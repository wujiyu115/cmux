import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_status_launch_env.dart';
import 'package:teampilot/services/agent_status/claude_hook_installer.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';

void main() {
  const endpoint = 'http://127.0.0.1:54321/agent-status';
  const seatId = 'ws:pane-1';

  group('AgentStatusLaunchEnv.build', () {
    test('stamps all three keys with session == member', () {
      final env = AgentStatusLaunchEnv.build(
        endpoint: endpoint,
        seatId: seatId,
        usesWsl: false,
        hostEnvironment: const {},
      );
      expect(env[agentStatusUrlEnvKey], endpoint);
      expect(env[agentStatusSessionEnvKey], seatId);
      expect(env[agentStatusMemberEnvKey], seatId);
      // The gateway keys seats by sessionId+NUL+memberId, so these must match.
      expect(env[agentStatusSessionEnvKey], env[agentStatusMemberEnvKey]);
    });

    test('omits WSLENV when not launching into WSL', () {
      final env = AgentStatusLaunchEnv.build(
        endpoint: endpoint,
        seatId: seatId,
        usesWsl: false,
        hostEnvironment: const {},
      );
      expect(env.containsKey('WSLENV'), isFalse);
    });

    test('declares WSLENV for WSL so wsl.exe forwards the keys', () {
      final env = AgentStatusLaunchEnv.build(
        endpoint: endpoint,
        seatId: seatId,
        usesWsl: true,
        hostEnvironment: const {},
      );
      final declared = (env['WSLENV'] ?? '').split(':');
      expect(declared, containsAll(AgentStatusLaunchEnv.forwardedKeys));
    });

    test('WSL env values are not path-rewritten by the URL/list shape', () {
      // Regression lock: LaunchCommandBuilder.normalizePathForCli rewrites
      // `C:\x` style values when useWslPaths is set. Its drive regex requires
      // exactly ONE letter before the colon, so neither the endpoint URL nor the
      // WSLENV list matches. Anyone shortening a seat-id prefix to a single
      // letter would break this.
      final env = AgentStatusLaunchEnv.build(
        endpoint: endpoint,
        seatId: seatId,
        usesWsl: true,
        hostEnvironment: const {},
      );
      expect(env[agentStatusUrlEnvKey], endpoint);
      expect(env[agentStatusSessionEnvKey]!.split(':').first.length,
          greaterThan(1));
    });
  });

  group('AgentStatusLaunchEnv.buildWslEnvDeclaration', () {
    test('appends to the host declaration instead of replacing it', () {
      final value = AgentStatusLaunchEnv.buildWslEnvDeclaration(
        hostEnvironment: const {'WSLENV': 'FOO/p:BAR'},
      );
      final entries = value.split(':');
      expect(entries, containsAll(<String>['FOO/p', 'BAR']));
      expect(entries, containsAll(AgentStatusLaunchEnv.forwardedKeys));
    });

    test('keeps host flags and does not duplicate an already-declared key', () {
      final value = AgentStatusLaunchEnv.buildWslEnvDeclaration(
        hostEnvironment: const {
          'WSLENV': '$agentStatusSessionEnvKey/p:KEEP',
        },
      );
      final entries = value.split(':');
      // Host's flagged entry survives verbatim...
      expect(entries, contains('$agentStatusSessionEnvKey/p'));
      // ...and the bare name is not added a second time.
      expect(entries.where((e) => e == agentStatusSessionEnvKey), isEmpty);
      expect(
        entries.where((e) => e.split('/').first == agentStatusSessionEnvKey),
        hasLength(1),
      );
    });

    test('tolerates empty and blank host entries', () {
      final value = AgentStatusLaunchEnv.buildWslEnvDeclaration(
        hostEnvironment: const {'WSLENV': '::  :'},
      );
      expect(value.split(':'), AgentStatusLaunchEnv.forwardedKeys);
    });

    test('handles a missing host WSLENV', () {
      final value = AgentStatusLaunchEnv.buildWslEnvDeclaration(
        hostEnvironment: const {},
      );
      expect(value.split(':'), AgentStatusLaunchEnv.forwardedKeys);
    });
  });
}
