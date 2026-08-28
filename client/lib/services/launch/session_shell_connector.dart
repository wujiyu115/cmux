import 'dart:async';

import '../../cubits/chat/chat_tab_store.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/cli_tool.dart';
import '../../models/runtime_target.dart';
import '../agent_status/agent_status_launch_env.dart';
import '../../services/host/host_interactive_shell.dart';
import '../../services/host/host_interactive_shell_kind.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../repositories/session_repository.dart';
import '../../services/launch/connect_shell_result.dart';
import '../../services/ssh/ssh_member_session.dart';
import '../../services/terminal/terminal_session.dart';
import '../../services/terminal/terminal_theme_for_launch.dart';
import '../../utils/logging/logger.dart';

/// Hooks [SessionShellConnector] delegates back to [SessionLaunchService].
abstract interface class SessionShellConnectorDelegate {
  WorkspaceLaunchContext launchContextFor(AppSession session);

  void Function(String line)? autoRenameOnFirstPrompt(String sessionId);

  void Function(String line)? autoTouchOnEveryPrompt(String sessionId);
}

/// Attaches a member shell after launch prep, lifecycle gating, and SSH/bus setup.
class SessionShellConnector {
  SessionShellConnector(this._host, this._delegate);

  final SessionLaunchHost _host;
  final SessionShellConnectorDelegate _delegate;

  ChatTabStore get _tabStore => _host.tabStore;

  bool connectShellStillValid({
    required ChatTab tab,
    required TerminalSession shell,
  }) {
    if (_host.isClosed) return false;
    if (_tabStore.activeIndexOfSession(tab.info.id) == -1) return false;
    if (shell.isDisposed) return false;
    return true;
  }

  void abortConnectShellIfStale({
    required ChatTab tab,
    required TerminalSession shell,
    required String reason,
    String? remoteMemberKey,
  }) {
    if (_host.isClosed) return;
    if (connectShellStillValid(tab: tab, shell: shell)) return;
    appLogger.d(
      '[session-launch] connectShell aborted session=${tab.info.id} '
      'reason=$reason',
    );
    if (remoteMemberKey != null) {
      unawaited(tab.closeMemberRemotePlane(remoteMemberKey));
    }
    if (_host.state.sessionConnectingId == tab.info.id) {
      _host.finishSessionConnect(tab.info.id);
    }
  }

