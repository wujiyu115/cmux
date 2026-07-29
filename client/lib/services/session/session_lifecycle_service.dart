import 'package:flutter/foundation.dart';

import '../../models/workspace.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/session_member_binding.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';
import '../../repositories/cli_presets_repository.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../../utils/logging/logger.dart';
import '../../models/workspace_topology.dart';
import '../../models/workspace_launch_context.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_layout.dart';
import '../cli/registry/capabilities/resume/pinned_transcript_probe.dart';
import '../cli/registry/capabilities/session_resume_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../provider/control_plane_profile_paths.dart';
import '../provider/config_profile_service.dart';
import '../../models/runtime_target.dart';
import '../io/local_filesystem.dart';
import '../storage/runtime_context.dart';
import '../io/filesystem.dart';


typedef StorageRootsResolver = Future<RuntimeContext> Function();

class SessionLifecycleService {
  static final _defaultCliRegistry = () {
    final registry = CliToolRegistry.builtIn();
    return registry;
  }();

  SessionLifecycleService({
    String? appDataBasePath,
    ConfigProfileService? configProfileService,
    StorageRootsResolver? storageRootsResolver,
    Future<RuntimeContext> Function(RuntimeTarget target)? workContextResolver,
    Future<RuntimeContext> Function()? catalogContextResolver,
    Future<Set<String>> Function({String? teamId, String? workspaceId})?
    loadEnabledExtensionIds,
    CliToolRegistry? cliToolRegistry,
    Future<List<Skill>> Function()? loadInstalledSkills,
    CliPresetsRepository? cliPresetsRepository,
    List<CliPreset> Function()? loadPresets,
  }) : _appDataBasePath = appDataBasePath,
       _configProfileService = configProfileService,
       _storageRootsResolver = storageRootsResolver,
       _workContextResolver = workContextResolver,
       _catalogContextResolver = catalogContextResolver,
       _loadEnabledExtensionIds = loadEnabledExtensionIds,
       _cliToolRegistry = cliToolRegistry ?? _defaultCliRegistry,
       _loadInstalledSkills = loadInstalledSkills,
       _cliPresetsRepository = cliPresetsRepository,
       _loadPresets = loadPresets;

  final String? _appDataBasePath;
  final ConfigProfileService? _configProfileService;
  final StorageRootsResolver? _storageRootsResolver;

  /// P2: resolves the work-plane context for a workspace's target (local/wsl/
  /// ssh). When set, launch resolves runtime trees on the workspace's machine;
  /// session metadata still lives on home.
  final Future<RuntimeContext> Function(RuntimeTarget target)?
  _workContextResolver;

  /// Control-plane context (`registry.home()`). Provider catalog reads use this
  /// even when the member launches on a remote work machine.
  final Future<RuntimeContext> Function()? _catalogContextResolver;
  final Future<Set<String>> Function({String? teamId, String? workspaceId})?
  _loadEnabledExtensionIds;
  final CliToolRegistry _cliToolRegistry;
  final Future<List<Skill>> Function()? _loadInstalledSkills;
  final CliPresetsRepository? _cliPresetsRepository;
  final List<CliPreset> Function()? _loadPresets;

  List<CliPreset> get globalPresets => _loadPresets?.call() ?? const [];

  CliToolRegistry get cliToolRegistry => _cliToolRegistry;

  /// Resolves a global CLI preset by id.
  Future<CliPreset?> resolvePresetById(String presetId) async {
    final trimmed = presetId.trim();
    if (trimmed.isEmpty) return null;
    final repo = _cliPresetsRepository;
    if (repo == null) return null;
    final presets = await repo.load();
    return resolveActivePreset(trimmed, presets);
  }

