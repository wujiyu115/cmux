import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// How often each side sends a protocol-level ping. Without this a socket that
/// died without a FIN — phone dozed, WiFi dropped, NAT entry expired — stays
/// open forever on both ends: the host keeps a dead connection in its set and
/// the phone keeps feeding a mirror nothing will ever answer. `dart:io` closes
/// the socket when a ping goes unanswered for this long, which turns a silent
/// half-open connection into an `onDone` both sides can act on.
const kPairingPingInterval = Duration(seconds: 20);

/// Thin binary wrapper over a [WebSocket] shared by both roles.
///
/// The host obtains its socket from `WebSocketTransformer.upgrade`, the mobile
/// client from `WebSocket.connect`. Only binary frames are used on the wire;
/// inbound text frames (unexpected) are dropped. [inbound] is a broadcast-free
/// single-subscription stream — each connection has exactly one consumer.
class WsTransport {
  WsTransport(this._socket, {Duration? pingInterval = kPairingPingInterval}) {
    // Set on the constructor rather than per role: both the host's upgrade and
    // the phone's dial funnel through here, so neither can forget it.
    _socket.pingInterval = pingInterval;
  }

  final WebSocket _socket;

  static Future<WsTransport> connect(Uri url) async =>
      WsTransport(await WebSocket.connect(url.toString()));

  Stream<Uint8List> get inbound => _socket
      .where((event) => event is List<int>)
      .map((event) => Uint8List.fromList(event as List<int>));

  void send(Uint8List bytes) => _socket.add(bytes);

  Future<void> close([int? code, String? reason]) => _socket.close(code, reason);

  int? get closeCode => _socket.closeCode;
}
