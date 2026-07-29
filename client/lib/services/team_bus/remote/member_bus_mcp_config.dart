/// Per-remote-seat binding produced by the agent-status reverse-tunnel mount.
class RemoteBusBinding {
  const RemoteBusBinding({
    required this.token,
    required this.tunnelPort,
  });

  final String token;

  /// Remote loopback port forwarded to the local gateway HTTP listener.
  final int tunnelPort;

  /// Remote URL seats POST permission / status hooks to.
  String get agentStatusUrl => 'http://127.0.0.1:$tunnelPort/agent-status';
}
