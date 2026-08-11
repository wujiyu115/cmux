import 'dart:io';

import '../../cubits/agent_attention_cubit.dart';
import '../../models/cli_tool.dart';
import '../../models/runtime_target.dart';
import '../../models/workspace_shell_launch_plan.dart';
import '../../models/ssh_profile.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_terminal_session_spec.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../agent_status/agent_status_gateway.dart';
import '../agent_status/agent_status_launch_env.dart';
import '../agent_status/agent_status_seat_lookup.dart';
import '../session/launch_command_builder.dart';
import '../session/remote_flashskyai_command_builder.dart';
import '../ssh/ssh_member_session.dart';
import '../workspace_dnd/runtime_target.dart' as dnd;
import 'ssh_pty_transport.dart';
import 'terminal_session.dart';
import 'terminal_transport_factory.dart';
import '../host/host_interactive_shell.dart';
import '../host/host_interactive_shell_kind.dart';

/// Materializes workspace-terminal [TerminalSession]s and opens their transports.
class WorkspaceShellConnector {
  WorkspaceShellConnector({
    required TerminalTransportFactory transportFactory,
    required SshProfileRepository sshProfileRepository,
    bool Function()? sshUseLoginShell,
    AgentStatusGateway? agentStatusGateway,
    AgentStatusSeatLookup? agentStatusSeatLookup,
    AgentAttentionCubit? agentAttentionCubit,
    void Function(String distro)? onWslDistroLaunch,
  }) : _transportFactory = transportFactory,
       _sshProfileRepository = sshProfileRepository,
       _sshUseLoginShell = sshUseLoginShell ?? (() => true),
       _agentStatusGateway = agentStatusGateway,
       _agentStatusSeatLookup = agentStatusSeatLookup,
       _agentAttentionCubit = agentAttentionCubit,
       _onWslDistroLaunch = onWslDistroLaunch;

  final TerminalTransportFactory _transportFactory;
  final SshProfileRepository _sshProfileRepository;
  final bool Function() _sshUseLoginShell;

  /// Optional so tests and harnesses can build a connector without the
  /// agent-status stack; absent means panes launch exactly as before.
  final AgentStatusGateway? _agentStatusGateway;
  final AgentStatusSeatLookup? _agentStatusSeatLookup;
  final AgentAttentionCubit? _agentAttentionCubit;

  /// Notified with the distro name whenever a pane launches into WSL, so the
  /// hook can be installed into that distro on first use. Fire-and-forget on
  /// the callee's side — this is a launch path.
  final void Function(String distro)? _onWslDistroLaunch;

  /// Seat-id prefix keeping workspace panes out of the session-tab id space
  /// (mirrors `paneCatalogId` in `services/pairing/session_catalog.dart`).
  static const seatIdPrefix = 'ws:';

  static String seatIdFor(String paneId) => '$seatIdPrefix${paneId.trim()}';

  /// Inverse of [seatIdFor]; null when [seatId] is not a workspace pane seat.
  /// Lets notification wiring map a seat back to its pane without hardcoding
  /// the prefix.
  static String? paneIdOfSeat(String seatId) =>
      seatId.startsWith(seatIdPrefix)
      ? seatId.substring(seatIdPrefix.length)
      : null;

  static final _remoteShell = HostInteractiveShell.remotePosixExecutable;

  RuntimeTarget runtimeTargetFor(WorkspaceTerminalSessionSpec spec) =>
      switch (spec) {
        WorkspaceTerminalLocalSpec() => RuntimeTarget.local(),
        WorkspaceTerminalWorkspaceTargetSpec(:final targetId) =>
          _runtimeTargetFromId(targetId),
        WorkspaceTerminalSshProfileSpec(:final profileId) => RuntimeTarget.ssh(
          profileId,
          label: '',
        ),
      };

  TerminalSession createSession(WorkspaceTerminalSessionSpec spec) {
    final target = runtimeTargetFor(spec);
    if (target.kind == RuntimeKind.ssh) {
      return _createSshSession();
    }
    return TerminalSession(
      executable: _posixShellSpec(spec).executable,
      validateLaunch: false,
      parseExecutable: false,
      runtimeTarget: _dndTargetFor(target),
    );
  }

