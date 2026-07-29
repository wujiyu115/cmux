import 'package:uuid/uuid.dart';

import '../../cubits/chat/chat_tab_store.dart';
import '../../cubits/chat/model/chat_state.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/model/session_connect_request.dart';
import '../../cubits/chat/model/session_create_request.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/model/session_persist_params.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/cli_tool.dart';
import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import '../../utils/logging/logger.dart';
import 'launch_operation.dart';
import 'launch_outcome.dart';
import 'session_default_materializer.dart';
import 'session_launch_open_validator.dart';
import 'session_launch_workspace_index.dart';
import 'session_provisional_builder.dart';
import 'session_tab_surface_coordinator.dart';

/// Routes [LaunchOperation] through validate, surface, and connect stages.
class SessionLaunchPipeline {
  SessionLaunchPipeline({
    required SessionLaunchHost host,
    required ChatTabStore tabStore,
    required ChatState Function() state,
    required SessionLaunchWorkspaceIndex Function() workspaceIndex,
    required SessionTabSurfaceCoordinator tabSurface,
    required SessionDefaultMaterializer materializer,
    required void Function() disconnectSession,
    required ChatTab? Function() activeTab,
    required Uuid uuid,
  }) : _host = host,
       _tabStore = tabStore,
       _state = state,
       _workspaceIndex = workspaceIndex,
       _tabSurface = tabSurface,
       _materializer = materializer,
       _disconnectSession = disconnectSession,
       _activeTab = activeTab,
       _uuid = uuid;

  final SessionLaunchHost _host;
  final ChatTabStore _tabStore;
  final ChatState Function() _state;
  final SessionLaunchWorkspaceIndex Function() _workspaceIndex;
  final SessionTabSurfaceCoordinator _tabSurface;
  final SessionDefaultMaterializer _materializer;
  final void Function() _disconnectSession;
  final ChatTab? Function() _activeTab;
  final Uuid _uuid;

  Workspace? _workspaceById(String workspaceId) =>
      _workspaceIndex().byId(workspaceId);

  Future<LaunchOutcome> run(LaunchOperation operation) async {
    return switch (operation) {
      OpenSessionOperation(:final request) => _runOpen(request),
      CreateSessionOperation(:final request) => _runCreate(request),
      ConnectWorkspaceOperation(:final request, :final repo) =>
        _runConnect(request, repo: repo),
      RestartWorkspaceOperation(:final request, :final repo) =>
        _runRestart(request, repo: repo),
    };
  }

  Future<LaunchOpened> _runOpen(SessionOpenRequest request) async {
    final session = request.session;
    appLogger.d(
      '[session-launch] pipeline open start '
      'session=${session.sessionId} '
      'connectImmediately=${request.connectImmediately}',
    );

    final blocked = validateSessionOpenRequest(
      request: request,
      session: session,
      workspaceById: _workspaceById,
    );
    if (blocked != null) return LaunchOpened(blocked);

    final existingIdx = _tabStore.activeIndexOfSession(session.sessionId);
    if (existingIdx != -1) {
      final status = _tabSurface.surfaceExistingTab(
        request: request.withSession(session),
        existingIdx: existingIdx,
      );
      return LaunchOpened(status);
    }
    final status = _tabSurface.surfaceNewTab(
      request: request.withSession(session),
      session: session,
    );
    return LaunchOpened(status);
  }

  Future<LaunchOpened> _runCreate(SessionCreateRequest request) async {
    appLogger.d(
      '[session-launch] pipeline create start '
      'workspace=${request.workspace.workspaceId}',
    );

    final fixedId = request.fixedSessionId?.trim();
    final sessionId = fixedId != null && fixedId.isNotEmpty
        ? fixedId
        : _uuid.v4();
    final provisional = buildProvisionalSession(
      sessionId: sessionId,
      workspace: request.workspace,
      cli: request.cli,
      simpleIdentity: request.simpleIdentity,
      workingDirectory: request.workingDirectory,
    );
    _host.appendSessionSnapshot(provisional);

    final persistParams = SessionPersistParams(
      cli: request.cli,
      simpleIdentity: request.simpleIdentity,
      workingDirectory: request.workingDirectory,
      continueOverrides: request.continueOverrides,
    );

    final status = _tabSurface.surfaceNewTab(
      request: SessionOpenRequest(
        session: provisional,
        workspace: request.workspace,
        repo: request.repo,
        emptyDisplayTitleFallback: request.emptyDisplayTitleFallback,
        preserveWorkbenchView: request.preserveWorkbenchView,
        persistParams: persistParams,
      ),
      session: provisional,
    );
    return LaunchOpened(status);
  }

