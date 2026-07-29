import 'agent_status_headers.dart';
import 'agent_status_gateway.dart';
import 'remote/remote_status_binding.dart';

/// Launch env key for seat status hooks (OpenCode plugin fallback, etc.).
const agentStatusUrlEnvKey = 'TEAMPILOT_AGENT_STATUS_URL';

/// Where a seat reports permission / status hooks (`POST /agent-status`).
///
/// Local seats dial the TeamBus gateway loopback. Remote (SSH) seats dial their
/// reverse-tunnel port and include [token] for gateway routing.
class MemberAgentStatusEndpoint {
  const MemberAgentStatusEndpoint({
    required this.url,
    this.token,
    this.sessionId,
  });

  final String url;

  /// Per-session bus token; set for remote members only.
  final String? token;

  /// Local gateway routing header value.
  final String? sessionId;

  bool get isRemote => token != null && token!.isNotEmpty;

  int? get port {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasPort) return null;
    return uri.port;
  }

  factory MemberAgentStatusEndpoint.local(
    AgentStatusGateway gateway, {
    required String sessionId,
  }) => MemberAgentStatusEndpoint(
    url: gateway.agentStatusEndpoint.toString(),
    sessionId: sessionId,
  );

  /// Remote binding: reverse-tunnel loopback URL + bus token.
  factory MemberAgentStatusEndpoint.remote(RemoteStatusBinding binding) =>
      MemberAgentStatusEndpoint(
        url: binding.agentStatusUrl,
        token: binding.token,
      );

  Map<String, String> headersFor(String memberId) {
    final headers = <String, String>{agentStatusMemberHeader: memberId};
    final session = sessionId;
    if (session != null && session.isNotEmpty) {
      headers[agentStatusSessionHeader] = session;
    }
    final t = token;
    if (t != null && t.isNotEmpty) {
      headers[agentStatusTokenHeader] = t;
    }
    return headers;
  }
}
