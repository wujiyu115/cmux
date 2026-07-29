import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:uuid/uuid.dart';

import '../models/workspace.dart';
import '../models/workspace_topology.dart';
import '../models/workspace_folder.dart';
import '../models/app_session.dart';
import '../models/session_continue_overrides.dart';
import '../models/cli_tool.dart';
import '../services/storage/app_storage.dart';
import '../models/workspace_icon_ref.dart';
import '../services/workspace/target_liveness.dart';
import '../services/workspace/workspace_icon_service.dart';
import '../services/workspace/workspace_icon_storage.dart';
import '../services/workspace/workspace_target_remap.dart';
import '../utils/lock_pool.dart';
import '../utils/logging/logger.dart';
import '../utils/workspace/workspace_path_utils.dart';
import '../utils/session/workspace_sessions.dart';
import 'session_repository_fs.dart';
import 'workspace_index_store.dart';

class SessionRepository {
  SessionRepository({String? rootDir}) : _rootOverride = rootDir;

  final String? _rootOverride;
  final _sessionFileLocks = LockPool();
  static final Map<String, List<Workspace>> _workspacesIndexByRoot = {};

  String _workspacesIndexCacheKey() {
    if (_rootOverride != null) return _rootOverride;
    if (AppStorage.isInstalled) return AppStorage.appDataRoot;
    return AppStorage.paths.basePath;
  }

  void _invalidateWorkspacesIndexCache() {
    _workspacesIndexByRoot.remove(_workspacesIndexCacheKey());
  }

  List<Workspace> _rememberWorkspacesIndex(List<Workspace> workspaces) {
    final inferred = [
      for (final workspace in workspaces)
        _withInferredMemberPlacementInit(workspace),
    ];
    final remembered = List<Workspace>.unmodifiable(inferred);
    _workspacesIndexByRoot[_workspacesIndexCacheKey()] = remembered;
    return remembered;
  }

  Future<T> _withSessionFile<T>(String sessionId, Future<T> Function() fn) {
    return _sessionFileLocks.synchronized(sessionId, fn);
  }

  Future<SessionRepositoryFs> _fs() async {
    // Explicit rootDir override (tests) wins; otherwise the home control plane.
    if (_rootOverride != null) {
      return SessionRepositoryFs(teampilotRoot: _rootOverride);
    }
    if (AppStorage.isInstalled) {
      final snap = AppStorage.context;
      return SessionRepositoryFs(
        teampilotRoot: snap.teampilotRoot,
        fs: snap.fs,
        layout: snap.workspace,
      );
    }
    return SessionRepositoryFs(teampilotRoot: AppStorage.paths.basePath);
  }

  Future<Workspace?> _readManifest(
    SessionRepositoryFs fs,
    String workspaceId, {
    bool indexOnly = false,
  }) async {
    final raw = await fs.readText(fs.manifestFile(workspaceId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        final workspace = Workspace.fromJson(json);
        final sessionIds = indexOnly
            ? await fs.listSessionDirectoryIds(workspaceId)
            : await fs.listSessionIdsForWorkspace(workspaceId);
        // Migration: infer mixed placement init in-memory only when remembered
        // targets are non-empty and all host ids are still in the workspace.
        // Roster/lead is unavailable at load, so pass members: [] (lead check
        // vacuous). Disk is not rewritten here — next explicit placement save
        // persists the flag.
        return _withInferredMemberPlacementInit(
          workspace.copyWith(sessionIds: sessionIds),
        );
      }
    } on Object {
      // ignore
    }
    return null;
  }

