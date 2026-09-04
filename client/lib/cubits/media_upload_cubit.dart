import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/pairing/pairing_upload_sender.dart';
import '../services/pairing/upload_limits.dart';
import '../services/pairing/upload_source.dart';
import '../utils/logging/logger_utils.dart';

/// Where a media upload is in its lifecycle.
///
/// [picking] covers the photo-sheet window; [uploading] covers the chunked
/// transfers of the whole picked batch (its counters span the batch, so the
/// ring is one 0→100% sweep across the files), during which
/// [MediaUploadState.progress] advances so the button can repaint per
/// acknowledged megabyte. [cancelling] exists so the button can stop being
/// tappable and stop reporting a progress figure that is no longer going
/// anywhere.
enum MediaUploadStatus { idle, picking, uploading, cancelling }

/// Why an upload failed. An enum so no user-facing string lives in the cubit.
enum MediaUploadFailureReason { tooLarge, unsupportedType, failed }

/// One upload failure, carrying whatever the UI needs to word it.
///
/// [kind] and [limitBytes] travel with the event rather than being a default on
/// the widget that renders it: "Image is larger than 25 MB" and "Video is larger
/// than 512 MB" are different sentences with different numbers, and the cubit is
/// the only thing that knows which applied.
@immutable
class MediaUploadFailure {
  const MediaUploadFailure(this.reason, {this.kind, this.limitBytes});

  final MediaUploadFailureReason reason;

  /// Set for [MediaUploadFailureReason.tooLarge]; null when the kind is unknown
  /// (an extension the phone does not recognize either).
  final UploadMediaKind? kind;

  /// The cap that was exceeded, in bytes. Set alongside [kind].
  final int? limitBytes;
}

/// A photo or video chosen on the phone, ready to hand to
/// [PairingUploadSender].
///
/// Carries a [source] rather than bytes: reading the file into memory is exactly
/// what makes a video upload impossible on a phone. Whoever receives one owns
/// closing it, on every path — including the ones that reject it.
@immutable
class PickedMedia {
  const PickedMedia({required this.filename, required this.source});

  final String filename;
  final UploadSource source;
}

/// The live upload status plus its byte counters.
///
/// No `==`: a `status` change should always rebuild the upload button, so every
/// emit is a distinct instance. Widgets that only care about a subset must use
/// `buildWhen` (see the next task).
@immutable
class MediaUploadState {
  const MediaUploadState({
    required this.status,
    this.sentBytes = 0,
    this.totalBytes = 0,
  });

  const MediaUploadState.idle() : this(status: MediaUploadStatus.idle);

  final MediaUploadStatus status;
  final int sentBytes;
  final int totalBytes;

  /// Fraction acknowledged so far, `0` before any bytes are counted. Guards the
  /// divide so a zero-length total cannot produce a NaN.
  double get progress => totalBytes == 0 ? 0 : sentBytes / totalBytes;

  MediaUploadState copyWith({
    MediaUploadStatus? status,
    int? sentBytes,
    int? totalBytes,
  }) => MediaUploadState(
    status: status ?? this.status,
    sentBytes: sentBytes ?? this.sentBytes,
    totalBytes: totalBytes ?? this.totalBytes,
  );
}

/// Maps a host reject code to a failure. A `default` arm keeps the phone
/// degrading gracefully if the host grows a new code, rather than failing to
/// compile against one it has never heard of.
///
/// The host's `too_large` reply carries no number, but the phone knows the
/// filename it sent, so the applicable cap is recomputed here rather than added
/// to the protocol.
MediaUploadFailure _failureForCode(
  String code,
  String filename,
  PairingUploadCaps caps,
) {
  switch (code) {
    case 'too_large':
      return _tooLarge(filename, caps);
    case 'unsupported_type':
      return const MediaUploadFailure(MediaUploadFailureReason.unsupportedType);
    default:
      return const MediaUploadFailure(MediaUploadFailureReason.failed);
  }
}

MediaUploadFailure _tooLarge(String filename, PairingUploadCaps caps) {
  final kind = caps.kindOf(filename);
  return MediaUploadFailure(
    MediaUploadFailureReason.tooLarge,
    kind: kind,
    limitBytes: caps.maxBytesForKind(kind),
  );
}