  /// [paneId] is the owning `WorkspaceTerminalEntry.id`. When supplied (and the
  /// gateway is up) the pane is registered as an agent-status seat and the
  /// resulting plan carries the identity env the shared Claude hook reads. SSH
  /// panes are skipped — they need a reverse tunnel and a remote script, same
  /// deferral as `SessionShellConnector`.
  WorkspaceShellLaunchPlan resolveLaunchPlan({
    required WorkspaceTerminalSessionSpec spec,
    required String workingDirectory,
    String paneId = '',
  }) {
    final target = runtimeTargetFor(spec);
    if (target.kind == RuntimeKind.wsl) {
      // First launch into this distro installs the hook there (the distro reads
      // its own ~/.claude/settings.json). Deliberately not awaited.
      _onWslDistroLaunch?.call(target.wslDistro ?? '');
    }
    return switch (target.kind) {
      RuntimeKind.ssh => _sshLaunchPlan(workingDirectory: workingDirectory),
      RuntimeKind.wsl => _wslLaunchPlan(
        distro: target.wslDistro ?? '',
        workingDirectory: workingDirectory,
        runtimeTarget: target,
        environment: _registerAgentStatusSeat(paneId: paneId, usesWsl: true),
      ),
      RuntimeKind.local => _localLaunchPlan(
        spec: spec,
        workingDirectory: workingDirectory,
        runtimeTarget: target,
        environment: _registerAgentStatusSeat(paneId: paneId, usesWsl: false),
      ),
    };
  }

  /// Registers the pane as an agent-status seat and returns the identity env.
  ///
  /// Returns empty (leaving the launch env untouched) when there is no gateway,
  /// no pane id, or the loopback listener never bound — reading
  /// [AgentStatusGateway.agentStatusEndpoint] before that would dereference a
  /// null server.
  Map<String, String> _registerAgentStatusSeat({
    required String paneId,
    required bool usesWsl,
  }) {
    final gateway = _agentStatusGateway;
    if (gateway == null || paneId.trim().isEmpty || !gateway.isStarted) {
      return const {};
    }
    final seatId = seatIdFor(paneId);
    gateway.registerAgentStatusSession(sessionId: seatId);
    // A workspace pane runs a plain shell, so the CLI is unknown until a hook
    // fires — assume `claude`, the only wired family.
    _agentStatusSeatLookup?.registerSeat(
      sessionId: seatId,
      memberId: seatId,
      cli: CliTool.claude,
      skipPermissions: false,
    );
    return AgentStatusLaunchEnv.build(
      endpoint: gateway.agentStatusEndpoint.toString(),
      seatId: seatId,
      usesWsl: usesWsl,
    );
  }

  /// Drops the pane's agent-status seat. Safe to call for panes that never
  /// registered one.
  void releaseAgentStatusSeat(String paneId) {
    if (paneId.trim().isEmpty) return;
    final seatId = seatIdFor(paneId);
    // Same three steps as the session path's `clearAgentStatusSeat`: drop the
    // attention row too, or a closed pane keeps a ghost seat until the 30-minute
    // stale prune. All three are idempotent.
    _agentAttentionCubit?.clearSeat(sessionId: seatId, memberId: seatId);
    _agentStatusSeatLookup?.unregisterSeat(
      sessionId: seatId,
      memberId: seatId,
    );
    _agentStatusGateway?.unregisterAgentStatusSession(seatId);
  }

  Future<SshMemberSession?> openSshSession(
    WorkspaceTerminalSessionSpec spec,
  ) async {
    final profile = await _profileFor(spec);
    if (profile == null) return null;
    return SshMemberSession.open(_transportFactory.sshClientFactory, profile);
  }

  Future<void> disposeRemotePlane(TerminalSession session) async {
    session.sshMemberSession?.close();
    session.sshMemberSession = null;
  }

  Future<String> labelForSpec(WorkspaceTerminalSessionSpec spec) async {
    switch (spec) {
      case WorkspaceTerminalLocalSpec():
        return 'Local';
      case WorkspaceTerminalWorkspaceTargetSpec(:final targetId):
        final profileId = sshProfileIdOfId(targetId);
        if (profileId != null) {
          final profile = await _sshProfileRepository.findById(profileId);
          if (profile != null) return profile.hostIdentifier;
        }
        final distro = wslDistroOfId(targetId);
        if (distro != null && distro.isNotEmpty) return 'WSL · $distro';
        if (targetId == WorkspaceFolder.localTargetId) return 'Local';
        return targetId;
      case WorkspaceTerminalSshProfileSpec(:final profileId):
        final profile = await _sshProfileRepository.findById(profileId);
        if (profile == null) return 'SSH';
        return profile.hostIdentifier;
    }
  }

  Future<SshProfile?> _profileFor(WorkspaceTerminalSessionSpec spec) async {
    final id = switch (spec) {
      WorkspaceTerminalSshProfileSpec(:final profileId) => profileId,
      WorkspaceTerminalWorkspaceTargetSpec(:final targetId) =>
        sshProfileIdOfId(targetId) ?? '',
      _ => '',
    };
    if (id.isEmpty) return null;
    return _sshProfileRepository.findById(id);
  }

