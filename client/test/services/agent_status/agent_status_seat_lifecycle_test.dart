import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/cli_tool.dart';
import 'package:teampilot/services/agent_status/agent_status_seat_lookup.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint_resolver.dart';
import 'package:teampilot/services/agent_status/remote/remote_status_binding.dart';

void main() {
  group('RemoteStatusBinding.agentStatusUrl', () {
    test('ends with /agent-status on the tunnel port', () {
      const binding = RemoteStatusBinding(
        token: 'tok',
        tunnelPort: 47214,
      );
      expect(binding.agentStatusUrl, 'http://127.0.0.1:47214/agent-status');
      expect(binding.agentStatusUrl, endsWith('/agent-status'));
    });
  });

  group('AgentStatusSeatLookup', () {
    test('register OpenCode seat → resolveCli returns opencode', () {
      final lookup = AgentStatusSeatLookup();
      lookup.registerSeat(
        sessionId: 'sess-1',
        memberId: 'm1',
        cli: CliTool.opencode,
        skipPermissions: false,
      );
      expect(lookup.resolveCli('sess-1', 'm1'), CliTool.opencode);
      expect(lookup.resolveSkipPermissions('sess-1', 'm1'), isFalse);

      lookup.registerSeat(
        sessionId: 'sess-1',
        memberId: 'm2',
        cli: CliTool.claude,
        skipPermissions: true,
      );
      expect(lookup.resolveSkipPermissions('sess-1', 'm2'), isTrue);
    });
  });

  group('needsAgentStatusOnlyHttpTunnel / resolveMemberAgentStatusEndpoint', () {
    test('SSH without mixed binding needs status-only tunnel', () {
      expect(
        needsAgentStatusOnlyHttpTunnel(
          launchKind: RuntimeKind.ssh,
          mixedRemoteBinding: null,
        ),
        isTrue,
      );
    });

    test('SSH with mixed binding reuses idle tunnel (no status-only)', () {
      const binding = RemoteStatusBinding(
        token: 'tok',
        tunnelPort: 4000,
      );
      expect(
        needsAgentStatusOnlyHttpTunnel(
          launchKind: RuntimeKind.ssh,
          mixedRemoteBinding: binding,
        ),
        isFalse,
      );
    });

    test('local / WSL never need status-only tunnel', () {
      expect(
        needsAgentStatusOnlyHttpTunnel(
          launchKind: RuntimeKind.local,
          mixedRemoteBinding: null,
        ),
        isFalse,
      );
      expect(
        needsAgentStatusOnlyHttpTunnel(
          launchKind: RuntimeKind.wsl,
          mixedRemoteBinding: null,
        ),
        isFalse,
      );
    });
  });
}