/// Orchestrates picking one or more images or videos and uploading them over
/// the pairing channel — one batch at a time, one file at a time within the
/// batch, so peak memory stays at one in-flight chunk no matter how many files
/// were picked.
///
/// Recognized paths and failures leave as broadcast streams rather than state:
/// both are one-shot events (a path is written into a `TextEditingController`
/// the mirror page owns, a failure raises a snackbar that may arrive after the
/// panel unmounted), and putting either in state would re-emit on every
/// progress tick and rebuild the composer. A constructor callback would force
/// this cubit to be created only after its consumers exist; a stream lets them
/// subscribe on their own schedule. Progress *is* state — the button must
/// repaint — but it emits at most once per acknowledged megabyte, so that is
/// cheap.
class MediaUploadCubit extends Cubit<MediaUploadState> {
  MediaUploadCubit({
    required Future<List<PickedMedia>> Function() pickMedia,
    required Future<String> Function({
      required String filename,
      required UploadSource source,
      void Function(int sent, int total)? onProgress,
    })
    upload,
    void Function()? cancelUpload,
    PairingUploadCaps caps = const PairingUploadCaps(),
  }) : _pickMedia = pickMedia,
       _upload = upload,
       _cancelUpload = cancelUpload,
       _caps = caps,
       super(const MediaUploadState.idle());

  final Future<List<PickedMedia>> Function() _pickMedia;
  final Future<String> Function({
    required String filename,
    required UploadSource source,
    void Function(int sent, int total)? onProgress,
  })
  _upload;

  /// Tells the transport to stop. Optional so a consumer that never shows a
  /// cancel affordance need not wire one.
  final void Function()? _cancelUpload;

  /// The same per-kind caps the host enforces, applied before an upload is even
  /// attempted so an oversized pick is refused locally instead of after a wasted
  /// round trip. Shared table, so both sides name the same number.
  final PairingUploadCaps _caps;

  // Asynchronous delivery on purpose: with `sync: true` a `_paths.add(path)`
  // would run the listener (which writes into a `TextEditingController` and can
  // drive a rebuild) synchronously inside `pickAndUpload`'s `try` block, so any
  // exception it threw would land in the `catch` and be mis-reported as an
  // upload failure for an upload that actually succeeded. Plain `.broadcast()`
  // keeps the listener's work out of the cubit's error handling. Do not
  // reintroduce `sync: true` to quiet a test — add an event-loop turn instead.
  final _paths = StreamController<String>.broadcast();
  final _failures = StreamController<MediaUploadFailure>.broadcast();

  /// Host paths of committed uploads, ready to insert into the composer.
  Stream<String> get paths => _paths.stream;

  /// One event per upload failure, mapped to copy by the UI.
  Stream<MediaUploadFailure> get failures => _failures.stream;

  /// Set by [cancel] and by the in-flight upload ending in
  /// [PairingUploadCancelled]: everything in the batch after the file being
  /// sent is skipped. The user asked to stop, and files not yet sent are files
  /// they no longer want sent. Cleared when the next batch starts.
  bool _abortBatch = false;

  /// Stops the batch in flight. A no-op unless one is actually running.
  ///
  /// Emits no failure event: cancelling is a user action, like backing out of
  /// the photo sheet, so it must not raise a snackbar. The in-flight upload
  /// future throws [PairingUploadCancelled], which [pickAndUpload] both
  /// swallows and treats as its cue to skip the files still queued.
  void cancel() {
    if (isClosed) return;
    if (state.status != MediaUploadStatus.uploading) return;
    emit(state.copyWith(status: MediaUploadStatus.cancelling));
    _abortBatch = true;
    _cancelUpload?.call();
  }

