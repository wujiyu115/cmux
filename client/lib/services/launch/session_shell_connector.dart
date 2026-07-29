import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../cubits/chat/chat_tab_store.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/member_remote_provision_progress.dart';
import '../../models/runtime_target.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../repositories/session_repository.dart';
import '../../services/cli/installer_types.dart';
import '../../services/launch/connect_shell_result.dart';
import '../../services/session/shell_launch_spec.dart';
import '../../services/session/remote_ssh_launch_constraints.dart';
import '../../services/ssh/ssh_member_session.dart';
import '../../services/agent_status/member_agent_status_endpoint.dart';
import '../../services/agent_status/member_agent_status_endpoint_resolver.dart';
import '../../services/team_bus/remote/member_bus_mcp_config.dart';
import '../../services/team_bus/remote/remote_bus_mount.dart';
import '../../services/team_bus/remote/ssh_remote_bus_mount_factory.dart';
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
  SessionShellConnector(this._host, this._delegate, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final SessionLaunchHost _host;
  final SessionShellConnectorDelegate _delegate;
  final Uuid _uuid;

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
    const SessionMemberBinding? binding = null;

    if (!connectShellStillValid(tab: tab, shell: shell)) {
      abortConnectShellIfStale(
        tab: tab,
        shell: shell,
        reason: 'tab_or_shell_gone_after_member_binding',
      );
      return ConnectShellResult.aborted;
    }

    final launchTarget = _host.lifecycle.launchWorkTarget(
      _delegate.launchContextFor(activeSession),
      memberId: null,
    );
    final launchCli = activeSession.simpleIdentity.cli;
    final preflightMemberId = activeSession.sessionId;

    final sshMemberKey = preflightMemberId;
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
        'session=${tab.info.id} member=$preflightMemberId '
        'cli=${launchCli.value} target=${launchTarget.kind.name} '
        'targetId=${launchTarget.id}',
      );

      String? remoteCliPath;
      ShellLaunchSpec shellLaunch;
      final launchWarnings = <String>[];
      MemberAgentStatusEndpoint? agentStatus;

      if (workspace == null) {
        _host.failSessionConnect(
          tab.info.id,
          'Simple session requires workspace to connect.',
        );
        return ConnectShellResult.failed;
      }
      agentStatus = await _resolveAgentStatusForSeat(
        tab: tab,
        sessionId: activeSession.sessionId,
        memberId: activeSession.sessionId,
        launchTarget: launchTarget,
        launchCli: launchCli,
        memberSshSession: memberSshSession,
        mixedRemoteBinding: null,
        launchWarnings: launchWarnings,
      );
      final progressMemberId = activeSession.sessionId;
      final connectResult = await _prepareConnectWithProvisionUi(
        tab: tab,
        memberId: progressMemberId,
        launchTarget: launchTarget,
        prepare: (onProgress) => _host.sessionConnect.prepareSimpleConnect(
          session: activeSession,
          workspace: workspace,
          launchTarget: launchTarget,
          agentStatus: agentStatus,
          onProvisionProgress: onProgress,
        ),
      );
      shellLaunch = connectResult.shellLaunch;
      remoteCliPath = connectResult.remoteCliPath;
      launchWarnings.addAll(connectResult.warnings);

      final agentStatusSeatMemberId = activeSession.sessionId;

      if (!connectShellStillValid(tab: tab, shell: shell)) {
        abortConnectShellIfStale(
          tab: tab,
          shell: shell,
          reason: 'tab_or_shell_gone_after_prepare_connect',
          remoteMemberKey: remoteMemberKeyForRollback,
        );
        return ConnectShellResult.aborted;
      }

      if (launchTarget.kind == RuntimeKind.ssh) {
        final injectRootSandboxEnv = await _host.isWorkspaceRootSandboxEnvOptIn(
          activeSession.workspaceId,
        );
        shellLaunch = await applyRemoteSshLaunchConstraints(
          spec: shellLaunch,
          memberTarget: launchTarget,
          memberSession: memberSshSession,
          profile: _host.shellFactory.profileFor(launchTarget),
          injectRootSandboxEnv: injectRootSandboxEnv,
        );
      }

      if (!connectShellStillValid(tab: tab, shell: shell)) {
        abortConnectShellIfStale(
          tab: tab,
          shell: shell,
          reason: 'tab_or_shell_gone_after_ssh_constraints',
          remoteMemberKey: remoteMemberKeyForRollback,
        );
        return ConnectShellResult.aborted;
      }

      // After SSH constraints may flip skip-permissions (root dropFlag).
      _registerAgentStatusSeat(
        sessionId: activeSession.sessionId,
        memberId: agentStatusSeatMemberId,
        cli: launchCli,
        skipPermissions:
            shellLaunch.launchContext.member.dangerouslySkipPermissions,
        agentStatus: agentStatus,
      );
      if (launchCli == CliTool.cursor) {
        final attention = _host.agentAttentionCubit;
        if (attention != null) {
          final sessionId = activeSession.sessionId;
          final memberId = agentStatusSeatMemberId;
          shell.bindCursorTitleAttention(
            sessionId: sessionId,
            memberId: memberId,
            attention: attention,
            skipPermissions: () =>
                _host.agentStatusSeatLookup?.resolveSkipPermissions(
                  sessionId,
                  memberId,
                ) ??
                false,
          );
        }
      }

      final plan = shellLaunch.plan;
      appLogger.d(
        '[session-launch] launch plan ready '
        'session=${tab.info.id} member=$memberLabel '
        'resume=${plan.resume} create=${plan.createSessionId ?? ''} '
        'resumeId=${plan.resumeSessionId ?? ''} warnings=${plan.warnings.length}',
      );
      _host.emitLaunchWarnings([...launchWarnings, ...plan.warnings]);
      await _persistNativeSessionId(repo, tab, activeSession, binding, plan);

      if (!connectShellStillValid(tab: tab, shell: shell)) {
        abortConnectShellIfStale(
          tab: tab,
          shell: shell,
          reason: 'tab_or_shell_gone_after_persist_native_id',
          remoteMemberKey: remoteMemberKeyForRollback,
        );
        return ConnectShellResult.aborted;
      }

      final memberWork = activeSession.workDirsForMember(
        null,
        folders: _delegate.launchContextFor(activeSession).folderCatalog,
      );
      appLogger.d(
        '[session-launch] shell.connect '
        'session=${tab.info.id} member=$memberLabel '
        'cwd=${memberWork.workingDirectory} addDirs=${memberWork.addDirs.length}',
      );
      // Background members never hit workbench theme sync before spawn; apply
      // here so COLORFGBG matches the embedded light/dark (Claude theme: auto).
      final launchTheme = _host.resolveTerminalThemeForLaunch();
      if (launchTheme != null) {
        applyShellTerminalThemeForLaunch(shell, launchTheme);
      }
      shell.connect(
        workingDirectory: memberWork.workingDirectory,
        additionalDirectories: memberWork.addDirs,
        executableOverride: remoteCliPath,
        fixedSessionId: plan.createSessionId,
        resumeSessionId: plan.resumeSessionId,
        shellLaunch: shellLaunch,
        extraEnvironment: plan.env.isEmpty ? null : plan.env,
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
            memberId: agentStatusSeatMemberId,
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

  Future<void> _persistNativeSessionId(
    SessionRepository? repo,
    ChatTab tab,
    AppSession session,
    SessionMemberBinding? binding,
    LaunchPlan plan,
  ) async {
    final id = plan.nativeSessionIdToPersist?.trim() ?? '';
    final tool = plan.toolValue?.trim() ?? '';
    final r = repo ?? _host.sessionRepository;
    if (r == null ||
        id.isEmpty ||
        tool.isEmpty ||
        session.sessionId.startsWith('local-')) {
      return;
    }

    AppSession applyNative(AppSession s) {
      if (binding != null) {
        return s.copyWith(
          members: [
            for (final m in s.members)
              if (m.rosterMemberId == binding.rosterMemberId)
                m.withNativeSessionId(tool, id)
              else
                m,
          ],
        );
      }
      return s.withNativeSessionId(tool, id);
    }

    final current = tab.persistedSession ?? session;
    if (identical(applyNative(current), current)) return;

    try {
      await r.recordNativeSessionId(
        session.sessionId,
        tool: tool,
        nativeId: id,
        rosterMemberId: binding?.rosterMemberId,
      );
    } on Object catch (e, st) {
      appLogger.w(
        '[session] persist native session id failed: $e',
        error: e,
        stackTrace: st,
      );
      return;
    }
    if (_host.isClosed) return;

    tab.persistedSession = applyNative(current);
    final state = _host.state;
    final sessions = state.sessions
        .map((s) => s.sessionId == session.sessionId ? applyNative(s) : s)
        .toList();
    _host.emitSnapshot(
      _host.dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
    );
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

  Future<
    ({ShellLaunchSpec shellLaunch, List<String> warnings, String remoteCliPath})
  >
  _prepareConnectWithProvisionUi({
    required ChatTab tab,
    required String memberId,
    required RuntimeTarget launchTarget,
    required Future<
      ({
        ShellLaunchSpec shellLaunch,
        List<String> warnings,
        String remoteCliPath,
      })
    >
    Function(void Function(CliInstallProgress progress)? onProgress)
    prepare,
  }) async {
    final hostLabel = launchTarget.kind == RuntimeKind.ssh
        ? (_host.shellFactory.profileFor(launchTarget)?.host.trim() ??
              launchTarget.id)
        : '';
    MemberRemoteProvisionProgress? latest;
    void onProgress(CliInstallProgress progress) {
      latest = MemberRemoteProvisionProgress(
        memberId: memberId,
        phase: progress.phase,
        detail: progress.detail,
        hostLabel: hostLabel,
      );
      _host.setMemberRemoteProvisionProgress(tab.info.id, memberId, latest);
    }

    if (launchTarget.kind == RuntimeKind.ssh) {
      onProgress(const CliInstallProgress(phase: CliInstallPhase.checkingNpm));
    }

    try {
      final result = await prepare(
        launchTarget.kind == RuntimeKind.ssh ? onProgress : null,
      );
      _host.setMemberRemoteProvisionProgress(tab.info.id, memberId, null);
      return result;
    } on Object catch (e) {
      _host.setMemberRemoteProvisionProgress(
        tab.info.id,
        memberId,
        (latest ??
                MemberRemoteProvisionProgress(
                  memberId: memberId,
                  phase: CliInstallPhase.checkingNpm,
                  hostLabel: hostLabel,
                ))
            .copyWith(error: '$e'),
      );
      rethrow;
    }
  }

  /// Builds [MemberAgentStatusEndpoint] for a seat. Soft-fails status-only SSH
  /// tunnels (launch continues without attention).
  Future<MemberAgentStatusEndpoint?> _resolveAgentStatusForSeat({
    required ChatTab tab,
    required String sessionId,
    required String memberId,
    required RuntimeTarget launchTarget,
    required CliTool launchCli,
    required SshMemberSession? memberSshSession,
    required RemoteBusBinding? mixedRemoteBinding,
    required List<String> launchWarnings,
  }) async {
    final gateway = _host.teammateBusMcpGateway;
    // Local seats stamp the gateway /agent-status URL; start listeners even
    // when TeamBus was never installed (native / simple connect paths).
    await gateway.ensureStarted();
    if (!needsAgentStatusOnlyHttpTunnel(
      launchKind: launchTarget.kind,
      mixedRemoteBinding: mixedRemoteBinding,
    )) {
      return resolveMemberAgentStatusEndpoint(
        gateway: gateway,
        sessionId: sessionId,
        remoteBinding: mixedRemoteBinding,
      );
    }

    if (memberSshSession == null) {
      appLogger.w(
        '[agent-status] status-only SSH tunnel skipped '
        'session=$sessionId member=$memberId reason=no_ssh_session',
      );
      launchWarnings.add('agent_status_tunnel_unavailable');
      return null;
    }

    try {
      final token = gateway.registerAgentStatusSession(sessionId: sessionId);
      final workCtx = await _host.lifecycle.resolveWorkContextForTargetId(
        launchTarget.id,
      );
      final arch = archFromUname(await memberSshSession.run('uname -m'));
      final mount = buildStatusOnlyRemoteBusMount(
        memberSession: memberSshSession,
        gateway: gateway,
        storageFs: workCtx.fs,
        arch: arch,
        token: token,
      );
      tab.memberRemoteBusMounts[memberId] = mount;
      final binding = await mount.bindHttpMember(memberId);
      appLogger.d(
        '[agent-status] status-only SSH tunnel ready '
        'session=$sessionId member=$memberId cli=${launchCli.value}',
      );
      return MemberAgentStatusEndpoint.remote(binding);
    } on Object catch (e, st) {
      await tab.closeMemberRemoteBusMount(memberId);
      appLogger.w(
        '[agent-status] status-only SSH tunnel failed '
        'session=$sessionId member=$memberId: $e',
        error: e,
        stackTrace: st,
      );
      launchWarnings.add('agent_status_tunnel_failed');
      return null;
    }
  }

  void _registerAgentStatusSeat({
    required String sessionId,
    required String memberId,
    required CliTool cli,
    required bool skipPermissions,
    required MemberAgentStatusEndpoint? agentStatus,
  }) {
    final lookup = _host.agentStatusSeatLookup;
    if (lookup == null) return;

    final token = agentStatus?.token;
    _host.teammateBusMcpGateway.registerAgentStatusSession(
      sessionId: sessionId,
      token: token,
    );
    lookup.registerSeat(
      sessionId: sessionId,
      memberId: memberId,
      cli: cli,
      skipPermissions: skipPermissions,
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
