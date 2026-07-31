import 'dart:convert';
import 'dart:typed_data';

/// Wire framing for the pairing channel's *application* payloads (post-handshake,
/// inside the E2EE box).
///
/// Two shapes share one byte stream, distinguished by a leading kind byte:
/// - **JSON** (`0x01`) — low-frequency control: JSON-RPC requests/responses,
///   events (`auth`, `session.list`, `terminal.resize`, `terminal.closed`, …).
/// - **Binary terminal** (`0x02` output / `0x03` input / `0x04` snapshot) — the
///   hot path. Raw PTY bytes with a varint `sub` (+ `seq` for host→client) and
///   no base64 inflation.
///
/// The plaintext handshake frames (`hello`/`hello.ack`) are plain JSON on the
/// socket and never pass through here.
enum PairingFrameKind { json, output, input, snapshot }

sealed class PairingFrame {
  const PairingFrame();
}

class JsonFrame extends PairingFrame {
  const JsonFrame(this.data);
  final Map<String, Object?> data;
}

class OutputFrame extends PairingFrame {
  const OutputFrame(this.sub, this.seq, this.bytes);
  final int sub;
  final int seq;
  final Uint8List bytes;
}

class SnapshotFrame extends PairingFrame {
  const SnapshotFrame(this.sub, this.seq, this.bytes);
  final int sub;
  final int seq;
  final Uint8List bytes;
}

class InputFrame extends PairingFrame {
  const InputFrame(this.sub, this.bytes);
  final int sub;
  final Uint8List bytes;
}

class PairingCodec {
  const PairingCodec._();

  static const _kJson = 0x01;
  static const _kOutput = 0x02;
  static const _kInput = 0x03;
  static const _kSnapshot = 0x04;

  static Uint8List encodeJson(Map<String, Object?> data) {
    final body = utf8.encode(jsonEncode(data));
    final out = Uint8List(1 + body.length);
    out[0] = _kJson;
    out.setRange(1, out.length, body);
    return out;
  }

  static Uint8List encodeOutput(int sub, int seq, Uint8List bytes) =>
      _encodeSeqFrame(_kOutput, sub, seq, bytes);

  static Uint8List encodeSnapshot(int sub, int seq, Uint8List bytes) =>
      _encodeSeqFrame(_kSnapshot, sub, seq, bytes);

  static Uint8List encodeInput(int sub, Uint8List bytes) {
    final builder = _Writer()
      ..byte(_kInput)
      ..varint(sub)
      ..raw(bytes);
    return builder.take();
  }

  static Uint8List _encodeSeqFrame(
    int kind,
    int sub,
    int seq,
    Uint8List bytes,
  ) {
    final builder = _Writer()
      ..byte(kind)
      ..varint(sub)
      ..varint(seq)
      ..raw(bytes);
    return builder.take();
  }

  static PairingFrame decode(Uint8List frame) {
    if (frame.isEmpty) {
      throw const FormatException('empty pairing frame');
    }
    final reader = _Reader(frame);
    final kind = reader.byte();
    switch (kind) {
      case _kJson:
        final text = utf8.decode(reader.rest());
        final decoded = jsonDecode(text);
        if (decoded is! Map) {
          throw const FormatException('json frame is not an object');
        }
        return JsonFrame(decoded.cast<String, Object?>());
      case _kOutput:
        final sub = reader.varint();
        final seq = reader.varint();
        return OutputFrame(sub, seq, reader.rest());
      case _kSnapshot:
        final sub = reader.varint();
        final seq = reader.varint();
        return SnapshotFrame(sub, seq, reader.rest());
      case _kInput:
        final sub = reader.varint();
        return InputFrame(sub, reader.rest());
      default:
        throw FormatException('unknown pairing frame kind: $kind');
    }
  }
}

class _Writer {
  final _bytes = <int>[];

  void byte(int b) => _bytes.add(b & 0xff);

  void varint(int value) {
    if (value < 0) throw ArgumentError('varint must be non-negative: $value');
    var v = value;
    while (v >= 0x80) {
      _bytes.add((v & 0x7f) | 0x80);
      v >>= 7;
    }
    _bytes.add(v);
  }

  void raw(Uint8List data) => _bytes.addAll(data);

  Uint8List take() => Uint8List.fromList(_bytes);
}

class _Reader {
  _Reader(this._data);
  final Uint8List _data;
  int _pos = 0;

  int byte() {
    if (_pos >= _data.length) throw const FormatException('frame underrun');
    return _data[_pos++];
  }

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = byte();
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
      if (shift > 63) throw const FormatException('varint too long');
    }
    return result;
  }

  Uint8List rest() {
    final out = Uint8List.sublistView(_data, _pos);
    _pos = _data.length;
    return out;
  }
}