  Future<bool> hasCliState(
    AppSession session, {
    String? teamId,
    CliTool? cli,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
  }) async {
    final roots = await _resolveRoots(
      session: session,
      memberId: memberBinding?.rosterMemberId,
    );
    final isPersonal = _isPersonalLaunch(workspace, session);
    final runtimeTeamId = isPersonal
        ? session.sessionId.trim()
        : session.cliTeamName.trim().isNotEmpty
        ? session.cliTeamName.trim()
        : session.sessionId.trim();
    final cliSessionId =
        memberBinding?.taskId.trim() ?? session.sessionId.trim();
    CliTool? resolvedCli;
    if (isPersonal) {
      resolvedCli = session.cli ?? CliTool.claude;
    } else {
      resolvedCli = cli;
    }
    final probe = await _findCliState(
      roots: roots,
      session: session,
      teamId: (teamId ?? session.sessionTeam).trim(),
      runtimeSessionId: runtimeTeamId,
      cliSessionId: cliSessionId,
      cli: resolvedCli,
      workspaceId: isPersonal ? workspace!.workspaceId : null,
    );
    return probe.exists;
  }

  Future<void> destroyCliState({
    required String workspaceId,
    required String teamId,
    required String sessionId,
    AppSession? session,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedTeamId = teamId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty ||
        trimmedTeamId.isEmpty ||
        trimmedSessionId.isEmpty) {
      return;
    }

    // P2: clean the runtime tree on the *workspace's* machine (work plane),
    // resolved from the session's folder target, not always home.
    final roots = await _resolveRoots(session: session);
    final sessionRoot = roots.layout.workspace.sessionRuntimeDir(
      trimmedWorkspaceId,
      trimmedSessionId,
    );
    await _removeTree(roots, sessionRoot);
  }

  Future<void> destroyStandaloneCliState({
    required String workspaceId,
    required String sessionId,
    AppSession? session,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty || trimmedSessionId.isEmpty) return;

    final roots = await _resolveRoots(session: session);
    final sessionRoot = roots.layout.workspace.sessionRuntimeDir(
      trimmedWorkspaceId,
      trimmedSessionId,
    );
    await _removeTree(roots, sessionRoot);
  }

  Future<void> destroyCliToolState(String teamId) async {
    final trimmedTeamId = teamId.trim();
    if (trimmedTeamId.isEmpty) return;

    final roots = await _resolveRoots();
    final teamRoot = roots.fs.pathContext.dirname(
      roots.layout.identityToolDir(trimmedTeamId, 'flashskyai'),
    );
    await _removeTree(roots, teamRoot);
  }

  bool _isPersonalLaunch(Workspace? workspace, AppSession session) =>
      workspace != null && session.sessionTeam.trim().isEmpty;

  /// Test-only seam for [_isPersonalLaunch].
  @visibleForTesting
  bool debugIsPersonalLaunch(Workspace workspace, AppSession session) =>
      _isPersonalLaunch(workspace, session);

  List<String> _standaloneTranscriptSearchRoots({
    required RuntimeLayout layout,
    required String workspaceId,
    required String sessionId,
    required Iterable<String> tools,
  }) {
    final tt = tools.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return [
      for (final tool in tt) layout.appToolRoot(tool),
      for (final tool in tt) layout.workspaceConfigToolDir(workspaceId, tool),
      for (final tool in tt)
        layout.sessionRuntimeToolDir(workspaceId, sessionId, tool),
    ];
  }

  Future<ConfigProfileService> configProfileServiceFor(
    RuntimeContext roots, {
    String? launchWorkspaceId,
  }) => _configProfileServiceFor(roots, launchWorkspaceId: launchWorkspaceId);

  Future<ConfigProfileService> _configProfileServiceFor(
    RuntimeContext roots, {
    String? launchWorkspaceId,
  }) async {
    final injected = _configProfileService;
    if (injected != null) return injected;
    final loader = _loadEnabledExtensionIds;
    final trimmedWorkspaceId = launchWorkspaceId?.trim() ?? '';
    final catalogRoots = await _resolveCatalogRoots();
    final catalog = catalogRoots.appDataRoot == roots.appDataRoot
        ? null
        : ControlPlaneProfilePaths(catalogRoots);
    return ConfigProfileService(
      basePath: roots.teampilotRoot,
      home: roots.home,
      fs: roots.fs,
      layout: roots.layout,
      catalog: catalog,
      loadEnabledExtensionIds: loader == null
          ? null
          : ({teamId, workspaceId}) => loader(
              teamId: teamId,
              workspaceId: (workspaceId?.trim().isNotEmpty ?? false)
                  ? workspaceId
                  : (trimmedWorkspaceId.isNotEmpty ? trimmedWorkspaceId : null),
            ),
      cliRegistry: _cliToolRegistry,
      loadInstalledSkills: _loadInstalledSkills,
      loadGlobalPresets: () async => _loadPresets?.call() ?? const [],
    );
  }

