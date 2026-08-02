import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/stt/volcengine_frame_codec.dart';

void main() {
  group('buildVolcFrame', () {
    test('lays out the 4-byte header then int32 seq and uint32 length', () {
      final frame = buildVolcFrame(
        messageType: VolcMessageType.fullClientRequest,
        serialization: VolcSerialization.json,
        flags: 0x01,
        sequence: 1,
        payload: utf8.encode('{}'),
      );
      expect(frame[0], 0x11, reason: 'protocol version 1, header size 1');
      expect(frame[1], (0x01 << 4) | 0x01);
      expect(frame[2], (VolcSerialization.json << 4) | 0x01, reason: 'gzip');
      expect(frame[3], 0x00);

      final header = ByteData.sublistView(frame, 0, 12);
      expect(header.getInt32(4), 1, reason: 'big-endian by default');
      final gzipped = gzip.encode(utf8.encode('{}'));
      expect(header.getUint32(8), gzipped.length);
      expect(frame.sublist(12), gzipped);
    });

    test('gzips the payload', () {
      // A raw-serialization audio frame carries PCM, not JSON, but is still
      // compressed — the server rejects an uncompressed body.
      final pcm = Uint8List(3200); // 100 ms of 16 kHz 16-bit silence
      final frame = buildVolcFrame(
        messageType: VolcMessageType.audioOnlyRequest,
        serialization: VolcSerialization.raw,
        flags: 0x00,
        sequence: 2,
        payload: pcm,
      );
      expect(frame[2], (VolcSerialization.raw << 4) | 0x01);
      final body = frame.sublist(12);
      expect(body.length, lessThan(pcm.length), reason: 'silence compresses');
      expect(gzip.decode(body), pcm);
    });

    test('encodes a negative sequence for the last packet', () {
      // The final audio frame flags the end of the utterance with a negated
      // sequence; an unsigned write here would send a huge positive number and
      // the server would keep waiting for more audio.
      final frame = buildVolcFrame(
        messageType: VolcMessageType.audioOnlyRequest,
        serialization: VolcSerialization.raw,
        flags: 0x03,
        sequence: -7,
        payload: const <int>[],
      );
      expect(frame[1] & 0x0f, 0x03);
      expect(ByteData.sublistView(frame, 0, 12).getInt32(4), -7);
    });
  });

  group('parseVolcFrame', () {
    test('round-trips a frame built by buildVolcFrame', () {
      final payload = utf8.encode('{"result":{"text":"ls"}}');
      final wire = buildVolcFrame(
        messageType: VolcMessageType.fullServerResponse,
        serialization: VolcSerialization.json,
        flags: 0x00,
        sequence: 5,
        payload: payload,
      );
      final parsed = parseVolcFrame(wire);
      expect(parsed.messageType, VolcMessageType.fullServerResponse);
      expect(parsed.sequence, 5);
      expect(parsed.payload, payload, reason: 'gunzipped by the parser');
    });

    test('reports the message type of an error frame', () {
      final wire = buildVolcFrame(
        messageType: VolcMessageType.errorResponse,
        serialization: VolcSerialization.json,
        flags: 0x00,
        sequence: 0,
        payload: utf8.encode('{"error":"bad token"}'),
      );
      expect(parseVolcFrame(wire).messageType, VolcMessageType.errorResponse);
    });

    test('throws FormatException on a truncated frame', () {
      expect(
        () => parseVolcFrame(const <int>[0x11, 0x10]),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when the length field overruns the buffer', () {
      final wire = Uint8List(12);
      wire[0] = 0x11;
      ByteData.sublistView(wire).setUint32(8, 999);
      expect(() => parseVolcFrame(wire), throwsA(isA<FormatException>()));
    });
  });

  // Big-endian field encoders used to hand-assemble server frames byte-for-byte
  // (NOT via buildVolcFrame — these fixtures must exercise the real, flag-gated
  // server layout that buildVolcFrame does not produce).
  List<int> u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();
  List<int> i32(int v) => (ByteData(4)..setInt32(0, v)).buffer.asUint8List();

  group('decodeVolcServerFrame', () {
    test('decodes a result frame with the sequence flag set (gzipped)', () {
      final payload = utf8.encode('{"result":{"text":"ls"}}');
      final body = gzip.encode(payload);
      final frame = <int>[
        0x11, // byte0: header descriptor -> headerSize = (0x11 & 0x0f) * 4 = 4
        (0x09 << 4) | 0x01, // byte1: messageType 0x09 (result), flags 0x01 (seq present)
        (0x01 << 4) | 0x01, // byte2: serialization json, compression gzip
        0x00, // byte3: reserved
        ...i32(42), // sequence field (present because flags & 0x01)
        ...u32(body.length), // uint32 payload length
        ...body, // gzipped payload
      ];

      final f = decodeVolcServerFrame(frame);
      expect(f.messageType, VolcMessageType.fullServerResponse);
      expect(f.flags, 0x01);
      expect(f.sequence, 42, reason: 'sequence field read at offset 4');
      expect(f.payload, payload, reason: 'gunzipped by the decoder');
      expect(f.errorCode, isNull);
      expect(f.errorMessage, isNull);
    });

    test('decodes a result frame with the sequence flag CLEAR (regression guard)',
        () {
      // With no sequence field, the uint32 payload length sits right after the
      // 4-byte header (offset 4). The old fixed parser reads bytes 4..8 as an
      // int32 sequence and 8..12 as the length, so it misparses this frame --
      // this test proves the offset is flag-driven.
      final payload = utf8.encode('{"result":{"text":"hi"}}');
      final frame = <int>[
        0x11, // byte0: headerSize = 4
        (0x09 << 4) | 0x00, // byte1: result, flags 0x00 (NO sequence field)
        (0x01 << 4) | 0x00, // byte2: json, compression 0x00 (raw, not gzipped)
        0x00, // byte3: reserved
        ...u32(payload.length), // uint32 payload length at offset 4
        ...payload, // plain payload
      ];

      final f = decodeVolcServerFrame(frame);
      expect(f.messageType, VolcMessageType.fullServerResponse);
      expect(f.sequence, 0, reason: 'no sequence field -> default 0');
      expect(f.payload, payload);
    });

    test('decodes a result frame with the event bit (flags & 0x04) set', () {
      final payload = utf8.encode('{"result":{"text":"ok"}}');
      final frame = <int>[
        0x11, // byte0: headerSize = 4
        (0x09 << 4) | 0x04, // byte1: result, flags 0x04 (event field present)
        (0x01 << 4) | 0x00, // byte2: json, compression 0x00 (raw)
        0x00, // byte3: reserved
        ...i32(7), // event field (present because flags & 0x04) -- skipped
        ...u32(payload.length), // uint32 payload length after the event field
        ...payload, // plain payload
      ];

      final f = decodeVolcServerFrame(frame);
      expect(f.messageType, VolcMessageType.fullServerResponse);
      expect(f.flags, 0x04);
      expect(f.payload, payload,
          reason: 'offset advanced past the 4-byte event field');
    });

    test('decodes an error frame as plain UTF-8 (never gzip-decoded)', () {
      final message = utf8.encode('bad token');
      final frame = <int>[
        0x11, // byte0: headerSize = 4
        (0x0f << 4) | 0x00, // byte1: messageType 0x0f (error), flags 0x00
        (0x01 << 4) | 0x01, // byte2: compression nibble 0x01 -- MUST be ignored for errors
        0x00, // byte3: reserved
        ...i32(45000003), // int32 error code
        ...u32(message.length), // uint32 message length
        ...message, // PLAIN UTF-8 message (not gzipped)
      ];

      final f = decodeVolcServerFrame(frame);
      expect(f.messageType, VolcMessageType.errorResponse);
      expect(f.errorCode, 45000003);
      expect(f.errorMessage, 'bad token',
          reason: 'plain UTF-8 despite the gzip compression nibble');
      expect(f.payload, isEmpty);
    });

    test('throws FormatException (not a raw exception) on a bad-gzip result body',
        () {
      // A result frame that claims gzip compression but carries non-gzip bytes
      // must surface as FormatException, never a raw crash.
      final body = utf8.encode('not gzip');
      final frame = <int>[
        0x11,
        (0x09 << 4) | 0x00, // result, no flags
        (0x01 << 4) | 0x01, // json, compression gzip
        0x00,
        ...u32(body.length),
        ...body,
      ];
      expect(() => decodeVolcServerFrame(frame),
          throwsA(isA<FormatException>()));
    });

    group('bounds checks each throw FormatException', () {
      test('buffer shorter than the 4-byte header', () {
        expect(() => decodeVolcServerFrame(const <int>[0x11, 0x90]),
            throwsA(isA<FormatException>()));
      });

      test('sequence field truncated', () {
        // flags & 0x01 set but no 4 bytes after the header.
        final frame = <int>[0x11, (0x09 << 4) | 0x01, 0x00, 0x00];
        expect(() => decodeVolcServerFrame(frame),
            throwsA(isA<FormatException>()));
      });

      test('event field truncated', () {
        // flags & 0x04 set but no 4 bytes after the header.
        final frame = <int>[0x11, (0x09 << 4) | 0x04, 0x00, 0x00];
        expect(() => decodeVolcServerFrame(frame),
            throwsA(isA<FormatException>()));
      });

      test('result payload-length field truncated', () {
        // Only 2 bytes where the uint32 length should be.
        final frame = <int>[0x11, 0x90, 0x00, 0x00, 0x00, 0x00];
        expect(() => decodeVolcServerFrame(frame),
            throwsA(isA<FormatException>()));
      });

      test('result payload length overruns the buffer', () {
        final frame = <int>[
          0x11, 0x90, 0x00, 0x00, // header, result, raw
          ...u32(999), // claims 999 bytes of body...
          // ...but none follow.
        ];
        expect(() => decodeVolcServerFrame(frame),
            throwsA(isA<FormatException>()));
      });

      test('error code+length fields truncated', () {
        // messageType 0x0f but no room for the 8 bytes of code + length.
        final frame = <int>[0x11, 0xf0, 0x00, 0x00];
        expect(() => decodeVolcServerFrame(frame),
            throwsA(isA<FormatException>()));
      });

      test('error message overruns the buffer', () {
        final frame = <int>[
          0x11, 0xf0, 0x00, 0x00, // header, error frame
          ...i32(1), // error code
          ...u32(999), // claims a 999-byte message...
          // ...but none follow.
        ];
        expect(() => decodeVolcServerFrame(frame),
            throwsA(isA<FormatException>()));
      });
    });
  });
}
