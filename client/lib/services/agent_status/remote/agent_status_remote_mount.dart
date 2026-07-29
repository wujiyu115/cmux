import 'dart:async';
import 'dart:math';

import '../../ssh/ssh_member_session.dart';
import 'remote_status_binding.dart';
import 'reverse_tunnel.dart';

/// Per-tab mount that tunnels a **remote** (ssh) seat's `POST /agent-status`
/// reports back to the local gateway over an SSH reverse tunnel.
///
/// Owns per-member reverse tunnels only. The SSH session plane lives in
/// [memberSession] and is closed by the tab when the member disconnects — not
/// by [close].
class AgentStatusRemoteMount {
  AgentStatusRemoteMount({
    required this.httpBusPort,
    required SshMemberSession memberSession,
    ReverseTunnel Function()? tunnelFactory,
    String? token,
  }) : memberSession = memberSession,
       token = token ?? _randomToken(),
       _tunnelFactory = tunnelFactory ?? memberSession.newReverseTunnel;

  /// Test / harness constructor without a live [SshMemberSession].
  AgentStatusRemoteMount.testing({
    required this.httpBusPort,
    required ReverseTunnel Function() tunnelFactory,
    String? token,
  }) : token = token ?? _randomToken(),
       memberSession = null,
       _tunnelFactory = tunnelFactory;

  final int httpBusPort;
  final SshMemberSession? memberSession;
  final String token;

  final ReverseTunnel Function() _tunnelFactory;

  final _members = <String, _MountedMember>{};

  Future<RemoteStatusBinding> bindHttpMember(String memberId) async {
    final existing = _members[memberId];
    if (existing != null) return existing.binding;

    final tunnel = _tunnelFactory();
    TunnelPump? pump;
    var pumpStarted = false;
    try {
      final port = await tunnel.open();
      pump = TunnelPump(tunnel: tunnel, localPort: httpBusPort);
      await pump.start();
      pumpStarted = true;

      final binding = RemoteStatusBinding(token: token, tunnelPort: port);
      _members[memberId] = _MountedMember(
        binding: binding,
        tunnels: [(tunnel: tunnel, pump: pump)],
      );
      return binding;
    } on Object {
      if (pumpStarted) {
        await pump!.stop();
      } else {
        await tunnel.close();
      }
      rethrow;
    }
  }

  /// Tears down tunnels. Does not close [memberSession].
  Future<void> close() async {
    for (final m in _members.values) {
      for (final t in m.tunnels) {
        await t.pump.stop();
      }
    }
    _members.clear();
  }

  static String _randomToken() {
    final rng = Random.secure();
    return List.generate(24, (_) => rng.nextInt(16).toRadixString(16)).join();
  }
}

class _MountedMember {
  _MountedMember({required this.binding, required this.tunnels});

  final RemoteStatusBinding binding;
  final List<({ReverseTunnel tunnel, TunnelPump pump})> tunnels;
}

String archFromUname(String unameM) {
  final m = unameM.trim().toLowerCase();
  return switch (m) {
    'x86_64' || 'amd64' => 'linux-x64',
    'aarch64' || 'arm64' => 'linux-arm64',
    _ => m,
  };
}
