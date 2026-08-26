import 'dart:async';
import 'dart:typed_data';

import 'package:synchronized/synchronized.dart';

import '../../utils/logging/logger_utils.dart';
import 'pairing_upload_target.dart';
import 'upload_limits.dart';

/// Bytes per upload chunk on the wire, advertised to the phone in the
/// `upload.begin` reply.
///
/// The host dictates it — deliberately, so it can be tuned without a phone
/// update. 256 KiB rather than 64 KiB because a 512 MiB video is 2048 frames and
/// 2048 acks at this size instead of 8192 of each, and because 16 chunks in
/// flight then fills a LAN pipe over a 5–10 ms round trip.
///
/// It is also the ceiling, not a compromise: each frame is copied several times
/// end to end (frame encode → E2EE box → socket), so 1 MiB chunks would mean
/// multiple megabytes of transient garbage per frame.
const uploadWireChunkSize = 256 * 1024;

/// Result of [PairingUploadReceiver.begin].
class UploadBeginResult {
  const UploadBeginResult.ok(this.transferId, this.chunkSize) : code = null;
  const UploadBeginResult.error(this.code)
    : transferId = 0,
      chunkSize = 0;

  final int transferId;
  final int chunkSize;
  final String? code;

  bool get isOk => code == null;
}

/// Result of [PairingUploadReceiver.commit].
class UploadCommitResult {
  const UploadCommitResult.ok(this.path) : code = null;
  const UploadCommitResult.error(this.code) : path = null;

  final String? path;
  final String? code;

  bool get isOk => code == null;
}

class _Transfer {
  _Transfer({required this.target, required this.declaredSize});

  final PairingUploadTarget target;
  final int declaredSize;

  /// Bytes received but not yet handed to [target]. Bounded by
  /// [PairingUploadTarget.preferredFlushBytes] plus one chunk.
  final BytesBuilder buffer = BytesBuilder(copy: false);

  /// Serialises flushes and the final append against each other. Two concurrent
  /// `appendBytes` on one path each do open(append)/write/close, so their byte
  /// order would be whatever the OS decides. `Lock` is FIFO, so queued flushes
  /// land in wire order.
  final Lock lock = Lock();

  int nextIndex = 0;
  int received = 0;

  /// Set once the transfer is gone, so a flush already queued behind the lock
  /// skips its write instead of recreating a file that was just deleted.
  bool dead = false;

  /// A failed flush cannot be attributed to the chunk that caused it — a
  /// disk-full at byte 300 MB surfaces on whichever chunk happens to trigger the
  /// next flush. That is how any buffered writer behaves. It is checked by the
  /// next [PairingUploadReceiver.chunk] (which abandons the transfer) and by
  /// [PairingUploadReceiver.commit] (which reports `write_failed`).
  Object? writeError;
}

/// Streams a chunked media upload from a paired phone onto a
/// [PairingUploadTarget], validating it as it goes.
///
/// This class knows the upload protocol and knows nothing about the filesystem —
/// opening the destination (and resolving which machine the pane lives on) is the
/// [PairingUploadOpener]'s job, which keeps this layer testable with a fake and
/// keeps storage concerns out of the pairing code.
///
/// **Backpressure is the load-bearing invariant.** A chunk that fits under the
/// target's flush threshold is acked immediately; the chunk that *triggers* a
/// flush is acked only once that flush has landed. That single rule turns the
/// phone's existing credit window into real disk backpressure, so host memory
/// stays at roughly `preferredFlushBytes + windowBytes` no matter how slow the
/// backend is — 42 MiB for a WSL target, rather than the whole 512 MiB file.
///
/// [abandonAll] MUST be called when the connection closes. It is no longer only
/// about releasing memory: every live transfer owns a part-file in the user's
/// working directory, and abandoning is what deletes it.
class PairingUploadReceiver {
  PairingUploadReceiver({
    required this.openTarget,
    required this.onAck,
    this.caps = const PairingUploadCaps(),
    this.chunkSize = 64 * 1024,
    this.maxConcurrentTransfers = 4,
  });

  final PairingUploadOpener openTarget;

  /// Emits `upload.ack` for [transferId] at [received] bytes.
  ///
  /// The receiver is the sole acker. Returning the ack from [chunk] instead
  /// cannot express the deferred case at all, and having both would mean two ack
  /// paths and two sources of truth.
  final void Function(int transferId, int received) onAck;

  final PairingUploadCaps caps;
  final int chunkSize;

  /// Cap on live transfers. With real part-files being written, an unbounded
  /// table means unbounded partial files in the user's directory.
  final int maxConcurrentTransfers;

  final Map<int, _Transfer> _transfers = {};
  int _nextId = 0;

