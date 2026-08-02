import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Message type nibbles carried in the high nibble of the frame's second byte
/// (`byte1 >> 4`). Client frames identify the request kind; server frames
/// identify a result vs. an error.
class VolcMessageType {
  const VolcMessageType._();

  /// Client → server: the initial JSON configuration ("full client request").
  static const int fullClientRequest = 0x01;

  /// Client → server: a raw PCM audio chunk ("audio only request").
  static const int audioOnlyRequest = 0x02;

  /// Server → client: a recognition result ("full server response").
  static const int fullServerResponse = 0x09;

  /// Server → client: an error frame.
  static const int errorResponse = 0x0f;
}

/// Serialization nibbles carried in the high nibble of the frame's third byte
/// (`byte2 >> 4`).
class VolcSerialization {
  const VolcSerialization._();

  /// No structured serialization — the payload is raw bytes (e.g. PCM audio).
  static const int raw = 0x00;

  /// The payload is UTF-8 JSON.
  static const int json = 0x01;
}

/// A decoded Volcengine (火山引擎豆包) speech frame.
///
/// The fields the caller needs are surfaced: the [messageType] and [flags]
/// nibbles, the signed [sequence], and the (already gunzipped) [payload].
///
/// Error frames (`messageType == 0x0f`) carry no gzipped payload; instead they
/// populate [errorCode] and [errorMessage]. For a result frame those two are
/// `null`; for an error frame [payload] is empty. This keeps an error frame's
/// numeric code from silently landing in [sequence].
class VolcFrame {
  const VolcFrame({
    required this.messageType,
    required this.flags,
    required this.sequence,
    required this.payload,
    this.errorCode,
    this.errorMessage,
  });

  final int messageType;
  final int flags;
  final int sequence;
  final List<int> payload;

  /// The server's numeric error code — set only on error frames (`0x0f`).
  final int? errorCode;

  /// The server's plain-UTF-8 error message — set only on error frames
  /// (`0x0f`). Never gzip-decoded.
  final String? errorMessage;
}

/// Builds one Volcengine binary frame.
///
/// Wire layout (matches `_buildFrame` in the Nexterm reference provider):
///
/// ```
/// byte 0      : 0x11               protocol version 1, header size 1 (=4 bytes)
/// byte 1      : messageType<<4 | flags
/// byte 2      : serialization<<4 | compression  (compression is always 0x01 = gzip)
/// byte 3      : 0x00               reserved
/// bytes 4..7  : int32  sequence    (big-endian; negative for the last packet)
/// bytes 8..11 : uint32 payloadLen  (big-endian; length of the gzipped body)
/// bytes 12..  : gzip(payload)
/// ```
///
/// [payload] is gzipped here; the server rejects an uncompressed body, so
/// compression is hard-coded to gzip even for raw-serialization audio frames.
Uint8List buildVolcFrame({
  required int messageType,
  required int serialization,
  required int flags,
  required int sequence,
  required List<int> payload,
}) {
  const int compression = 0x01; // gzip, always.
  final Uint8List body = Uint8List.fromList(gzip.encode(payload));

  final Uint8List frame = Uint8List(12 + body.length);
  frame[0] = 0x11; // protocol v1, header size 1 (4 bytes).
  frame[1] = (messageType << 4) | (flags & 0x0f);
  frame[2] = (serialization << 4) | (compression & 0x0f);
  frame[3] = 0x00;
  final ByteData header = ByteData.sublistView(frame, 0, 12);
  header.setInt32(4, sequence); // big-endian by default; signed.
  header.setUint32(8, body.length); // big-endian by default.
  frame.setRange(12, 12 + body.length, body);
  return frame;
}

/// Decodes a frame that WE produced with [buildVolcFrame] — i.e. an
/// **outbound client→server** frame, round-tripped in tests. This is NOT for
/// live server traffic; for **inbound server→client** frames use
/// [decodeVolcServerFrame].
///
/// It inverts [buildVolcFrame]'s fixed layout: a 4-byte header, an int32
/// sequence at offset 4, a uint32 body length at offset 8, then the body. The
/// body is gunzipped when the compression nibble (`byte2 & 0x0f`) is `0x01`,
/// otherwise it is returned as-is.
VolcFrame parseVolcFrame(List<int> bytes) {
  final Uint8List data = Uint8List.fromList(bytes);
  if (data.length < 12) {
    throw FormatException(
      'Volcengine frame too short: need at least 12 bytes, got ${data.length}',
    );
  }

  final int messageType = (data[1] >> 4) & 0x0f;
  final int flags = data[1] & 0x0f;
  final int compression = data[2] & 0x0f;

  final ByteData header = ByteData.sublistView(data, 0, 12);
  final int sequence = header.getInt32(4);
  final int length = header.getUint32(8);

  if (12 + length > data.length) {
    throw FormatException(
      'Volcengine frame payload overruns buffer: header claims $length bytes '
      'but only ${data.length - 12} remain (total ${data.length})',
    );
  }

  final Uint8List body = data.sublist(12, 12 + length);
  final List<int> payload =
      compression == 0x01 ? gzip.decode(body) : body;

  return VolcFrame(
    messageType: messageType,
    flags: flags,
    sequence: sequence,
    payload: payload,
  );
}

