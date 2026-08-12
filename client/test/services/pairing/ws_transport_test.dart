import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/ws_transport.dart';

/// The real socket both roles wrap; only [pingInterval] is asserted here.
class _FakeWebSocket extends Stream<Object?> implements WebSocket {
  Duration? interval;

  @override
  Duration? get pingInterval => interval;

  @override
  set pingInterval(Duration? value) => interval = value;

  @override
  StreamSubscription<Object?> listen(
    void Function(Object?)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => const Stream<Object?>.empty().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('WsTransport arms the keepalive ping by default', () {
    final socket = _FakeWebSocket();

    WsTransport(socket);

    // Without this a half-open socket (phone dozed, WiFi dropped, NAT entry
    // expired) is never noticed by either side.
    expect(socket.interval, kPairingPingInterval);
  });

  test('WsTransport allows the keepalive to be disabled', () {
    final socket = _FakeWebSocket();

    WsTransport(socket, pingInterval: null);

    expect(socket.interval, isNull);
  });
}
