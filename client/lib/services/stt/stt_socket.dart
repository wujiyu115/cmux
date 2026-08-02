import 'package:web_socket_channel/io.dart';

import 'stt_provider.dart';

/// [SttSocket] over a real WebSocket.
///
/// `IOWebSocketChannel` rather than `WebSocketChannel.connect` because
/// Volcengine authenticates with request headers, and only the IO channel can
/// set them.
class WebSocketSttSocket implements SttSocket {
  WebSocketSttSocket._(this._channel);

  final IOWebSocketChannel _channel;

  /// Matches [SttSocketFactory].
  static Future<SttSocket> connect(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    final channel = IOWebSocketChannel.connect(url, headers: headers);
    await channel.ready;
    return WebSocketSttSocket._(channel);
  }

  @override
  Stream<dynamic> get messages => _channel.stream;

  @override
  void send(Object data) => _channel.sink.add(data);

  @override
  Future<void> close() => _channel.sink.close();
}
