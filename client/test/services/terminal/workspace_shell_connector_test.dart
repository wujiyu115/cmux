import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_tool.dart';
import 'package:teampilot/services/host/host_interactive_shell.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/agent_status/agent_status_gateway.dart';
import 'package:teampilot/services/agent_status/agent_status_launch_env.dart';
import 'package:teampilot/services/agent_status/agent_status_seat_lookup.dart';
import 'package:teampilot/services/agent_status/claude_hook_installer.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/terminal/workspace_shell_connector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WorkspaceShellConnector connector;

  setUp(() {
    connector = WorkspaceShellConnector(
      transportFactory: TerminalTransportFactory(
        sshProfileRepository: SshProfileRepository(),
        sshCredentialStore: InMemorySshCredentialStore(),
        sshKnownHostRepository: InMemorySshKnownHostRepository(),
      ),
      sshProfileRepository: SshProfileRepository(),
    );
  });

  group('WorkspaceShellConnector.resolveLaunchPlan', () {
    test('local spec uses resolved shell path and cwd', () {
      const requested = '/bin/bash';
      final plan = connector.resolveLaunchPlan(
        spec: WorkspaceTerminalLocalSpec(requested),
        workingDirectory: '/home/user/proj',
      );
      expect(File(plan.executable).existsSync(), isTrue);
      expect(plan.workingDirectory, '/home/user/proj');
      expect(plan.usesRemoteTransport, isFalse);
      expect(plan.runtimeTarget.kind.name, 'local');
    });

    test('wsl spec launches distro default login shell (no forced bash)', () {
      final plan = connector.resolveLaunchPlan(
        spec: const WorkspaceTerminalWorkspaceTargetSpec('wsl:Ubuntu'),
        workingDirectory: '/home/user/proj',
      );
      expect(plan.executable, 'wsl.exe');
      expect(plan.arguments, ['-d', 'Ubuntu', '--cd', '/home/user/proj']);
      // No shell binary appended — wsl.exe starts the chsh default shell.
      expect(plan.arguments, isNot(contains('bash')));
      expect(plan.arguments, isNot(contains('-l')));
      expect(plan.runtimeTarget.kind.name, 'wsl');
    });

    test('ssh profile spec uses remote transport', () {
      final plan = connector.resolveLaunchPlan(
        spec: const WorkspaceTerminalSshProfileSpec('profile-1'),
        workingDirectory: '/remote',
      );
      expect(plan.usesRemoteTransport, isTrue);
      expect(plan.executable, HostInteractiveShell.remotePosixExecutable);
      expect(plan.runtimeTarget.kind.name, 'ssh');
    });
  });

  group('WorkspaceShellConnector.runtimeTargetFor', () {
    test('maps workspace target id to runtime kind', () {
      final target = connector.runtimeTargetFor(
        const WorkspaceTerminalWorkspaceTargetSpec('wsl:Ubuntu'),
      );
      expect(target.kind.name, 'wsl');
      expect(target.wslDistro, 'Ubuntu');
    });
  });

  group('agent-status seat stamping', () {
    late AgentStatusGateway gateway;
    late AgentStatusSeatLookup seats;
    late List<String> wslLaunches;
    late WorkspaceShellConnector wired;

    WorkspaceShellConnector build(AgentStatusGateway g) =>
        WorkspaceShellConnector(
          transportFactory: TerminalTransportFactory(
            sshProfileRepository: SshProfileRepository(),
            sshCredentialStore: InMemorySshCredentialStore(),
            sshKnownHostRepository: InMemorySshKnownHostRepository(),
          ),
          sshProfileRepository: SshProfileRepository(),
          agentStatusGateway: g,
          agentStatusSeatLookup: seats,
          onWslDistroLaunch: wslLaunches.add,
        );

    setUp(() async {
      seats = AgentStatusSeatLookup();
      wslLaunches = <String>[];
      gateway = AgentStatusGateway();
      await gateway.ensureStarted();
      wired = build(gateway);
    });

    tearDown(() async {
      await gateway.dispose();
    });

    test('local pane stamps identity and registers a claude seat', () {
      final plan = wired.resolveLaunchPlan(
        spec: WorkspaceTerminalLocalSpec('/bin/bash'),
        workingDirectory: '/home/user/proj',
        paneId: 'pane-1',
      );
      final seatId = WorkspaceShellConnector.seatIdFor('pane-1');
      expect(plan.environment[agentStatusUrlEnvKey], contains('/agent-status'));
      expect(plan.environment[agentStatusSessionEnvKey], seatId);
      expect(plan.environment[agentStatusMemberEnvKey], seatId);
      expect(plan.environment.containsKey('WSLENV'), isFalse);
      expect(seats.resolveCli(seatId, seatId), CliTool.claude);
    });

    test('wsl pane also declares WSLENV and leaves argv untouched', () {
      final plan = wired.resolveLaunchPlan(
        spec: const WorkspaceTerminalWorkspaceTargetSpec('wsl:Ubuntu'),
        workingDirectory: '/home/user/proj',
        paneId: 'pane-2',
      );
      expect(plan.environment['WSLENV'], isNotNull);
      expect(
        plan.environment['WSLENV']!.split(':'),
        containsAll(AgentStatusLaunchEnv.forwardedKeys),
      );
      // The distro default login shell must still be what launches.
      expect(plan.arguments, ['-d', 'Ubuntu', '--cd', '/home/user/proj']);
    });

    test('wsl launch reports the distro for lazy hook install', () {
      wired.resolveLaunchPlan(
        spec: const WorkspaceTerminalWorkspaceTargetSpec('wsl:Ubuntu'),
        workingDirectory: '/home/user/proj',
        paneId: 'pane-2',
      );
      expect(wslLaunches, ['Ubuntu']);
    });

    test('ssh pane stamps nothing (deferred)', () {
      final plan = wired.resolveLaunchPlan(
        spec: const WorkspaceTerminalSshProfileSpec('profile-1'),
        workingDirectory: '/remote',
        paneId: 'pane-3',
      );
      expect(plan.environment, isEmpty);
      expect(wslLaunches, isEmpty);
    });

    test('missing paneId stamps nothing', () {
      final plan = wired.resolveLaunchPlan(
        spec: WorkspaceTerminalLocalSpec('/bin/bash'),
        workingDirectory: '/home/user/proj',
      );
      expect(plan.environment, isEmpty);
    });

    test('releaseAgentStatusSeat drops the seat and is idempotent', () {
      wired.resolveLaunchPlan(
        spec: WorkspaceTerminalLocalSpec('/bin/bash'),
        workingDirectory: '/home/user/proj',
        paneId: 'pane-1',
      );
      final seatId = WorkspaceShellConnector.seatIdFor('pane-1');
      expect(seats.resolveCli(seatId, seatId), isNotNull);
      wired.releaseAgentStatusSeat('pane-1');
      expect(seats.resolveCli(seatId, seatId), isNull);
      // Panes can be torn down twice (PTY exit + dispose).
      wired.releaseAgentStatusSeat('pane-1');
      expect(seats.resolveCli(seatId, seatId), isNull);
    });

    test('unstarted gateway stamps nothing instead of throwing', () {
      // agentStatusEndpoint dereferences a null server before ensureStarted.
      final unstarted = build(AgentStatusGateway());
      final plan = unstarted.resolveLaunchPlan(
        spec: WorkspaceTerminalLocalSpec('/bin/bash'),
        workingDirectory: '/home/user/proj',
        paneId: 'pane-9',
      );
      expect(plan.environment, isEmpty);
    });
  });

  group('WorkspaceShellConnector.seatIdFor / paneIdOfSeat', () {
    test('round-trips and rejects non-pane seat ids', () {
      final seatId = WorkspaceShellConnector.seatIdFor('pane-7');
      expect(WorkspaceShellConnector.paneIdOfSeat(seatId), 'pane-7');
      expect(WorkspaceShellConnector.paneIdOfSeat('session-uuid'), isNull);
    });
  });
}