  /// In-memory migration for mixed workspaces that already have valid pins.
  ///
  /// Skips teams with an explicit `false` entry (host-set / topology reset)
  /// so load-time infer does not undo a deliberate re-confirm requirement.
  static Workspace _withInferredMemberPlacementInit(Workspace workspace) {
    if (workspaceTopologyOf(workspace.folders) != WorkspaceTopology.mixed) {
      return workspace;
    }
    if (workspace.memberTargetsByTeam.isEmpty) return workspace;

    var nextInitialized = workspace.memberPlacementInitializedByTeam;
    var changed = false;
    for (final entry in workspace.memberTargetsByTeam.entries) {
      final teamId = entry.key.trim();
      if (teamId.isEmpty) continue;
      // Missing key → eligible for migration infer.
      // Explicit true → already initialized.
      // Explicit false → host-set reset; do not re-infer.
      if (nextInitialized.containsKey(teamId)) continue;
      final targets = rememberedMemberTargets(
        workspace.memberTargetsByTeam,
        teamId,
      );
      if (!inferMemberPlacementInitialized(
        folders: workspace.folders,
        targets: targets,
        alreadyInitialized: false,
      )) {
        continue;
      }
      if (!changed) {
        nextInitialized = Map<String, bool>.from(nextInitialized);
        changed = true;
      }
      nextInitialized[teamId] = true;
    }
    if (!changed) return workspace;
    return workspace.copyWith(
      memberPlacementInitializedByTeam: nextInitialized,
    );
  }

  Future<void> _writeManifest(
    SessionRepositoryFs fs,
    Workspace workspace,
  ) async {
    await fs.ensureWorkspaceDir(workspace.workspaceId);
    final withoutSessions = workspace.copyWith(sessionIds: const []);
    await fs.writeText(
      fs.manifestFile(workspace.workspaceId),
      const JsonEncoder.withIndent('  ').convert(withoutSessions.toJson()),
    );
    await _syncWorkspaceIndexEntry(fs, workspace);
  }

  Future<void> _syncWorkspaceIndexEntry(
    SessionRepositoryFs fs,
    Workspace workspace,
  ) async {
    _invalidateWorkspacesIndexCache();
    final sessionIds = await fs.listSessionDirectoryIds(workspace.workspaceId);
    await WorkspaceIndexStore(
      fs,
    ).upsert(workspace.copyWith(sessionIds: sessionIds));
  }

  static bool _sameWorkspaceIds(
    List<String> diskIds,
    List<Workspace> snapshot,
  ) {
    if (diskIds.length != snapshot.length) return false;
    final diskSet = diskIds.toSet();
    return snapshot.every(
      (workspace) => diskSet.contains(workspace.workspaceId),
    );
  }

  Future<List<Workspace>> loadWorkspaces() => _loadWorkspaces(indexOnly: false);

  /// Manifest + session directory names only — no per-session JSON reads.
  ///
  /// Reads [workspaces-index.json] when present and workspace ids still match
  /// disk; otherwise rebuilds the snapshot from per-workspace manifests.
  Future<List<Workspace>> loadWorkspacesIndex() async {
    final cached = _workspacesIndexByRoot[_workspacesIndexCacheKey()];
    if (cached != null) {
      appLogger.i(
        '[boot] loadWorkspacesIndex from memory count=${cached.length}',
      );
      return cached;
    }
    final fs = await _fs();
    final store = WorkspaceIndexStore(fs);
    final readSw = Stopwatch()..start();
    final snapshot = await store.tryRead();
    final readMs = readSw.elapsedMilliseconds;
    if (snapshot != null) {
      appLogger.i(
        '[boot] loadWorkspacesIndex from snapshot count=${snapshot.length} '
        'read=${readMs}ms (validate deferred)',
      );
      unawaited(_revalidateWorkspacesIndexSnapshot(fs, store, snapshot));
      return _rememberWorkspacesIndex(snapshot);
    } else {
      appLogger.i(
        '[boot] loadWorkspacesIndex rebuilding snapshot read=${readMs}ms',
      );
    }
    final workspaces = await _loadWorkspaces(indexOnly: true);
    await store.writeAll(workspaces);
    return _rememberWorkspacesIndex(workspaces);
  }

  Future<void> _revalidateWorkspacesIndexSnapshot(
    SessionRepositoryFs fs,
    WorkspaceIndexStore store,
    List<Workspace> snapshot,
  ) async {
    final validateSw = Stopwatch()..start();
    final diskIds = await fs.listWorkspaceIds();
    final validateMs = validateSw.elapsedMilliseconds;
    if (_sameWorkspaceIds(diskIds, snapshot)) {
      appLogger.i('[boot] loadWorkspacesIndex validate ok +${validateMs}ms');
      return;
    }
    appLogger.i(
      '[boot] loadWorkspacesIndex snapshot stale '
      'disk=${diskIds.length} index=${snapshot.length} '
      'validate=${validateMs}ms',
    );
    final workspaces = await _loadWorkspaces(indexOnly: true);
    await store.writeAll(workspaces);
    _rememberWorkspacesIndex(workspaces);
  }

