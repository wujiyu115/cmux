import '../../ssh/ssh_member_session.dart';
import '../mcp/teammate_bus_mcp_gateway.dart';
import 'remote_bus_mount.dart';

/// HTTP-only reverse tunnel carrying agent-status reports for one SSH seat.
///
/// Uses [token] from [TeammateBusMcpGateway.registerAgentStatusSession] so the
/// remote agent authenticates against the local gateway.
RemoteBusMount buildStatusOnlyRemoteBusMount({
  required SshMemberSession memberSession,
  required TeammateBusMcpGateway gateway,
  required String token,
}) {
  return RemoteBusMount(
    httpBusPort: gateway.httpPort,
    memberSession: memberSession,
    token: token,
  );
}