  TerminalSession _createSshSession() {
    late final TerminalSession shell;
    shell = TerminalSession(
      executable: _remoteShell,
      validateLaunch: false,
      usesRemoteTransport: true,
      parseExecutable: false,
      runtimeTarget: const dnd.RuntimeTarget.ssh(),
      transportStarter:
          (
            String executable, {
            required List<String> arguments,
            required String workingDirectory,
            required int columns,
            required int rows,
            Map<String, String>? environment,
          }) async {
            final memberSession = shell.sshMemberSession;
            if (memberSession == null) {
              throw StateError(
                'SSH workspace shell requires an open member session',
              );
            }
            final command = const RemoteFlashskyaiCommandBuilder().buildCommand(
              remoteExecutablePath: executable,
              arguments: arguments,
              workingDirectory: workingDirectory.isEmpty
                  ? null
                  : workingDirectory,
              environment: environment,
              useLoginShell: _sshUseLoginShell(),
            );
            return SshPtyTransport.start(
              memberSession: memberSession,
              command: SshPtyTransport.buildSessionCommand(command),
              columns: columns,
              rows: rows,
            );
          },
    );
    return shell;
  }

  HostInteractiveShellSpec _posixShellSpec(WorkspaceTerminalSessionSpec spec) =>
      switch (spec) {
        WorkspaceTerminalLocalSpec(:final shellPath) =>
          HostInteractiveShell.resolveSpec(shellPath),
        _ => HostInteractiveShell.defaultSpec(),
      };

  WorkspaceShellLaunchPlan _localLaunchPlan({
    required WorkspaceTerminalSessionSpec spec,
    required String workingDirectory,
    required RuntimeTarget runtimeTarget,
    Map<String, String> environment = const {},
  }) {
    final shell = _posixShellSpec(spec);
    final cwd = LaunchCommandBuilder.workingDirectoryForProcess(
      _nonEmptyCwd(workingDirectory),
      useWslPaths: false,
    );
    return WorkspaceShellLaunchPlan(
      executable: shell.executable,
      arguments: shell.launchArguments,
      workingDirectory: cwd,
      useWslPaths: false,
      inheritHostEnvironment: true,
      runtimeTarget: runtimeTarget,
      usesRemoteTransport: false,
      environment: environment,
    );
  }

  WorkspaceShellLaunchPlan _wslLaunchPlan({
    required String distro,
    required String workingDirectory,
    required RuntimeTarget runtimeTarget,
    Map<String, String> environment = const {},
  }) {
    final cwd = workingDirectory.trim();
    final wslArgs = <String>[];
    final trimmedDistro = distro.trim();
    if (trimmedDistro.isNotEmpty) wslArgs.addAll(['-d', trimmedDistro]);
    if (cwd.isNotEmpty) wslArgs.addAll(['--cd', cwd]);
    // No shell executable appended: `wsl.exe [-d …] [--cd …]` starts the
    // distro's *default* login shell (zsh, fish, …) as configured by chsh —
    // rather than forcing bash, which sources the wrong rc files and ignores
    // the user's chosen shell.

    return WorkspaceShellLaunchPlan(
      executable: 'wsl.exe',
      arguments: wslArgs,
      workingDirectory: LaunchCommandBuilder.workingDirectoryForProcess(
        cwd,
        useWslPaths: true,
      ),
      useWslPaths: true,
      inheritHostEnvironment: true,
      runtimeTarget: runtimeTarget,
      usesRemoteTransport: false,
      environment: environment,
    );
  }

  WorkspaceShellLaunchPlan _sshLaunchPlan({required String workingDirectory}) {
    return WorkspaceShellLaunchPlan(
      executable: _remoteShell,
      arguments: HostInteractiveShell.launchArgumentsFor(
        HostInteractiveShellKind.bash,
      ),
      workingDirectory: workingDirectory.trim(),
      useWslPaths: false,
      inheritHostEnvironment: false,
      runtimeTarget: RuntimeTarget.ssh('', label: ''),
      usesRemoteTransport: true,
    );
  }

  RuntimeTarget _runtimeTargetFromId(String id) => switch (runtimeKindOfId(
    id,
  )) {
    RuntimeKind.ssh => RuntimeTarget.ssh(sshProfileIdOfId(id) ?? '', label: ''),
    RuntimeKind.wsl => RuntimeTarget.wsl(wslDistroOfId(id) ?? ''),
    RuntimeKind.local => RuntimeTarget.local(),
  };

  dnd.RuntimeTarget _dndTargetFor(RuntimeTarget target) =>
      switch (target.kind) {
        RuntimeKind.ssh => const dnd.RuntimeTarget.ssh(),
        RuntimeKind.wsl => dnd.RuntimeTarget.wsl(),
        RuntimeKind.local =>
          Platform.isWindows
              ? dnd.RuntimeTarget.localWindows()
              : dnd.RuntimeTarget.localPosix(),
      };

  String _nonEmptyCwd(String cwd) =>
      cwd.trim().isNotEmpty ? cwd.trim() : Directory.current.path;
}
