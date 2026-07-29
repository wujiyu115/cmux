import '../../models/runtime_target.dart';
import 'agent_status_gateway.dart';
import 'remote/remote_status_binding.dart';
import 'member_agent_status_endpoint.dart';

/// Whether this SSH seat needs a status-only HTTP reverse tunnel.
///
/// Mixed seats already open an idle/MCP tunnel ([remoteBinding] non-null).
/// Local / WSL seats stamp the app-host gateway URL — no reverse tunnel.
bool needsAgentStatusOnlyHttpTunnel({
  required RuntimeKind launchKind,
  required RemoteStatusBinding? mixedRemoteBinding,
}) =>
    launchKind == RuntimeKind.ssh && mixedRemoteBinding == null;

/// Pick the stamped agent-status endpoint once any SSH tunnel (or null) is known.
///
/// [remoteBinding] covers mixed idle tunnels and status-only [bindHttpMember]
/// results. Never pass an app-host local URL for a remote agent process.
MemberAgentStatusEndpoint resolveMemberAgentStatusEndpoint({
  required AgentStatusGateway gateway,
  required String sessionId,
  RemoteStatusBinding? remoteBinding,
}) {
  if (remoteBinding != null) {
    return MemberAgentStatusEndpoint.remote(remoteBinding);
  }
  return MemberAgentStatusEndpoint.local(gateway, sessionId: sessionId);
}