  /// Picks photos or videos and uploads them one at a time, in pick order. A
  /// no-op if closed or if a batch is already in flight — only one runs at a
  /// time; use [cancel] to stop it.
  Future<void> pickAndUpload() async {
    if (isClosed) return;
    if (state.status != MediaUploadStatus.idle) return;

    emit(const MediaUploadState(status: MediaUploadStatus.picking));
    final List<PickedMedia> picked;
    try {
      picked = await _pickMedia();
    } on Object catch (e, st) {
      // The picker throwing must not escape: `pickAndUpload` is called from an
      // `onTap` and nobody awaits it, so an exception here used to leave the
      // status pinned at `picking` — a spinner that never stops and, because of
      // the single-flight guard below, an attach button dead for the rest of the
      // session.
      AppLogger.instance.w('Media pick failed', error: e, stackTrace: st);
      if (!isClosed) {
        _failures.add(
          const MediaUploadFailure(MediaUploadFailureReason.failed),
        );
        emit(const MediaUploadState.idle());
      }
      return;
    }
    // Every path from here on must close every source, or RandomAccessFiles
    // leak — real OS handles on iOS. The loop's `finally` covers each uploaded
    // file; the early returns, the local rejects and the skipped tail of a
    // cancelled batch have to do it themselves.
    if (isClosed) {
      for (final media in picked) {
        await media.source.close();
      }
      return;
    }
    // Backing out of the photo sheet is not a failure — no snackbar.
    if (picked.isEmpty) {
      emit(const MediaUploadState.idle());
      return;
    }

    // Local rejects happen before the first byte moves: the user hears about an
    // oversized file immediately rather than after everything ahead of it has
    // uploaded, and the progress total below only counts files that will
    // actually send. Identical rejects collapse into one event — five oversized
    // videos picked together are one sentence, not five snackbars queued four
    // seconds apart.
    final batch = <PickedMedia>[];
    final rejects =
        <
          (MediaUploadFailureReason, UploadMediaKind?, int?),
          MediaUploadFailure
        >{};
    for (final media in picked) {
      // A null cap means the extension is not allowed at all — the host would
      // say so anyway, but not after uploading it first.
      final cap = _caps.maxBytesFor(media.filename);
      if (cap == null) {
        await media.source.close();
        rejects[(MediaUploadFailureReason.unsupportedType, null, null)] ??=
            const MediaUploadFailure(MediaUploadFailureReason.unsupportedType);
        continue;
      }
      if (media.source.length > cap) {
        await media.source.close();
        final failure = _tooLarge(media.filename, _caps);
        rejects[(failure.reason, failure.kind, failure.limitBytes)] ??= failure;
        continue;
      }
      batch.add(media);
    }
    if (!isClosed) {
      for (final failure in rejects.values) {
        _failures.add(failure);
      }
    }
    // An empty batch (or a cubit that closed during validation) falls through
    // to the loop below, which closes each remaining source itself.
    if (batch.isEmpty) {
      if (!isClosed) emit(const MediaUploadState.idle());
      return;
    }

    _abortBatch = false;
    var totalBytes = 0;
    for (final media in batch) {
      totalBytes += media.source.length;
    }
    var doneBytes = 0;
    for (final media in batch) {
      if (_abortBatch || isClosed) {
        await media.source.close();
        continue;
      }
      emit(
        MediaUploadState(
          status: MediaUploadStatus.uploading,
          sentBytes: doneBytes,
          totalBytes: totalBytes,
        ),
      );
      try {
        final path = await _upload(
          filename: media.filename,
          source: media.source,
          onProgress: (sent, total) {
            if (!isClosed) {
              emit(
                state.copyWith(
                  sentBytes: doneBytes + sent,
                  totalBytes: totalBytes,
                ),
              );
            }
          },
        );
        if (!isClosed) _paths.add(path);
      } on PairingUploadCancelled {
        // The user stopped it. No failure event, no log — this is not an error.
        _abortBatch = true;
      } on PairingUploadException catch (e, st) {
        // One file being refused must not sentence the rest: the host rejected
        // *this* file, and the next one is a different file.
        if (!isClosed) {
          _failures.add(_failureForCode(e.code, media.filename, _caps));
        }
        AppLogger.instance.w(
          'Media upload rejected: ${e.code}',
          error: e,
          stackTrace: st,
        );
      } on Object catch (e, st) {
        if (!isClosed) {
          _failures.add(
            const MediaUploadFailure(MediaUploadFailureReason.failed),
          );
        }
        AppLogger.instance.w('Media upload failed', error: e, stackTrace: st);
      } finally {
        await media.source.close();
        // Counted even when the file failed or was cancelled: the ring is the
        // batch's, and this file is finished whatever happened to it.
        doneBytes += media.source.length;
      }
    }
    // State returns to idle only after the last file, not between files — a
    // mid-batch idle would read as "done" and let a double-tap start a second
    // batch under the first.
    if (!isClosed) emit(const MediaUploadState.idle());
  }

  @override
  Future<void> close() async {
    await _paths.close();
    await _failures.close();
    await super.close();
  }
}