  Future<RuntimeContext> _resolveCatalogRoots() async {
    final resolver = _catalogContextResolver ?? _storageRootsResolver;
    if (resolver != null) return resolver();
    return _localRoots(_appDataBasePath ?? AppStorage.paths.basePath);
  }

  /// Test seam: resolve the work-plane context for [session] (and optionally a
  /// [memberId], exercising the per-member folder-target → forTarget path).
  @visibleForTesting
  Future<RuntimeContext> debugResolveWorkContext(
    AppSession session, {
    String? memberId,
    Workspace? workspace,
  }) =>
      _resolveRoots(session: session, memberId: memberId, workspace: workspace);

  Future<RuntimeContext> _resolveRoots({
    AppSession? session,
    String? memberId,
    Workspace? workspace,
  }) async {
    final workResolver = _workContextResolver;
    if (session != null && workResolver != null) {
      final target = memberId != null
          ? _workTargetForMember(
              WorkspaceLaunchContext(
                session: session,
                workspace:
                    workspace ??
                    Workspace(
                      workspaceId: session.workspaceId,
                      folders: session.folders,
                      createdAt: 0,
                    ),
              ),
              memberId,
            )
          : _workTargetFor(session);
      return workResolver(target);
    }
    final resolver = _storageRootsResolver;
    if (resolver != null) return resolver();
    return _localRoots(_appDataBasePath ?? AppStorage.paths.basePath);
  }

  RuntimeTarget _runtimeTargetFromId(String id) => switch (runtimeKindOfId(
    id,
  )) {
    RuntimeKind.ssh => RuntimeTarget.ssh(sshProfileIdOfId(id) ?? '', label: ''),
    RuntimeKind.wsl => RuntimeTarget.wsl(wslDistroOfId(id) ?? ''),
    RuntimeKind.local => RuntimeTarget.local(),
  };

