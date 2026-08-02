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
}
