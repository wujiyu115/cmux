import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Thin binary wrapper over a [WebSocket] shared by both roles.
///
/// The host obtains its socket from `WebSocketTransformer.upgrade`, the mobile
/// client from `WebSocket.connect`. Only binary frames are used on the wire;
/// inbound text frames (unexpected) are dropped. [inbound] is a broadcast-free
/// single-subscription stream — each connection has exactly one consumer.
class WsTransport {
  WsTransport(this._socket);

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