  Future<LaunchOutcome> _runConnect(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) async {
    if (_state().isActiveSessionConnecting) {
      return LaunchSkipped();
    }

    switch (request) {
      case PersonalSessionConnect(:final workspaceId, :final cliOverride):
        await _connectPersonalSession(
          workspaceId: workspaceId,
          cliOverride: cliOverride,
          repo: repo,
        );
      case ExistingSessionConnect(
        :final session,
        :final workspace,
        :final preserveWorkbenchView,
      ):
        await _connectExistingSession(
          session: session,
          workspace: workspace,
          preserveWorkbenchView: preserveWorkbenchView,
          repo: repo,
        );
    }
    return LaunchCompleted();
  }

  Future<LaunchOutcome> _runRestart(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) async {
    _disconnectSession();
    await _runConnect(request, repo: repo);
    return LaunchCompleted();
  }

  Future<void> _connectPersonalSession({
    required String workspaceId,
    CliTool? cliOverride,
    SessionRepository? repo,
  }) async {
    final r = repo ?? _host.sessionRepository;
    if (r == null) {
      _host.failSessionConnect('pending', 'Session repository unavailable.');
      return;
    }
    final workspace = _workspaceById(workspaceId);
    if (workspace == null) {
      _host.failSessionConnect('pending', 'Workspace not found.');
      return;
    }
    if (_tabStore.activeTabsIsEmpty) {
      _host.beginSessionConnect('pending');
      try {
        await _materializer.materializePersonalSession(
          workspace,
          r,
          connectImmediately: true,
          cliOverride: cliOverride,
        );
      } on Object catch (e, st) {
        appLogger.e(
          'connectPersonalSession: materialize failed: $e',
          stackTrace: st,
        );
        _host.failSessionConnect('pending', 'Failed to create session: $e');
      }
      return;
    }
    final tab = _activeTab();
    final session = tab?.persistedSession;
    if (tab == null || session == null) {
      _host.failSessionConnect('pending', 'No active personal session tab.');
      return;
    }
    await _runOpen(
      SessionOpenRequest(
        session: session,
        workspace: _workspaceById(session.workspaceId),
        repo: r,
        connectImmediately: true,
      ),
    );
  }

  Future<void> _connectExistingSession({
    required AppSession session,
    Workspace? workspace,
    bool preserveWorkbenchView = false,
    SessionRepository? repo,
  }) async {
    final r = repo ?? _host.sessionRepository;
    if (r == null) {
      _host.failSessionConnect(
        session.sessionId,
        'Session repository unavailable.',
      );
      return;
    }

    final tab = _tabStore.openTabBySessionId(session.sessionId);
    if (tab == null) {
      _host.failSessionConnect(session.sessionId, 'Session tab is not open.');
      return;
    }

    tab.selectedMemberId = session.sessionId;
    _host.selectMember(session.sessionId);

    // Prefer the freshest in-memory snapshot (launchState / native ids) over a
    // stale tab.persistedSession left at create-time.
    AppSession launchSession = tab.persistedSession ?? session;
    for (final s in _state().sessions) {
      if (s.sessionId == session.sessionId) {
        launchSession = s;
        break;
      }
    }
    tab.persistedSession = launchSession;

    if (_tabStore.activeIndexOfSession(session.sessionId) == -1) {
      appLogger.w(
        '[session-launch] existing session connect tab not in foreground bucket '
        'session=${session.sessionId} active=${_tabStore.activeWorkspaceId} '
        'tabWorkspace=${tab.workspaceId}',
      );
      _host.failSessionConnect(
        session.sessionId,
        'Session tab is not active in this workspace.',
      );
      return;
    }

    await _runOpen(
      SessionOpenRequest(
        session: launchSession,
        workspace: workspace ?? _workspaceById(session.workspaceId),
        repo: r,
        connectImmediately: true,
        preserveWorkbenchView: preserveWorkbenchView,
      ),
    );
  }
}
