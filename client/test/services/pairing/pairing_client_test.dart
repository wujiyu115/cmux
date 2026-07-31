import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/pairing_client.dart';
import 'package:teampilot/services/pairing/ws_transport.dart';

void main() {
  group('PairingClient.connect candidate fallback', () {
    test('a blackholed candidate times out so the next one is still tried', () {
      fakeAsync((async) {
        final dialed = <String>[];
        final client = PairingClient(
          connector: (url) {
            dialed.add(url.toString());
            // Unreachable subnet / stale VPN route: the SYN is dropped, so the
            // dial neither completes nor errors on its own.
            if (url.host == '10.0.0.2') return Completer<WsTransport>().future;
            return Future.error(StateError('connection refused'));
          },
        );
        addTearDown(client.close);

        Object? thrown;
        var succeeded = false;
        unawaited(
          client
              .connect(
                wsUrls: const [
                  'ws://10.0.0.2:5555/pair/ws',
                  'ws://192.168.1.5:5555/pair/ws',
                ],
                token: 'onetime-code',
                hostPublicKeyB64: 'AAABBBCCC',
              )
              .then(
                (_) => succeeded = true,
                onError: (Object error) => thrown = error,
              ),
        );

        // Still inside the dial budget: the loop has not moved on yet.
        async.elapse(const Duration(seconds: 3));
        expect(dialed, const ['ws://10.0.0.2:5555/pair/ws']);
        expect(thrown, isNull);

        // Crossing PairingClient.dialTimeout abandons the dead candidate.
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect(dialed, const [
          'ws://10.0.0.2:5555/pair/ws',
          'ws://192.168.1.5:5555/pair/ws',
        ]);
        expect(succeeded, isFalse);
        expect('$thrown', contains('All pairing URLs failed'));
      });
    });

    test('the dial budget is per candidate, not shared across the list', () {
      fakeAsync((async) {
        final dialed = <String>[];
        final client = PairingClient(
          connector: (url) {
            dialed.add(url.toString());
            return Completer<WsTransport>().future;
          },
        );
        addTearDown(client.close);

        unawaited(
          client
              .connect(
                wsUrls: const [
                  'ws://10.0.0.2:5555/pair/ws',
                  'ws://10.0.0.3:5555/pair/ws',
                  'ws://10.0.0.4:5555/pair/ws',
                ],
                token: 'onetime-code',
                hostPublicKeyB64: 'AAABBBCCC',
              )
              .then((_) {}, onError: (Object _) {}),
        );

        // Three blackholed candidates cost 4s each rather than stalling on the
        // first one forever, and stay inside the cubit's 25s connect budget.
        for (var expected = 1; expected <= 3; expected++) {
          async.flushMicrotasks();
          expect(dialed, hasLength(expected));
          async.elapse(PairingClient.dialTimeout);
        }
        async.flushMicrotasks();
        expect(dialed, hasLength(3));
      });
    });
  });
}
