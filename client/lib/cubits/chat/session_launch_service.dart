import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/runtime_target.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../repositories/session_repository.dart';
import '../../services/launch/connect_shell_result.dart';
import '../../services/launch/launch_operation.dart';
import '../../services/launch/launch_outcome.dart';
import '../../services/launch/session_launch_bundle.dart';
import '../../services/launch/session_launch_pipeline.dart';
import '../../services/launch/session_ssh_profile_reconnect.dart';
import '../../services/launch/session_prompt_metadata_sync.dart';
import '../../services/launch/session_shell_connector.dart';
import '../../services/launch/session_tab_connect_prep.dart';
import '../../services/launch/session_launch_workspace_index.dart';
import 'session_launch_host.dart';

export 'session_launch_host.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logging/logger.dart';
import 'chat_tab_store.dart';
import 'model/chat_state.dart';
import 'model/chat_tab.dart';
import 'model/session_create_request.dart';
import 'model/session_open_request.dart';
import 'model/session_open_status.dart';
import 'model/session_connect_request.dart';

/// Owns session launch orchestration: delegates user operations to
/// [SessionLaunchPipeline] and wires shell collaborators for the personal
/// (simple) launch path.
class SessionLaunchService implements SessionShellConnectorDelegate {
  SessionLaunchService(this._h);

  final SessionLaunchHost _h;
  late final SessionShellConnector _shellConnector = SessionShellConnector(
    _h,
    this,
  );
  late final SessionLaunchBundle _launch = SessionLaunchBundle.create(
    SessionLaunchBundleDeps(
      host: _h,
      tabStore: _tabStore,
      state: () => _h.state,
      workspaceIndex: () => _workspaceIndex,
      workspaceById: _workspaceById,
      prepCallbacks: _tabConnectCallbacks,
      shouldAutoConnect: _shouldAutoConnect,
      scheduleShellConnect: _scheduleShellConnect,
      rollbackStagedLaunch: _rollbackStagedLaunch,
      disconnectSession: disconnectSession,
      activeTab: () => _activeTab,
      isTabsEmpty: () => _tabStore.activeTabsIsEmpty,
      uuid: _uuid,
    ),
  );
  SessionLaunchPipeline get _pipeline => _launch.pipeline;
  late final SessionSshProfileReconnect _sshReconnect =
      SessionSshProfileReconnect(
        host: _h,
        shellConnector: _shellConnector,
        launchContextFor: launchContextFor,
        workspaceIndex: () => _workspaceIndex,
        openTabs: () => _tabStore.openTabs,
      );
  late final SessionPromptMetadataSync _promptMetadata =
      SessionPromptMetadataSync(host: _h, state: () => _h.state);
  static const _uuid = Uuid();

  SessionTabConnectPrepCallbacks get _tabConnectCallbacks => (
    persistSessionIfNeeded: _persistSessionIfNeeded,
    resolveLaunchMembers: _resolveLaunchMembers,
    updateSelectedMember: _updateSelectedMember,
    shellForLaunch: _shellForLaunch,
    launchStillValid: _launchStillValid,
  );

  ChatState get _state => _h.state;
  ChatTabStore get _tabStore => _h.tabStore;
  ChatTab? get _activeTab => _h.activeTab;

  SessionLaunchWorkspaceIndex get _workspaceIndex =>
      SessionLaunchWorkspaceIndex(
        workspaces: _state.workspaces,
        sessions: _state.sessions,
      );

  Workspace? _workspaceById(String workspaceId) =>
      _workspaceIndex.byId(workspaceId);

  void _updateSelectedMember(String memberId) {
    final tabMemberId = memberId;
    if (_state.selectedMemberId != tabMemberId) {
      _h.applyState(_state.copyWith(selectedMemberId: tabMemberId));
    }
  }

  Future<SessionOpenStatus> requestOpenSession(SessionOpenRequest request) =>
      _launch.openSession(request);

