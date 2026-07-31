import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/pairing_frames.dart';

void main() {
  group('PairingCodec', () {
    test('JSON frame round-trips', () {
      final frame = PairingCodec.encodeJson({
        'id': 7,
        'method': 'terminal.subscribe',
        'params': {'catalogId': 'chat:s1:main'},
      });
      final decoded = PairingCodec.decode(frame);
      expect(decoded, isA<JsonFrame>());
      final data = (decoded as JsonFrame).data;
      expect(data['id'], 7);
      expect(data['method'], 'terminal.subscribe');
      expect((data['params'] as Map)['catalogId'], 'chat:s1:main');
    });

    test('output frame round-trips raw bytes with sub + seq', () {
      final payload = Uint8List.fromList([0x1b, 0x5b, 0x33, 0x6d, 0xff, 0x00]);
      final frame = PairingCodec.encodeOutput(3, 4096, payload);
      final decoded = PairingCodec.decode(frame);
      expect(decoded, isA<OutputFrame>());
      final out = decoded as OutputFrame;
      expect(out.sub, 3);
      expect(out.seq, 4096);
      expect(out.bytes, payload);
    });

    test('snapshot frame round-trips', () {
      final payload = Uint8List.fromList([1, 2, 3]);
      final decoded = PairingCodec.decode(
        PairingCodec.encodeSnapshot(1, 300000, payload),
      );
      expect(decoded, isA<SnapshotFrame>());
      final snap = decoded as SnapshotFrame;
      expect(snap.sub, 1);
      expect(snap.seq, 300000);
      expect(snap.bytes, payload);
    });

    test('input frame round-trips (no seq)', () {
      final payload = Uint8List.fromList('ls -la\n'.codeUnits);
      final decoded = PairingCodec.decode(PairingCodec.encodeInput(2, payload));
      expect(decoded, isA<InputFrame>());
      final input = decoded as InputFrame;
      expect(input.sub, 2);
      expect(input.bytes, payload);
    });

    test('varint handles large sub / seq values', () {
      final decoded = PairingCodec.decode(
        PairingCodec.encodeOutput(300, 1 << 40, Uint8List(0)),
      );
      final out = decoded as OutputFrame;
      expect(out.sub, 300);
      expect(out.seq, 1 << 40);
      expect(out.bytes, isEmpty);
    });

    test('decoding an empty frame throws', () {
      expect(
        () => PairingCodec.decode(Uint8List(0)),
        throwsA(isA<FormatException>()),
      );
    });

    test('decoding an unknown kind byte throws', () {
      expect(
        () => PairingCodec.decode(Uint8List.fromList([0x7f, 0, 0])),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