  Future<List<Workspace>> _loadWorkspaces({required bool indexOnly}) async {
    final fs = await _fs();
    final workspaceIds = await fs.listWorkspaceIds();
    final workspaces = await Future.wait(
      workspaceIds.map(
        (workspaceId) => _readManifest(fs, workspaceId, indexOnly: indexOnly),
      ),
    );
    return [
      for (final workspace in workspaces)
        if (workspace != null) workspace,
    ];
  }

  Future<List<AppSession>> loadSessions() async {
    final fs = await _fs();
    final workspaceIds = await fs.listWorkspaceIds();
    final mapsPerWorkspace = await Future.wait(
      workspaceIds.map(fs.listSessionJsonMapsForWorkspace),
    );
    final sessions = <AppSession>[];
    for (final maps in mapsPerWorkspace) {
      for (final json in maps) {
        try {
          sessions.add(AppSession.fromJson(json));
        } on Object {
          continue;
        }
      }
    }
    sessions.sort((a, b) {
      final au = a.updatedAt != 0 ? a.updatedAt : a.createdAt;
      final bu = b.updatedAt != 0 ? b.updatedAt : b.createdAt;
      return bu.compareTo(au);
    });
    return sessions;
  }

  Future<List<AppSession>> loadSessionsForWorkspace(String workspaceId) async {
    final fs = await _fs();
    final sessions = <AppSession>[];
    for (final json in await fs.listSessionJsonMapsForWorkspace(workspaceId)) {
      try {
        sessions.add(AppSession.fromJson(json));
      } on Object {
        continue;
      }
    }
    sessions.sort((a, b) {
      final au = a.updatedAt != 0 ? a.updatedAt : a.createdAt;
      final bu = b.updatedAt != 0 ? b.updatedAt : b.createdAt;
      return bu.compareTo(au);
    });
    return sessions;
  }

  /// Creates a workspace for [primaryPath].
  ///
  /// By default, an existing workspace with the same normalized [primaryPath]
  /// is reused: its folders and [display] are merged and it is returned
  /// instead of creating a duplicate. This keeps folder-merge
  /// ([SessionDataStore.addWorkspaceDirectory]) and bootstrap seeding
  /// idempotent. Pass [allowDuplicate] to skip reuse and always create a new,
  /// independent workspace on the same directory (the explicit "New Workspace"
  /// action) — multiple workspaces may then point at one directory.
  Future<Workspace> createWorkspace(
    List<WorkspaceFolder> folders, {
    String display = '',
    bool allowDuplicate = false,
  }) async {
    final fs = await _fs();
    final normalized = [
      for (final f in folders)
        if (f.path.trim().isNotEmpty)
          f.copyWith(path: normalizeWorkspacePath(f.path)),
    ];
    if (normalized.isEmpty) {
      throw ArgumentError('createWorkspace requires at least one folder path');
    }
    final primary = normalized.first.path;
    final now = DateTime.now().millisecondsSinceEpoch;
    final workspaces = await loadWorkspaces();
    for (final existing in allowDuplicate ? const <Workspace>[] : workspaces) {
      if (!workspacePathsEqual(existing.firstFolderPath, primary)) {
        continue;
      }
      final merged = List<WorkspaceFolder>.from(existing.folders);
      for (final f in normalized.skip(1)) {
        if (!merged.any((e) => workspacePathsEqual(e.path, f.path))) {
          merged.add(f);
        }
      }
      final trimmedDisplay = display.trim();
      final displayOut = trimmedDisplay.isNotEmpty
          ? trimmedDisplay
          : existing.display;
      if (listEquals(merged, existing.folders) &&
          displayOut == existing.display) {
        return existing;
      }
      final updated = existing.copyWith(
        folders: merged,
        display: displayOut,
        updatedAt: now,
      );
      await _writeManifest(fs, updated);
      return updated;
    }
    final workspace = Workspace(
      workspaceId: const Uuid().v4(),
      folders: normalized,
      display: display.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _writeManifest(fs, workspace);
    return workspace;
  }

  Future<void> updateWorkspaceMetadata(
    String workspaceId, {
    String? display,
    String? defaultProfileId,
    bool? rootSandboxEnvOptIn,
  }) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = existing.copyWith(
      display: display != null ? display.trim() : existing.display,
      defaultProfileId: defaultProfileId != null
          ? defaultProfileId.trim()
          : existing.defaultProfileId,
      folders: existing.folders,
      rootSandboxEnvOptIn: rootSandboxEnvOptIn ?? existing.rootSandboxEnvOptIn,
      updatedAt: now,
    );
    await _writeManifest(fs, updated);
  }