  /// Stages a new conversation tab immediately, then persists and connects async.
  Future<SessionOpenStatus> requestCreateAndOpenSession(
    SessionCreateRequest request,
  ) async {
    final outcome = await _pipeline.run(CreateSessionOperation(request));
    return switch (outcome) {
      LaunchOpened(:final status) => status,
      _ => SessionOpenStatus.opened,
    };
  }

  Future<AppSession> _persistSessionIfNeeded({
    required SessionOpenRequest request,
    required AppSession session,
    required ChatTab tab,
  }) async {
    final params = request.persistParams;
    if (params == null) return session;

    final repo = request.repo ?? _h.sessionRepository;
    if (repo == null) {
      throw StateError('Session repository unavailable');
    }

    final persisted = await repo.createSession(
      session.workspaceId,
      cli: params.simpleIdentity?.cli ?? params.cli,
      provider: params.simpleIdentity?.provider,
      model: params.simpleIdentity?.model,
      effort: params.simpleIdentity?.effort,
      presetId: params.simpleIdentity?.presetId,
      workingDirectory: params.workingDirectory,
      fixedSessionId: session.sessionId,
      continueOverrides: params.continueOverrides,
    );
    tab.persistedSession = persisted;
    _h.replaceSessionSnapshot(persisted);
    return persisted;
  }

  void _rollbackStagedLaunch({
    required ChatTab tab,
    required String sessionId,
    required SessionOpenRequest request,
    required String message,
  }) {
    _h.failSessionConnect(sessionId, message);
    if (request.persistParams == null) return;
    _h.closeSessionTab(sessionId);
    _h.removeSessionSnapshot(sessionId);
  }

  bool _shouldAutoConnect(SessionOpenRequest request) {
    return request.connectImmediately;
  }

  bool _launchStillValid(ChatTab tab, int generation) {
    if (_h.isClosed) return false;
    if (_tabStore.activeIndexOfSession(tab.info.id) == -1) return false;
    return tab.launchGeneration == generation;
  }

  Future<ResolvedLaunchMembers> _resolveLaunchMembers({
    required AppSession session,
    required SessionOpenRequest request,
    Workspace? workspace,
  }) async {
    final resolvedWorkspace = workspace ?? _workspaceById(session.workspaceId);
    if (resolvedWorkspace == null) {
      throw StateError('Session requires workspace');
    }
    return (memberId: session.sessionId, cli: session.simpleIdentity.cli);
  }

  void _scheduleShellConnect({
    required int generation,
    required ChatTab tab,
    required AppSession session,
    required TerminalSession shell,
    required SessionOpenRequest request,
    required bool launched,
    required Workspace? workspace,
    VoidCallback? onFinally,
  }) {
    _h.postFrameScheduler(() async {
      if (!_launchStillValid(tab, generation)) {
        _shellConnector.abortConnectShellIfStale(
          tab: tab,
          shell: shell,
          reason: 'launch_generation_stale',
          remoteMemberKey: session.sessionId,
        );
        return;
      }
      try {
        final result = await _shellConnector.connect(
          tab: tab,
          session: session,
          shell: shell,
          repo: request.repo,
          launched: launched,
          workspace: workspace,
        );
        switch (result) {
          case ConnectShellResult.attached:
            _h.updateTabRunning(tab.info.id);
          case ConnectShellResult.deferred:
            break;
          case ConnectShellResult.failed:
          case ConnectShellResult.aborted:
            break;
        }
      } on Object catch (e, st) {
        appLogger.e(
          '[session-launch] connect failed for ${tab.info.id}: $e',
          error: e,
          stackTrace: st,
        );
        final message = 'Failed to resume session: $e';
        shell.write('\r\n[$message]\r\n');
        unawaited(tab.closeMemberRemotePlane(session.sessionId));
        if (_launchStillValid(tab, generation)) {
          _h.failSessionConnect(tab.info.id, message);
        }
      } finally {
        onFinally?.call();
      }
    });
  }

  @override
  WorkspaceLaunchContext launchContextFor(AppSession session) =>
      WorkspaceLaunchContext(
        session: session,
        workspace:
            _workspaceById(session.workspaceId) ??
            Workspace(
              workspaceId: session.workspaceId,
              folders: session.folders,
              createdAt: 0,
            ),
      );