/// Decodes a live **inbound server→client** Volcengine frame. This is the
/// counterpart to [parseVolcFrame] (which is only for our own outbound frames)
/// — use THIS one for anything that arrives off the socket.
///
/// Ported byte-for-byte from `_handleServerMessage` in the Nexterm reference
/// provider. The wire layout is flag-gated and per-message-type; it does NOT
/// match [buildVolcFrame]'s fixed layout:
///
/// ```
/// byte 0      : header descriptor; headerSize = (byte0 & 0x0f) * 4
/// byte 1      : messageType<<4 | flags
/// byte 2      : serialization<<4 | compression
/// byte 3      : reserved
/// [headerSize ..]  optional, flag-gated fields consumed by offset:
///   if flags & 0x01 : + int32 sequence      (read, surfaced on VolcFrame)
///   flags & 0x02    => this is the last packet
///   if flags & 0x04 : + int32 event field   (skipped)
///   then, depending on messageType:
///     0x0f error  : int32 errorCode, uint32 msgLen, then PLAIN UTF-8 message
///                   (never gzip-decoded)
///     otherwise   : uint32 payloadLen, then payload
///                   (gzip-decoded when compression nibble == 0x01)
/// ```
///
/// Every read at a computed offset is bounds-checked first because these bytes
/// come straight off a socket. A malformed frame — a short buffer, a length
/// that overruns, bad gzip, or invalid UTF-8 — always throws [FormatException]
/// and never a raw exception that could crash the session.
VolcFrame decodeVolcServerFrame(List<int> bytes) {
  final Uint8List data = Uint8List.fromList(bytes);
  if (data.length < 4) {
    throw FormatException(
      'Volcengine server frame too short: need at least 4 header bytes, '
      'got ${data.length}',
    );
  }

  final int headerSize = (data[0] & 0x0f) * 4;
  final int messageType = (data[1] >> 4) & 0x0f;
  final int flags = data[1] & 0x0f;
  final int compression = data[2] & 0x0f;

  int offset = headerSize;

  int sequence = 0;
  if (flags & 0x01 != 0) {
    if (data.length < offset + 4) {
      throw FormatException(
        'Volcengine server frame truncated: sequence field needs 4 bytes at '
        'offset $offset but only ${data.length} present',
      );
    }
    sequence = ByteData.sublistView(data, offset, offset + 4).getInt32(0);
    offset += 4;
  }

  if (flags & 0x04 != 0) {
    if (data.length < offset + 4) {
      throw FormatException(
        'Volcengine server frame truncated: event field needs 4 bytes at '
        'offset $offset but only ${data.length} present',
      );
    }
    offset += 4; // event field — consumed but not surfaced.
  }

  if (messageType == VolcMessageType.errorResponse) {
    if (data.length < offset + 8) {
      throw FormatException(
        'Volcengine error frame truncated: need 8 bytes for code+length at '
        'offset $offset but only ${data.length} present',
      );
    }
    final int errorCode =
        ByteData.sublistView(data, offset, offset + 4).getInt32(0);
    final int msgLen =
        ByteData.sublistView(data, offset + 4, offset + 8).getUint32(0);
    offset += 8;
    if (data.length < offset + msgLen) {
      throw FormatException(
        'Volcengine error frame message overruns buffer: header claims '
        '$msgLen bytes at offset $offset but only ${data.length - offset} '
        'remain',
      );
    }
    // Error messages are plain UTF-8 — never gzip-decoded, even when the
    // compression nibble is set. Malformed UTF-8 throws FormatException.
    final String errorMessage =
        utf8.decode(data.sublist(offset, offset + msgLen));
    return VolcFrame(
      messageType: messageType,
      flags: flags,
      sequence: sequence,
      payload: const <int>[],
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  // Result frame (0x09) and any other non-error type: uint32 payload length
  // then the (optionally gzipped) payload.
  if (data.length < offset + 4) {
    throw FormatException(
      'Volcengine result frame truncated: payload length needs 4 bytes at '
      'offset $offset but only ${data.length} present',
    );
  }
  final int payloadLen =
      ByteData.sublistView(data, offset, offset + 4).getUint32(0);
  offset += 4;
  if (data.length < offset + payloadLen) {
    throw FormatException(
      'Volcengine result frame payload overruns buffer: header claims '
      '$payloadLen bytes at offset $offset but only ${data.length - offset} '
      'remain',
    );
  }

  final Uint8List body = data.sublist(offset, offset + payloadLen);
  final List<int> payload;
  if (compression == 0x01) {
    try {
      payload = gzip.decode(body);
    } on FormatException {
      rethrow;
    } catch (e) {
      // Guarantee callers only ever see FormatException for a bad frame.
      throw FormatException('Volcengine result frame gzip decode failed: $e');
    }
  } else {
    payload = body;
  }

  return VolcFrame(
    messageType: messageType,
    flags: flags,
    sequence: sequence,
    payload: payload,
  );
}
