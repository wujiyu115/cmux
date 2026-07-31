import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/pairing_offer.dart';

void main() {
  group('PairingOffer', () {
    const offer = PairingOffer(
      version: 1,
      wsUrls: ['ws://192.168.1.5:5555/pair/ws', 'ws://10.0.0.2:5555/pair/ws'],
      token: 'onetime-code',
      hostPublicKeyB64: 'AAABBBCCC',
      expiresAtMs: 123456,
    );

    test('deep link round-trips through tryParse', () {
      final link = offer.toDeepLink();
      expect(link, startsWith('teampilot://pair?code='));
      final parsed = PairingOffer.tryParse(link);
      expect(parsed, isNotNull);
      expect(parsed!.version, 1);
      expect(parsed.wsUrls, offer.wsUrls);
      expect(parsed.token, offer.token);
      expect(parsed.hostPublicKeyB64, offer.hostPublicKeyB64);
      expect(parsed.expiresAtMs, offer.expiresAtMs);
    });

    test('tryParse accepts a bare code payload without the URL wrapper', () {
      final link = offer.toDeepLink();
      final bareCode = link.split('code=').last;
      final parsed = PairingOffer.tryParse(bareCode);
      expect(parsed, isNotNull);
      expect(parsed!.token, offer.token);
    });

    test('tryParse returns null on malformed input', () {
      expect(PairingOffer.tryParse(''), isNull);
      expect(PairingOffer.tryParse('not base64 !!!'), isNull);
      expect(PairingOffer.tryParse('teampilot://pair?code='), isNull);
    });

    test('tryParse rejects payload missing required fields', () {
      // Valid base64url of a JSON object lacking token/pk.
      final parsed = PairingOffer.tryParse('eyJ2IjoxfQ');
      expect(parsed, isNull);
    });

    group('extractPairingCodeFromUrl', () {
      test('pulls the code query param from a teampilot link', () {
        expect(
          PairingOffer.extractPairingCodeFromUrl('teampilot://pair?code=abc123'),
          'abc123',
        );
      });

      test('returns null for a non-teampilot scheme', () {
        expect(
          PairingOffer.extractPairingCodeFromUrl('https://pair?code=abc'),
          isNull,
        );
      });

      test('returns null for a plain string with no scheme', () {
        expect(PairingOffer.extractPairingCodeFromUrl('abc123'), isNull);
      });
    });
  });

  group('PairingOfferWindow', () {
    test('consume succeeds once then closes the window (replay fails)', () {
      var now = 1000;
      final window = PairingOfferWindow(clock: () => now);
      final token = window.open(ttl: const Duration(minutes: 3));
      expect(window.isOpen, isTrue);
      expect(window.consume(token), isTrue);
      expect(window.isOpen, isFalse);
      // Replay of the same token fails after single use.
      expect(window.consume(token), isFalse);
    });

    test('consume fails on a wrong token', () {
      final window = PairingOfferWindow(clock: () => 0);
      window.open();
      expect(window.consume('wrong'), isFalse);
      // A failed attempt does not close the window.
      expect(window.isOpen, isTrue);
    });

    test('window expires after its TTL', () {
      var now = 0;
      final window = PairingOfferWindow(clock: () => now);
      final token = window.open(ttl: const Duration(seconds: 10));
      now = 10001; // past the 10s TTL
      expect(window.isOpen, isFalse);
      expect(window.consume(token), isFalse);
    });

    test('open produces a fresh token each time', () {
      final window = PairingOfferWindow(clock: () => 0);
      final a = window.open();
      final b = window.open();
      expect(a, isNot(b));
    });
  });
}
