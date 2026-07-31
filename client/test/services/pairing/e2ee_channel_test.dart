import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/e2ee_channel.dart';

void main() {
  group('E2eeChannel', () {
    late E2eeChannel alice;
    late E2eeChannel bob;

    setUp(() {
      final a = E2eeChannel.newEphemeral();
      final b = E2eeChannel.newEphemeral();
      alice = E2eeChannel.derive(
        myEphemeralPrivate: a.privateKey,
        theirEphemeralPublic: b.publicKey,
      );
      bob = E2eeChannel.derive(
        myEphemeralPrivate: b.privateKey,
        theirEphemeralPublic: a.publicKey,
      );
    });

    test('both peers derive the same shared secret (round-trip)', () {
      final msg = Uint8List.fromList([1, 2, 3, 4, 5]);
      final wire = alice.encrypt(msg);
      expect(bob.decrypt(wire), msg);
      // And the reverse direction.
      final reply = Uint8List.fromList(utf8Bytes('pong'));
      expect(alice.decrypt(bob.encrypt(reply)), reply);
    });

    test('each encrypt uses a fresh nonce (ciphertext differs)', () {
      final msg = Uint8List.fromList([9, 9, 9]);
      final a = alice.encrypt(msg);
      final b = alice.encrypt(msg);
      expect(a, isNot(b));
      // Both still decrypt back to the same plaintext.
      expect(bob.decrypt(a), msg);
      expect(bob.decrypt(b), msg);
    });

    test('tampered ciphertext fails authentication', () {
      final wire = alice.encrypt(Uint8List.fromList([1, 2, 3]));
      wire[wire.length - 1] ^= 0xff; // flip a byte in the box
      expect(() => bob.decrypt(wire), throwsA(anything));
    });

    test('a foreign channel cannot decrypt (pin mismatch analog)', () {
      final stranger = E2eeChannel.derive(
        myEphemeralPrivate: E2eeChannel.newEphemeral().privateKey,
        theirEphemeralPublic: E2eeChannel.newEphemeral().publicKey,
      );
      final wire = alice.encrypt(Uint8List.fromList([7, 7, 7]));
      expect(() => stranger.decrypt(wire), throwsA(anything));
    });

    test('a frame shorter than the nonce throws FormatException', () {
      expect(
        () => bob.decrypt(Uint8List(4)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

List<int> utf8Bytes(String s) => s.codeUnits;