  Future<void> applyWorkspaceIcon(
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final workspaceDir = fs.workspaceDir(workspaceId);
    final iconService = WorkspaceIconService(
      storage: WorkspaceIconStorage(filesystem: fs.fs),
    );
    await iconService.deleteCustomFilesForTransition(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
      previous: existing.icon,
      next: icon,
    );
    await _writeManifest(fs, existing.copyWith(icon: icon, updatedAt: now));
  }

  Future<void> importCustomWorkspaceIcon(
    String workspaceId,
    String localSourcePath,
  ) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final workspaceDir = fs.workspaceDir(workspaceId);
    final iconService = WorkspaceIconService(
      storage: WorkspaceIconStorage(filesystem: fs.fs),
    );
    final customIcon = await iconService.importCustomFromLocalFile(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
      localSourcePath: localSourcePath,
    );
    await iconService.deleteCustomFilesForTransition(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
      previous: existing.icon,
      next: customIcon,
    );
    await _writeManifest(
      fs,
      existing.copyWith(icon: customIcon, updatedAt: now),
    );
  }

  /// Replace a workspace's folders wholesale (path + per-folder targetId).
  /// Used by the workspace target picker to move a workspace onto another
  /// machine (sets [WorkspaceFolder.targetId] on all folders).
  Future<void> updateWorkspaceFolders(
    String workspaceId,
    List<WorkspaceFolder> folders,
  ) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextFolders = [
      for (final f in folders)
        if (f.path.trim().isNotEmpty)
          f.copyWith(path: normalizeWorkspacePath(f.path)),
    ];
    final previousTopology = workspaceTopologyOf(existing.folders);
    final previousTargetIds = workspaceTargetIds(existing.folders);
    final nextTopology = workspaceTopologyOf(nextFolders);
    final nextTargetIds = workspaceTargetIds(nextFolders);
    final becameMixed =
        previousTopology != WorkspaceTopology.mixed &&
        nextTopology == WorkspaceTopology.mixed;
    final targetSetChanged = !_sameTargetIdSet(
      previousTargetIds,
      nextTargetIds,
    );
    final nextInitialized = (becameMixed || targetSetChanged)
        ? <String, bool>{
            for (final teamId in existing.memberTargetsByTeam.keys)
              if (teamId.trim().isNotEmpty) teamId.trim(): false,
          }
        : existing.memberPlacementInitializedByTeam;
    final updated = existing.copyWith(
      folders: nextFolders,
      memberPlacementInitializedByTeam: nextInitialized,
      updatedAt: now,
    );
    await _writeManifest(fs, updated);
  }

  static bool _sameTargetIdSet(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    return Set<String>.from(a).containsAll(b);
  }

  Future<Workspace> remapWorkspaceTarget(
    String workspaceId, {
    required String fromTargetId,
    required String toTargetId,
    required TargetLiveness liveness,
  }) async {
    final from = fromTargetId.trim();
    final to = toTargetId.trim();
    if (from.isEmpty || to.isEmpty) {
      throw ArgumentError('fromTargetId and toTargetId must be non-empty');
    }
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) {
      throw StateError('Workspace "$workspaceId" not found');
    }
    final sessions = await loadSessionsForWorkspace(workspaceId);
    if (!WorkspaceTargetRemap.usesTarget(
      folders: existing.folders,
      memberTargetsByTeam: existing.memberTargetsByTeam,
      sessions: sessions,
      targetId: from,
    )) {
      throw StateError('Nothing to remap for target "$from"');
    }
    if (from != to && !await liveness.isAlive(to)) {
      throw StateError('Destination target "$to" is not available');
    }

    final applied = WorkspaceTargetRemap.apply(
      folders: existing.folders,
      memberTargetsByTeam: existing.memberTargetsByTeam,
      sessions: sessions,
      fromTargetId: from,
      toTargetId: to,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = existing.copyWith(
      folders: applied.folders,
      memberTargetsByTeam: applied.memberTargetsByTeam,
      updatedAt: now,
    );
    await _writeManifest(fs, updated);

    for (final session in applied.sessions) {
      try {
        await _writeSession(fs, session.copyWith(updatedAt: now));
      } on Object catch (error, stackTrace) {
        appLogger.e(
          '[workspace] remap session write failed '
          'workspace=$workspaceId session=${session.sessionId}',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }
    return updated;
  }


  Future<AppSession> createSession(
    String workspaceId, {
    CliTool? cli,
    String? provider,
    String? model,
    String? effort,
    String? presetId,
    String? workingDirectory,
    String? fixedSessionId,
    SessionContinueOverrides? continueOverrides,
  }) async {
    final fs = await _fs();
    var workspace = await _readManifest(fs, workspaceId);
    if (workspace == null) {
      throw StateError('Unknown workspaceId: $workspaceId');
    }
    final pinnedId = fixedSessionId?.trim() ?? '';
    final sessionId = pinnedId.isNotEmpty ? pinnedId : const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = AppSession(
      sessionId: sessionId,
      workspaceId: workspaceId,
      folders: Workspace.foldersForPrimaryPath(
        workspace.folders,
        workingDirectory ?? '',
      ),
      display: '',
      profileId: '',
      cli: cli,
      provider: provider?.trim() ?? '',
      model: model?.trim() ?? '',
      effort: effort?.trim() ?? '',
      presetId: presetId?.trim() ?? '',
      memberTargets: const {},
      launchState: AppSessionLaunchState.created,
      createdAt: now,
      updatedAt: now,
      continueOverrides: continueOverrides ?? const SessionContinueOverrides(),
    );
    await fs.ensureSessionDir(workspaceId, sessionId);
    await fs.writeText(
      fs.sessionFile(workspaceId, sessionId),
      jsonEncode(session.toJson()),
    );
    await _syncWorkspaceIndexEntry(fs, workspace);
    return session;
  }

  Future<AppSession?> _readSession(
    SessionRepositoryFs fs,
    String workspaceId,
    String sessionId,
  ) async {
    final raw = await fs.readText(fs.sessionFile(workspaceId, sessionId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        return AppSession.fromJson(json);
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<AppSession?> _findSession(
    SessionRepositoryFs fs,
    String sessionId,
  ) async {
    for (final workspaceId in await fs.listWorkspaceIds()) {
      final session = await _readSession(fs, workspaceId, sessionId);
      if (session != null) return session;
    }
    return null;
  }

  Future<void> _writeSession(SessionRepositoryFs fs, AppSession session) async {
    final workspaceId = session.workspaceId.trim();
    if (workspaceId.isEmpty) {
      throw StateError('Session ${session.sessionId} missing workspaceId');
    }
    await fs.writeText(
      fs.sessionFile(workspaceId, session.sessionId),
      jsonEncode(session.toJson()),
    );
  }

  Future<void> markSessionLaunched(String sessionId) {
    return markSessionStarted(sessionId);
  }

  Future<void> markSessionStarted(String sessionId) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      if (existing.launchState == AppSessionLaunchState.started) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(
          launchState: AppSessionLaunchState.started,
          updatedAt: now,
        ),
      );
    });
  }

  Future<void> renameSession(String sessionId, String newName) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(display: newName, updatedAt: now),
      );
    });
  }

  Future<void> touchSession(String sessionId) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(fs, existing.copyWith(updatedAt: now));
    });
  }

  Future<void> toggleSessionPin(String sessionId) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(pinned: !existing.pinned, updatedAt: now),
      );
    });
  }

  Future<void> updateContinueOverrides(
    String sessionId,
    SessionContinueOverrides overrides,
  ) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(continueOverrides: overrides, updatedAt: now),
      );
    });
  }

  /// Patches Simple-launch identity fields without touching [AppSession.continueOverrides].
  Future<void> updateSimpleLaunchIdentity(
    String sessionId, {
    String? presetId,
    String? provider,
    String? model,
    String? effort,
  }) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(
          presetId: presetId != null ? presetId.trim() : existing.presetId,
          provider: provider != null ? provider.trim() : existing.provider,
          model: model != null ? model.trim() : existing.model,
          effort: effort != null ? effort.trim() : existing.effort,
          updatedAt: now,
        ),
      );
    });
  }

  /// Persists a manual arrangement: stamps each session's [AppSession.sortOrder]
  /// to its position in [orderedSessionIds] (1-based, so untouched sessions at
  /// the default `0` keep sorting first). Sessions absent from disk are skipped.
  Future<void> reorderSessions(List<String> orderedSessionIds) async {
    for (var i = 0; i < orderedSessionIds.length; i++) {
      final sessionId = orderedSessionIds[i];
      final order = i + 1;
      await _withSessionFile(sessionId, () async {
        final fs = await _fs();
        final existing = await _findSession(fs, sessionId);
        if (existing == null || existing.sortOrder == order) return;
        await _writeSession(fs, existing.copyWith(sortOrder: order));
      });
    }
  }

  Future<void> deleteSession(String sessionId) async {
    await _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final workspaceId = existing.workspaceId.trim();
      await fs.deleteSessionDir(workspaceId, sessionId);
      final workspace = await _readManifest(fs, workspaceId);
      if (workspace != null) {
        await _writeManifest(
          fs,
          workspace.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch),
        );
      }
    });
  }

  Future<Workspace> cloneWorkspace(
    String sourceWorkspaceId, {
    String? display,
  }) async {
    final fs = await _fs();
    final source = await _readManifest(fs, sourceWorkspaceId);
    if (source == null) {
      throw StateError('Unknown workspaceId: $sourceWorkspaceId');
    }

    final sourceSessions = sessionsForWorkspace(source, await loadSessions());
    final now = DateTime.now().millisecondsSinceEpoch;
    final newWorkspaceId = const Uuid().v4();
    final newWorkspace = Workspace(
      workspaceId: newWorkspaceId,
      folders: List.of(source.folders),
      display: (display ?? source.display).trim(),
      icon: source.icon,
      createdAt: now,
      updatedAt: now,
    );
    await _writeManifest(fs, newWorkspace);

    for (final old in sourceSessions) {
      await _cloneSessionRecord(
        fs,
        old,
        newWorkspaceId,
      );
    }

    await _syncWorkspaceIndexEntry(fs, newWorkspace);

    return (await _readManifest(fs, newWorkspaceId)) ?? newWorkspace;
  }

  Future<AppSession> _cloneSessionRecord(
    SessionRepositoryFs fs,
    AppSession source,
    String targetWorkspaceId,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sessionId = const Uuid().v4();
    final session = AppSession(
      sessionId: sessionId,
      workspaceId: targetWorkspaceId,
      folders: List.of(source.folders),
      display: source.display,
      launchState: AppSessionLaunchState.created,
      createdAt: now,
      updatedAt: now,
    );
    await fs.ensureSessionDir(targetWorkspaceId, sessionId);
    await _writeSession(fs, session);
    return session;
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    final fs = await _fs();
    final workspace = await _readManifest(fs, workspaceId);
    if (workspace == null) return;

    final sessions = sessionsForWorkspace(workspace, await loadSessions());
    for (final session in sessions) {
      await deleteSession(session.sessionId);
    }

    await WorkspaceIconService(
      storage: WorkspaceIconStorage(filesystem: fs.fs),
    ).deleteAllCustomFilesForWorkspace(
      workspaceDir: fs.workspaceDir(workspaceId),
      workspaceId: workspaceId,
      icon: workspace.icon,
    );

    await fs.deleteWorkspaceDir(workspaceId);
    _invalidateWorkspacesIndexCache();
    await WorkspaceIndexStore(fs).remove(workspaceId);
  }
}
