import 'dart:async';
import 'dart:typed_data';

import 'pairing_frames.dart';
import 'upload_source.dart';

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

/// Raised when the local caller cancelled the upload.
///
/// Deliberately *not* a [PairingUploadException]: the UI has to tell "the user
/// stopped it" from "the host refused it", and a `code: 'cancelled'` would fall
/// through the code mapping's default arm into a spurious "upload failed"
/// snackbar for something the user did on purpose.
class PairingUploadCancelled implements Exception {
  const PairingUploadCancelled();

  @override
  String toString() => 'PairingUploadCancelled';
}

/// Chunks a phone-side file over the pairing channel, pacing it with a credit
/// window.
///
/// **Why a window at all:** the phone→host direction has no backpressure —
/// `WsTransport.send` calls `WebSocket.add`, and Dart's `WebSocket` buffers
/// without limit. A video written chunk-after-chunk would land in memory all at
/// once on the phone. The window bounds what is in flight to
/// `windowChunks * chunkSize` (4 MiB in production), releasing on each ack, at
/// the cost of one round trip per window.
///
/// Since the host only acks a chunk once its write has landed, that same window
/// doubles as disk backpressure: a slow WSL or SFTP destination throttles the
/// phone instead of letting it race ahead into host memory.
///
/// **Why an [UploadSource] and not a `Uint8List`:** a 512 MiB video cannot be
/// read into memory on a phone. The source is pulled one chunk at a time, so peak
/// memory here is one chunk regardless of file size.
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

  /// Completed by [cancel]. A `Completer` rather than a bare flag because the
  /// sender also has to be woken *out of* an ack wait, not merely checked between
  /// chunks — a 4 MiB window on a slow link can park it for seconds.
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  /// Stops the upload at the next chunk boundary and tells the host to discard
  /// the part-file. Idempotent; safe to call after the upload has finished.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  /// Uploads [source] and returns the absolute host path it landed at.
  ///
  /// Does not close [source] — the caller owns it, because a source rejected
  /// before this method is ever reached still has to be closed.
  Future<String> upload({
    required int sub,
    required String filename,
    required UploadSource source,
    void Function(int sent, int total)? onProgress,
  }) async {
    final total = source.length;
    final begin = await _rpc('upload.begin', {
      'sub': sub,
      'filename': filename,
      'size': total,
    });
    if (begin['ok'] != true) {
      throw PairingUploadException(begin['code'] as String? ?? 'write_failed');
    }
    final transferId = begin['transferId']! as int;
    final chunkSize = begin['chunkSize']! as int;
    final windowBytes = chunkSize * _windowChunks;

    // Cancelled during the begin round trip: the host has already created a
    // part-file, so tell it to drop that before sending a single chunk.
    if (isCancelled) {
      unawaited(_abort(transferId));
      throw const PairingUploadCancelled();
    }

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
      while (sent < total) {
        if (isCancelled) {
          unawaited(_abort(transferId));
          throw const PairingUploadCancelled();
        }
        // Bound what is in flight. Dart's WebSocket buffers without limit, so
        // without this every chunk of a large video lands in memory at once.
        while (sent - acked >= windowBytes) {
          final gate = Completer<void>();
          waiter = gate;
          try {
            // Either an ack or a cancel releases the wait. `Future.any` does not
            // cancel the loser, but both are one-shot Completers so nothing
            // leaks.
            await Future.any([
              gate.future,
              _cancelled.future,
            ]).timeout(_ackTimeout);
          } finally {
            // Clearing it here as well as in the ack listener keeps a late ack
            // from completing a gate this loop has already abandoned.
            waiter = null;
          }
          // Handled at the top of the next iteration, which is also the only
          // place that aborts — one exit path, not two.
          if (isCancelled) break;
        }
        if (isCancelled) continue;
        final bytes = await source.read(chunkSize);
        // Short read before the declared total: the file shrank under us. Stop
        // here and let the host's `received != declaredSize` check reject the
        // commit rather than landing a truncated file.
        if (bytes.isEmpty) break;
        _send(PairingCodec.encodeUpload(transferId, index, bytes));
        sent += bytes.length;
        onProgress?.call(sent, total);
        index++;
      }
      final commit = await _rpc('upload.commit', {'transferId': transferId});
      if (commit['ok'] != true) {
        throw PairingUploadException(
          commit['code'] as String? ?? 'write_failed',
        );
      }
      // Cancelled while the commit was in flight. The host already dropped the
      // transfer from its table before writing, so aborting now is a no-op and
      // the file lands — harmless, in the pane's cwd, and the user asked for it a
      // moment earlier. Discarding the path here is what keeps it out of the
      // composer. Deliberately no host-side "delete the committed file" path:
      // that would be an arbitrary-path delete primitive this protocol does not
      // have.
      if (isCancelled) throw const PairingUploadCancelled();
      return commit['path']! as String;
    } finally {
      await ackSub.cancel();
    }
  }

  /// Best-effort "forget that transfer". Fire-and-forget by design: the user has
  /// already moved on, and the host answers `ok` even for an id it has never
  /// heard of, so there is nothing to react to.
  Future<void> _abort(int transferId) async {
    try {
      await _rpc('upload.abort', {'transferId': transferId});
    } on Object {
      // The connection may already be gone; the host drops the transfer when it
      // closes anyway.
    }
  }
}
