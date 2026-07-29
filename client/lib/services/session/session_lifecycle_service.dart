import 'package:flutter/foundation.dart';

import '../../models/workspace.dart';
import '../../models/app_session.dart';
import '../../models/workspace_launch_context.dart';
import '../storage/app_storage.dart';
import '../../models/runtime_target.dart';
import '../io/local_filesystem.dart';
import '../storage/runtime_context.dart';


typedef StorageRootsResolver = Future<RuntimeContext> Function();

class SessionLifecycleService {
  SessionLifecycleService({
    String? appDataBasePath,
    StorageRootsResolver? storageRootsResolver,
    Future<RuntimeContext> Function(RuntimeTarget target)? workContextResolver,
  }) : _appDataBasePath = appDataBasePath,
       _storageRootsResolver = storageRootsResolver,
       _workContextResolver = workContextResolver;

  final String? _appDataBasePath;
  final StorageRootsResolver? _storageRootsResolver;

  /// P2: resolves the work-plane context for a workspace's target (local/wsl/
  /// ssh). When set, launch resolves runtime trees on the workspace's machine;
  /// session metadata still lives on home.
  final Future<RuntimeContext> Function(RuntimeTarget target)?
  _workContextResolver;

  bool _isPersonalLaunch(Workspace? workspace, AppSession session) =>
      workspace != null;

  /// Test-only seam for [_isPersonalLaunch].
  @visibleForTesting
  bool debugIsPersonalLaunch(Workspace workspace, AppSession session) =>
      _isPersonalLaunch(workspace, session);


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
    final fallback = ctx.folderCatalog.isEmpty ? null : ctx.folderCatalog.first;
    return _runtimeTargetFromId(fallback?.targetId ?? RuntimeTarget.localId);
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

}
