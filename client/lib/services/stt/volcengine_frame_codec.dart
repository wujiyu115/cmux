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
/// Only the fields the caller needs are surfaced: the [messageType] and
/// [flags] nibbles, the signed [sequence], and the (already gunzipped)
/// [payload].
class VolcFrame {
  const VolcFrame({
    required this.messageType,
    required this.flags,
    required this.sequence,
    required this.payload,
  });

  final int messageType;
  final int flags;
  final int sequence;
  final List<int> payload;
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

/// Parses a frame produced by [buildVolcFrame] and returns its [VolcFrame].
///
/// This inverts [buildVolcFrame]'s fixed layout: a 4-byte header, an int32
/// sequence at offset 4, a uint32 body length at offset 8, then the body. The
/// body is gunzipped when the compression nibble (`byte2 & 0x0f`) is `0x01`,
/// otherwise it is returned as-is.
///
/// ---
/// The *real server* frames (ported byte-for-byte from `_handleServerMessage`
/// in the Nexterm reference) are richer and do NOT share one post-header
/// layout — the fixed parse above is intentionally the symmetric inverse of
/// our own builder, not a full server decoder. The true server layout is:
///
/// ```
/// byte 0      : header descriptor; headerSize = (byte0 & 0x0f) * 4
/// byte 1      : messageType<<4 | flags
/// byte 2      : serialization<<4 | compression
/// byte 3      : reserved
/// [headerSize .. ]  optional, flag-gated fields consumed by offset:
///   if flags & 0x01 (POS_SEQUENCE): + int32 sequence   (read then discarded)
///   flags & 0x02  => this is the last packet (isLast)
///   if flags & 0x04:                 + int32 event field
///   then, depending on messageType:
///     0x09 result frame : uint32 payloadLen, then payload (gzip-decoded if compression==0x01)
///     0x0f error frame  : int32 ERROR CODE, then uint32 msgLen, then UTF-8 message
/// ```
///
/// The critical divergence: in a result frame the first 4-byte slot after the
/// (optional) header fields is a payload *length*, but in an error frame that
/// same slot is an *error code* — the two frames do not share the post-header
/// field layout. A later socket task that decodes live server traffic must use
/// this flag-gated, per-type layout rather than the fixed parse here.
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