  /// Where the CLI process runs for this launch.
  ///
  /// Personal sessions omit [memberId] and use the workspace session target
  /// (`folders.first.targetId`). Team sessions pin each roster member via
  /// [memberId] → [AppSession.memberTargets].
  RuntimeTarget launchWorkTarget(
    WorkspaceLaunchContext ctx, {
    String? memberId,
  }) {
    final trimmed = memberId?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return _workTargetForMember(ctx, trimmed);
    }
    return _workTargetFor(ctx.session);
  }

  /// The runtime target of a session's workspace (P2: whole workspace = one
  /// target = `folders.first.targetId`).
  RuntimeTarget _workTargetFor(AppSession session) {
    final id = session.folders.isEmpty
        ? RuntimeTarget.localId
        : session.folders.first.targetId;
    return _runtimeTargetFromId(id);
  }

  Future<RuntimeContext> launchWorkContext(
    WorkspaceLaunchContext ctx, {
    String? memberId,
  }) => resolveWorkContextForTargetId(
    launchWorkTarget(ctx, memberId: memberId).id,
  );

  /// P3d: resolve the work-plane context for an arbitrary target id, so the
  /// cross-machine artifact service can read on the publisher's machine and
  /// write on the fetcher's machine. Falls back to the control-plane /home
  /// context when no work-plane resolver is wired (single-machine setups).
  Future<RuntimeContext> resolveWorkContextForTargetId(String targetId) {
    final resolver = _workContextResolver;
    if (resolver != null) return resolver(_runtimeTargetFromId(targetId));
    final fallback = _storageRootsResolver;
    if (fallback != null) return fallback();
    return Future.value(
      _localRoots(_appDataBasePath ?? AppStorage.paths.basePath),
    );
  }

  RuntimeTarget _workTargetForMember(
    WorkspaceLaunchContext ctx,
    String memberId,
  ) {
    final targetId = memberTargetForInstanceId(
      ctx.session.memberTargets,
      memberId,
    );
    if (targetId != null &&
        folderPathsForTarget(ctx.folderCatalog, targetId).isNotEmpty) {
      return _runtimeTargetFromId(targetId);
    }
    final fallback = ctx.folderCatalog.isEmpty ? null : ctx.folderCatalog.first;
    return _runtimeTargetFromId(fallback?.targetId ?? RuntimeTarget.localId);
  }

  bool memberTargetIsValid(WorkspaceLaunchContext ctx, String memberId) {
    final targetId = memberTargetForInstanceId(
      ctx.session.memberTargets,
      memberId,
    );
    if (targetId == null) return false;
    return folderPathsForTarget(ctx.folderCatalog, targetId).isNotEmpty;
  }

  ({String workingDirectory, List<String> addDirs}) memberWorkDirs(
    WorkspaceLaunchContext ctx,
    String memberId,
  ) => ctx.session.workDirsForMember(memberId, folders: ctx.folderCatalog);

  RuntimeContext _localRoots(String basePath) {
    return RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(basePath),
      ),
      home: basePath,
      cwd: basePath,
      appDataRoot: basePath,
      paths: AppPaths(basePath),
    );
  }

  /// Resolves the native session id for [cli] via its [SessionResumeCapability]
  /// (probe / scan / persisted / out-of-band allocate), then derives the
  /// create-vs-resume ids for the launch plan. See
  /// docs/session-resume-architecture.md.
  Future<_CliStateProbeResult> _findCliState({
    required RuntimeContext roots,
    required AppSession session,
    required String teamId,
    required String runtimeSessionId,
    required String cliSessionId,
    CliTool? cli,
    String? workspaceId,
  }) async {
    final id = cliSessionId.trim();
    if (id.isEmpty) {
      return const _CliStateProbeResult(exists: false);
    }

    final tools = cli != null ? [cli.value] : runtimeLayoutDefaultTools;
    final trimmedWorkspaceId = workspaceId?.trim() ?? '';
    final toolRoots = trimmedWorkspaceId.isNotEmpty
        ? _standaloneTranscriptSearchRoots(
            layout: roots.layout,
            workspaceId: trimmedWorkspaceId,
            sessionId: runtimeSessionId,
            tools: tools,
          )
        : roots.layout.transcriptSearchRoots(
            workspaceId: session.workspaceId.trim(),
            sessionId: session.sessionId.trim(),
            profileId: teamId,
            tools: tools,
          );
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
      session.firstFolderPath,
    );
    return _findCliStateInFilesystem(
      fs: roots.fs,
      toolRoots: toolRoots,
      sessionId: id,
      bucket: bucket,
    );
  }

  Future<_CliStateProbeResult> _findCliStateInFilesystem({
    required Filesystem fs,
    required Iterable<String> toolRoots,
    required String sessionId,
    required String bucket,
  }) async {
    final probe = await probePinnedTranscript(
      fs: fs,
      toolRoots: toolRoots,
      sessionId: sessionId,
      bucket: bucket,
      // Claude uses `projects/`; flashskyai uses `workspaces/`.
      layoutSegments: const ['projects', 'workspaces'],
    );
    if (!probe.exists) {
      return const _CliStateProbeResult(exists: false);
    }
    return _CliStateProbeResult(
      exists: true,
      rootsTried: toolRoots.toList(growable: false),
      matchedPath: probe.matchedPath,
    );
  }

  Future<void> _removeTree(RuntimeContext roots, String path) async {
    try {
      await roots.fs.removeRecursive(path);
    } on Object catch (e, st) {
      appLogger.w('[session-lifecycle] cleanup failed: $e', stackTrace: st);
    }
  }
}

class _CliStateProbeResult {
  const _CliStateProbeResult({
    required this.exists,
    this.rootsTried = const [],
    this.matchedPath,
  });

  final bool exists;
  final List<String> rootsTried;
  final String? matchedPath;
}