  RuntimeTarget _launchWorkTarget(AppSession session, {String? memberId}) => _h
      .lifecycle
      .launchWorkTarget(launchContextFor(session), memberId: memberId);

  /// Ensures [tab] holds a [TerminalSession] whose transport matches [session]'s
  /// launch target (local PTY vs SSH) and whose executable matches [cli].
  TerminalSession _shellForLaunch({
    required ChatTab tab,
    required String shellKey,
    required CliTool cli,
    required AppSession session,
  }) {
    final workTarget = _launchWorkTarget(session);
    final needsRemoteLaunch = workTarget.kind == RuntimeKind.ssh;
    _discardIdleShellIfMismatched(
      tab: tab,
      shellKey: shellKey,
      cli: cli,
      needsRemoteLaunch: needsRemoteLaunch,
      sessionId: tab.info.id,
    );
    return tab.memberShells.putIfAbsent(
      shellKey,
      () => _h.shellFactory.newSession(workTarget: workTarget),
    );
  }

  /// Drop an idle shell when transport or CLI executable no longer matches.
  ///
  /// Connect launches [TerminalSession.executable]; keeping a stale shell after
  /// a profile change would spawn the wrong CLI despite a locked binding.
  void _discardIdleShellIfMismatched({
    required ChatTab tab,
    required String shellKey,
    required CliTool cli,
    required bool needsRemoteLaunch,
    String? sessionId,
  }) {
    final existing = tab.memberShells[shellKey];
    if (existing == null) return;
    if (existing.isRunning || existing.isConnecting) return;
    final transportMismatch = needsRemoteLaunch != existing.usesRemoteTransport;
    if (!transportMismatch) return;
    existing.disconnect();
    tab.memberShells.remove(shellKey);
    if (sessionId != null) {
      _h.clearAgentStatusSeat(sessionId: sessionId, memberId: shellKey);
    }
  }

  Future<void> connectWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) => _pipeline.run(ConnectWorkspaceOperation(request, repo: repo));

  Future<void> reconnectSshProfile(String profileId) =>
      _sshReconnect.reconnect(profileId);

  void disconnectSession() {
    final tab = _activeTab;
    if (tab == null) return;
    final memberId = tab.selectedMemberId;
    tab.membersPendingConnect.remove(memberId);
    tab.memberShells[memberId]?.disconnect();
    unawaited(tab.closeMemberRemotePlane(memberId));
    _h.clearAgentStatusSeat(sessionId: tab.info.id, memberId: memberId);
    _h.clearLaunchError(tab.info.id);
    _h.updateTabRunning(tab.info.id);
  }

  /// Disconnects [memberId] on [sessionId]'s open tab (any tab, not only active).
  ///
  /// Mirrors [disconnectSession] cleanup for one member shell without closing
  /// the session workbench tab. Used by Resource Manager kill.
  void disconnectMemberShell(String sessionId, String memberId) {
    final id = sessionId.trim();
    final mid = memberId.trim();
    if (id.isEmpty || mid.isEmpty) return;
    final tab = _tabStore.openTabBySessionId(id);
    if (tab == null) return;
    tab.membersPendingConnect.remove(mid);
    tab.memberShells[mid]?.disconnect();
    unawaited(tab.closeMemberRemotePlane(mid));
    _h.clearAgentStatusSeat(sessionId: tab.info.id, memberId: mid);
    _h.clearLaunchError(tab.info.id);
    _h.updateTabRunning(tab.info.id);
  }

  Future<void> restartWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) => _pipeline.run(RestartWorkspaceOperation(request, repo: repo));

  @override
  void Function(String line)? autoRenameOnFirstPrompt(String sessionId) =>
      _promptMetadata.autoRenameOnFirstPrompt(sessionId);

  @override
  void Function(String line)? autoTouchOnEveryPrompt(String sessionId) =>
      _promptMetadata.autoTouchOnEveryPrompt(sessionId);

  Future<void> applyFirstPromptTitle(String sessionId, String firstPrompt) =>
      _promptMetadata.applyFirstPromptTitle(sessionId, firstPrompt);

}