  Future<ConnectShellResult> connect({
    required ChatTab tab,
    required AppSession session,
    required TerminalSession shell,
    SessionRepository? repo,
    required bool launched,
    Workspace? workspace,
  }) async {
    final connectSession = tab.persistedSession ?? session;
    final memberLabel = connectSession.sessionId;
    appLogger.d(
      '[session-launch] connectShell start '
      'session=${tab.info.id} member=$memberLabel personal=true '
      'launched=$launched',
    );

    final activeSession = connectSession;

    if (!connectShellStillValid(tab: tab, shell: shell)) {
      abortConnectShellIfStale(
        tab: tab,
        shell: shell,
        reason: 'tab_or_shell_gone_before_launch',
      );
      return ConnectShellResult.aborted;
    }

    final launchTarget = _host.lifecycle.launchWorkTarget(
      _delegate.launchContextFor(activeSession),
      memberId: null,
    );
    final sshMemberKey = activeSession.sessionId;
    String? remoteMemberKeyForRollback;
    try {
      final memberSshSession = await _beginRemoteMemberSshSession(
        tab: tab,
        memberKey: sshMemberKey,
        launchTarget: launchTarget,
      );
      if (memberSshSession != null) {
        remoteMemberKeyForRollback = sshMemberKey;
      }
      shell.sshMemberSession = memberSshSession;

      appLogger.d(
        '[session-launch] launch target resolved '
        'session=${tab.info.id} member=$sshMemberKey '
        'target=${launchTarget.kind.name} targetId=${launchTarget.id}',
      );

      if (workspace == null) {
        _host.failSessionConnect(
          tab.info.id,
          'Session requires workspace to connect.',
        );
        return ConnectShellResult.failed;
      }

      if (!connectShellStillValid(tab: tab, shell: shell)) {
        abortConnectShellIfStale(
          tab: tab,
          shell: shell,
          reason: 'tab_or_shell_gone_after_ssh_session',
          remoteMemberKey: remoteMemberKeyForRollback,
        );
        return ConnectShellResult.aborted;
      }

      final memberWork = activeSession.workDirsForMember(
        null,
        folders: _delegate.launchContextFor(activeSession).folderCatalog,
      );
      final shellArguments = launchTarget.kind == RuntimeKind.ssh
          ? HostInteractiveShell.launchArgumentsFor(
              HostInteractiveShellKind.bash,
            )
          : HostInteractiveShell.launchArgumentsFor(
              HostInteractiveShell.defaultSpec().kind,
            );
      appLogger.d(
        '[session-launch] shell.connect '
        'session=${tab.info.id} member=$memberLabel '
        'cwd=${memberWork.workingDirectory} args=${shellArguments.join(' ')}',
      );
      // Background members never hit workbench theme sync before spawn; apply
      // here so COLORFGBG matches the embedded light/dark (Claude theme: auto).
      final launchTheme = _host.resolveTerminalThemeForLaunch();
      if (launchTheme != null) {
        applyShellTerminalThemeForLaunch(shell, launchTheme);
      }
      // Revive the agent-status pipeline for local panes: register the gateway
      // session + seat and stamp the identity env the shared agent hook reads
      // at run time (see agent_hook_installer.dart). The pane runs a plain
      // shell, so the CLI is unknown until a hook fires — assume `claude`, the
      // family every wired CLI (claude / qoder / codex) normalizes through.
      // SSH panes need a remote tunnel + remote script and are deferred; skip
      // stamping there so the hook stays a no-op.
      final agentStatusEnv = <String, String>{};
      if (launchTarget.kind != RuntimeKind.ssh) {
        final seatId = activeSession.sessionId;
        _host.agentStatusGateway.registerAgentStatusSession(sessionId: seatId);
        _host.agentStatusSeatLookup?.registerSeat(
          sessionId: seatId,
          memberId: seatId,
          cli: CliTool.claude,
          skipPermissions: false,
        );
        // Only stamp the endpoint when the loopback gateway is actually up;
        // otherwise reading agentStatusEndpoint dereferences a null server
        // (tests, or agent-status disabled). The hook stays a no-op without it.
        if (_host.agentStatusGateway.isStarted) {
          // usesWsl: false even for a WSL target. A session pane's shell comes
          // from HostInteractiveShell.defaultExecutable(), which on Windows is
          // COMSPEC / cmd.exe / Git bash — never `wsl.exe` — so the CLI runs on
          // the host and already sees these vars. Should this path ever spawn
          // `wsl.exe` directly, it needs the WSLENV declaration too (see
          // AgentStatusLaunchEnv).
          agentStatusEnv.addAll(
            AgentStatusLaunchEnv.build(
              endpoint: _host.agentStatusGateway.agentStatusEndpoint.toString(),
              seatId: seatId,
              usesWsl: false,
            ),
          );
        }
      }
      shell.connect(
        workingDirectory: memberWork.workingDirectory,
        arguments: shellArguments,
        extraEnvironment: agentStatusEnv.isEmpty ? null : agentStatusEnv,
        onFirstUserLineSubmitted: _delegate.autoRenameOnFirstPrompt(
          activeSession.sessionId,
        ),
        onEveryUserLineSubmitted: _delegate.autoTouchOnEveryPrompt(
          activeSession.sessionId,
        ),
        onProcessFailed: (message) {
          if (remoteMemberKeyForRollback != null) {
            unawaited(tab.closeMemberRemotePlane(remoteMemberKeyForRollback));
          }
          _host.failSessionConnect(tab.info.id, message);
        },
        onProcessExited: () {
          _host.clearAgentStatusSeat(
            sessionId: activeSession.sessionId,
            memberId: activeSession.sessionId,
          );
          _host.agentStatusGateway.unregisterAgentStatusSession(
            activeSession.sessionId,
          );
          _host.updateTabRunning(tab.info.id);
        },
        onProcessStarted: () {
          final personalMemberId = tab.selectedMemberId.trim();
          if (personalMemberId.isNotEmpty) {
            _host.memberMaterializer.markMemberReady(
              tab.info.id,
              personalMemberId,
            );
          }
          _host.clearLaunchError(tab.info.id);
          _host.updateTabRunning(tab.info.id);
          _host.finishSessionConnect(tab.info.id);
          final r = repo ?? _host.sessionRepository;
          if (r != null && !activeSession.sessionId.startsWith('local-')) {
            unawaited(
              _persistSessionStarted(r, activeSession.sessionId).onError(
                (e, st) => appLogger.w(
                  '[session] persist after start failed: $e',
                  error: e,
                  stackTrace: st,
                ),
              ),
            );
          }
        },
      );
      remoteMemberKeyForRollback = null;
      return ConnectShellResult.attached;
    } on Object catch (e, st) {
      if (remoteMemberKeyForRollback != null) {
        await tab.closeMemberRemotePlane(remoteMemberKeyForRollback);
      }
      appLogger.e(
        '[session-launch] connectShell failed session=${tab.info.id} '
        'member=$memberLabel: $e',
        error: e,
        stackTrace: st,
      );
      _host.failSessionConnect(tab.info.id, 'Failed to connect session: $e');
      return ConnectShellResult.failed;
    }
  }

  Future<void> _persistSessionStarted(
    SessionRepository repo,
    String sessionId,
  ) async {
    await repo.markSessionLaunched(sessionId);
    if (_host.isClosed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = _host.state;
    final sessions = state.sessions.map((s) {
      if (s.sessionId != sessionId) return s;
      return s.copyWith(
        launchState: AppSessionLaunchState.started,
        updatedAt: now,
      );
    }).toList();
    // Keep the open tab's cached session in sync — history-review reconnect
    // reads tab.persistedSession for previouslyLaunched / resume decisions.
    final tab = _host.tabStore.openTabBySessionId(sessionId);
    final cached = tab?.persistedSession;
    if (tab != null && cached != null && cached.sessionId == sessionId) {
      tab.persistedSession = cached.copyWith(
        launchState: AppSessionLaunchState.started,
        updatedAt: now,
      );
    }
    _host.emitSnapshot(
      _host.dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
    );
  }

  Future<SshMemberSession?> _beginRemoteMemberSshSession({
    required ChatTab tab,
    required String memberKey,
    required RuntimeTarget launchTarget,
  }) async {
    if (launchTarget.kind != RuntimeKind.ssh) return null;
    final factory = _host.shellFactory.transportFactory?.sshClientFactory;
    final profile = _host.shellFactory.profileFor(launchTarget);
    if (factory == null || profile == null) return null;

    await tab.closeMemberRemotePlane(memberKey);

    final session = await SshMemberSession.open(factory, profile);
    tab.memberSshSessions[memberKey] = session;
    return session;
  }
}
