import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/pairing_frames.dart';

void main() {
  group('encodeUpload', () {
    test('writes the kind byte, both varints, then the raw payload', () {
      final frame = PairingCodec.encodeUpload(
        7,
        3,
        Uint8List.fromList(const [1, 2, 3]),
      );
      expect(frame[0], 0x05, reason: 'upload kind');
      expect(frame[1], 7, reason: 'transferId as a single-byte varint');
      expect(frame[2], 3, reason: 'chunkIndex as a single-byte varint');
      expect(frame.sublist(3), const [1, 2, 3], reason: 'payload is not framed');
    });

    test('encodes multi-byte varints', () {
      // 300 needs two LEB128 bytes; a transfer id or chunk index above 127 must
      // not be truncated to one byte.
      final frame = PairingCodec.encodeUpload(300, 200, Uint8List(0));
      final decoded = PairingCodec.decode(frame) as UploadFrame;
      expect(decoded.transferId, 300);
      expect(decoded.chunkIndex, 200);
    });

    test('carries an empty payload', () {
      final decoded =
          PairingCodec.decode(PairingCodec.encodeUpload(1, 0, Uint8List(0)))
              as UploadFrame;
      expect(decoded.bytes, isEmpty);
    });
  });

  group('decode', () {
    test('round-trips an upload frame', () {
      final payload = Uint8List.fromList(List.generate(256, (i) => i));
      final decoded = PairingCodec.decode(
        PairingCodec.encodeUpload(42, 9, payload),
      );
      expect(decoded, isA<UploadFrame>());
      final upload = decoded as UploadFrame;
      expect(upload.transferId, 42);
      expect(upload.chunkIndex, 9);
      expect(upload.bytes, payload);
    });

    test('still round-trips every pre-existing kind', () {
      // Regression guard: adding a fifth kind must not shift any other kind's
      // layout. These four carry the terminal hot path.
      final json = PairingCodec.decode(
        PairingCodec.encodeJson({'method': 'ping'}),
      );
      expect((json as JsonFrame).data['method'], 'ping');

      final bytes = Uint8List.fromList(utf8.encode('ls -la'));
      final output = PairingCodec.decode(PairingCodec.encodeOutput(1, 2, bytes));
      expect((output as OutputFrame).sub, 1);
      expect(output.seq, 2);
      expect(output.bytes, bytes);

      final snapshot = PairingCodec.decode(
        PairingCodec.encodeSnapshot(3, 4, bytes),
      );
      expect((snapshot as SnapshotFrame).sub, 3);
      expect(snapshot.seq, 4);

      final input = PairingCodec.decode(PairingCodec.encodeInput(5, bytes));
      expect((input as InputFrame).sub, 5);
      expect(input.bytes, bytes);
    });

    test('throws FormatException on an unknown kind', () {
      expect(
        () => PairingCodec.decode(Uint8List.fromList(const [0x7f])),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when an upload frame is truncated', () {
      // Kind byte present but the transferId varint is missing.
      expect(
        () => PairingCodec.decode(Uint8List.fromList(const [0x05])),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
