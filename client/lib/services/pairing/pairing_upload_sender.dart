import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'pairing_frames.dart';

/// An acknowledgement from the host of how many bytes of a transfer it has
/// received so far. Drives the credit window's release.
class PairingUploadAck {
  const PairingUploadAck({required this.transferId, required this.received});
  final int transferId;
  final int received;
}

/// Raised when the host refuses `upload.begin` or `upload.commit`; [code] is the
/// host's machine-readable reason (e.g. `too_large`, `write_failed`).
class PairingUploadException implements Exception {
  const PairingUploadException(this.code);
  final String code;

  @override
  String toString() => 'PairingUploadException: $code';
}

/// Chunks a phone-side file over the pairing channel, pacing it with a credit
/// window.
///
/// **Why a window at all:** the phone→host direction has no backpressure —
/// `WsTransport.send` calls `WebSocket.add`, and Dart's `WebSocket` buffers
/// without limit. A 25 MB photo written chunk-after-chunk would land in memory
/// all at once on the phone. The window bounds what is in flight to
/// `windowChunks * chunkSize` (1 MiB in production), releasing on each ack, at
/// the cost of one round trip per window.
///
/// **Why `chunkSize` comes from the host:** it is read from the `upload.begin`
/// reply rather than a local constant, so the host can retune it without
/// shipping a new phone build.
///
/// The transport is injected (`rpc`, `send`, `acks`) so this class never
/// touches a socket and stays trivially testable.
class PairingUploadSender {
  PairingUploadSender({
    required Future<Map<String, Object?>> Function(
      String method,
      Map<String, Object?> params,
    ) rpc,
    required void Function(Uint8List frame) send,
    required Stream<PairingUploadAck> acks,
    int windowChunks = 16,
    Duration ackTimeout = const Duration(seconds: 30),
  })  : _rpc = rpc,
        _send = send,
        _acks = acks,
        _windowChunks = windowChunks,
        _ackTimeout = ackTimeout;

  final Future<Map<String, Object?>> Function(
    String method,
    Map<String, Object?> params,
  ) _rpc;
  final void Function(Uint8List frame) _send;
  final Stream<PairingUploadAck> _acks;
  final int _windowChunks;
  final Duration _ackTimeout;

  Future<String> upload({
    required int sub,
    required String filename,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) async {
    final begin = await _rpc('upload.begin', {
      'sub': sub,
      'filename': filename,
      'size': bytes.length,
    });
    if (begin['ok'] != true) {
      throw PairingUploadException(begin['code'] as String? ?? 'write_failed');
    }
    final transferId = begin['transferId']! as int;
    final chunkSize = begin['chunkSize']! as int;
    final windowBytes = chunkSize * _windowChunks;

    var sent = 0;
    var acked = 0;
    Completer<void>? waiter;
    final ackSub = _acks.where((ack) => ack.transferId == transferId).listen((
      ack,
    ) {
      if (ack.received > acked) acked = ack.received;
      waiter?.complete();
      waiter = null;
    });
    try {
      var index = 0;
      var offset = 0;
      while (offset < bytes.length) {
        // Bound what is in flight. Dart's WebSocket buffers without limit, so
        // without this every chunk of a large photo lands in memory at once.
        while (sent - acked >= windowBytes) {
          final gate = Completer<void>();
          waiter = gate;
          await gate.future.timeout(_ackTimeout);
        }
        final end = min(offset + chunkSize, bytes.length);
        _send(
          PairingCodec.encodeUpload(
            transferId,
            index,
            Uint8List.sublistView(bytes, offset, end),
          ),
        );
        sent = end;
        onProgress?.call(sent, bytes.length);
        offset = end;
        index++;
      }
      final commit = await _rpc('upload.commit', {'transferId': transferId});
      if (commit['ok'] != true) {
        throw PairingUploadException(
          commit['code'] as String? ?? 'write_failed',
        );
      }
      return commit['path']! as String;
    } finally {
      await ackSub.cancel();
    }
  }
}