  Future<UploadBeginResult> begin({
    required String workspaceId,
    required String cwd,
    required String filename,
    required int size,
  }) async {
    // Validate before allocating a transfer id: allocating and then rejecting
    // would leave gaps in the id sequence that look like lost frames when
    // debugging. Order is filename → extension → size → capacity.
    if (_isBadFilename(filename)) {
      return const UploadBeginResult.error('bad_filename');
    }
    // The extension both admits the file and picks its cap, so one lookup does
    // the work of two — a null means "not an allowed kind at all".
    final maxBytes = caps.maxBytesFor(filename);
    if (maxBytes == null) {
      return const UploadBeginResult.error('unsupported_type');
    }
    // One code covers the whole "declared size out of the acceptable range"
    // case — including a malformed negative size, not just a too-big one.
    if (size < 0 || size > maxBytes) {
      return const UploadBeginResult.error('too_large');
    }
    if (_transfers.length >= maxConcurrentTransfers) {
      return const UploadBeginResult.error('too_many');
    }

    final PairingUploadTarget target;
    try {
      target = await openTarget(
        workspaceId: workspaceId,
        cwd: cwd,
        filename: filename,
      );
    } on Object catch (e, st) {
      // Opening resolves the pane's machine and creates the part-file. Failing
      // here — before a single byte crossed the network — is the whole reason
      // this happens at begin rather than at commit.
      AppLogger.instance.w(
        'Pairing upload target failed to open ($e)',
        error: e,
        stackTrace: st,
      );
      return const UploadBeginResult.error('no_target');
    }

    final id = ++_nextId;
    _transfers[id] = _Transfer(target: target, declaredSize: size);
    return UploadBeginResult.ok(id, chunkSize);
  }

  /// Validates and buffers one chunk, flushing to the target when the buffer is
  /// full enough to be worth a write.
  ///
  /// Deliberately **synchronous**. Chunks arrive from the socket listener faster
  /// than an `appendBytes` completes (a WSL append is hundreds of milliseconds),
  /// and an `async` body would let chunk N+1 read `nextIndex` before chunk N had
  /// incremented it. A sync body runs to completion, so every counter mutation
  /// and every check below is as race-free as it was when this class assembled
  /// bytes in memory. The only asynchronous part is the flush, which is handed to
  /// the transfer's lock and never touches those counters.
  void chunk(int transferId, int chunkIndex, List<int> bytes) {
    final transfer = _transfers[transferId];
    // Unknown id: nothing to ack and nothing to abandon. The phone finds out at
    // commit or at its own ack timeout.
    if (transfer == null) return;
    if (transfer.writeError != null) {
      unawaited(abandon(transferId));
      return;
    }
    if (chunkIndex != transfer.nextIndex) {
      // WebSocket preserves order, so a gap means something is wrong; writing a
      // file with a hole in it would be worse than failing.
      unawaited(abandon(transferId));
      return;
    }
    if (transfer.received + bytes.length > transfer.declaredSize) {
      unawaited(abandon(transferId));
      return;
    }

    transfer.buffer.add(bytes);
    transfer.received += bytes.length;
    transfer.nextIndex++;

    if (transfer.buffer.length < transfer.target.preferredFlushBytes) {
      onAck(transferId, transfer.received);
      return;
    }

    // takeBytes() leaves a fresh buffer behind, so the next chunk accumulates
    // independently of the flush now in flight.
    final pending = transfer.buffer.takeBytes();
    final high = transfer.received;
    unawaited(
      transfer.lock.synchronized(() async {
        if (transfer.dead) return;
        try {
          await transfer.target.append(pending);
          // The withheld ack. Sending it here rather than above is what makes
          // the phone's credit window wait for the disk.
          if (!transfer.dead) onAck(transferId, high);
        } on Object catch (e, st) {
          transfer.writeError = e;
          AppLogger.instance.w(
            'Pairing upload append failed ($e)',
            error: e,
            stackTrace: st,
          );
        }
      }),
    );
  }

  Future<UploadCommitResult> commit(int transferId) async {
    final transfer = _transfers[transferId];
    if (transfer == null) {
      return const UploadCommitResult.error('unknown_transfer');
    }
    if (transfer.received != transfer.declaredSize) {
      // Truncation is what this check exists to catch; half a file on disk is
      // worse than no file.
      await abandon(transferId);
      return const UploadCommitResult.error('write_failed');
    }
    // Drop it before touching the target: whether the write succeeds or throws,
    // the transfer must not linger in the table.
    _transfers.remove(transferId);
    try {
      // Inside the same lock, so the tail lands after every queued flush.
      return await transfer.lock.synchronized(() async {
        final error = transfer.writeError;
        if (error != null) throw error;
        final tail = transfer.buffer.takeBytes();
        if (tail.isNotEmpty) await transfer.target.append(tail);
        return UploadCommitResult.ok(await transfer.target.commit());
      });
    } on Object catch (e, st) {
      AppLogger.instance.w(
        'Pairing upload commit failed ($e)',
        error: e,
        stackTrace: st,
      );
      await transfer.target.abort();
      return const UploadCommitResult.error('write_failed');
    }
  }

  Future<void> abandon(int id) async {
    final transfer = _transfers.remove(id);
    if (transfer == null) return;
    // Set synchronously so a flush already queued behind the lock skips its
    // write; then abort *inside* the lock, so deleting the part-file cannot race
    // an in-flight append that would recreate it.
    transfer.dead = true;
    await transfer.lock.synchronized(transfer.target.abort);
  }

  Future<void> abandonAll() =>
      Future.wait(_transfers.keys.toList().map(abandon));

  bool _isBadFilename(String name) {
    return name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains('\x00');
  }
}
