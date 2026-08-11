import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/pairing_client.dart';
import 'package:teampilot/services/pairing/pairing_ports.dart';
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
          // No ladder port answers, so this case ends where it always did.
          portProbe: (_, _) async => false,
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
          portProbe: (_, _) async => false,
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

  group('PairingClient.connect ladder fallback', () {
    test('re-probes the agreed ladder when the saved port moved', () async {
      // The desktop could not rebind the port it advertised at pairing time (a
      // second instance, or a Windows excluded range) and landed further down
      // the ladder. Without this the phone is stranded on a re-scan.
      final probed = <String>[];
      final dialed = <String>[];
      final client = PairingClient(
        connector: (url) {
          dialed.add(url.toString());
          return Future.error(StateError('connection refused'));
        },
        portProbe: (host, port) async {
          probed.add('$host:$port');
          return port == kPairingPortLadder[2];
        },
      );
      addTearDown(client.close);

      await expectLater(
        client.connect(
          wsUrls: ['ws://192.168.1.5:${kPairingPortLadder.first}/pair/ws'],
          token: 'device-token',
          hostPublicKeyB64: 'AAABBBCCC',
          deviceId: 'd1',
        ),
        throwsA(isA<Exception>()),
      );

      // The port from the saved URL is not re-probed; the rest of the ladder is.
      expect(probed, [
        '192.168.1.5:${kPairingPortLadder[1]}',
        '192.168.1.5:${kPairingPortLadder[2]}',
        '192.168.1.5:${kPairingPortLadder[3]}',
      ]);
      // Only the port that answered earns a full dial.
      expect(dialed, [
        'ws://192.168.1.5:${kPairingPortLadder.first}/pair/ws',
        'ws://192.168.1.5:${kPairingPortLadder[2]}/pair/ws',
      ]);
    });

    test('ports already covered by saved URLs are not re-probed', () async {
      var probes = 0;
      final client = PairingClient(
        connector: (_) => Future.error(StateError('refused')),
        portProbe: (_, _) async {
          probes++;
          return true;
        },
      );
      addTearDown(client.close);

      // Saved URLs already span the whole ladder, so the fallback has nothing
      // left to try and must not dial each port a second time.
      await expectLater(
        client.connect(
          wsUrls: [
            for (final port in kPairingPortLadder)
              'ws://192.168.1.5:$port/pair/ws',
          ],
          token: 't',
          hostPublicKeyB64: 'k',
        ),
        throwsA(isA<Exception>()),
      );
      // Every ladder port was already in the saved list, so nothing to probe.
      expect(probes, 0);
    });
  });
}
