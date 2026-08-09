import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/pairing/pairing_upload_sender.dart';
import '../utils/logging/logger_utils.dart';

/// Where an image upload is in its lifecycle.
///
/// [picking] covers the photo-sheet window; [uploading] covers the chunked
/// transfer, during which [ImageUploadState.progress] advances so the button
/// can repaint per acknowledged megabyte.
enum ImageUploadStatus { idle, picking, uploading }

/// An upload failure, mapped to localized copy by the UI (next task). Kept an
/// enum so no user-facing string lives in the cubit.
enum ImageUploadFailure { tooLarge, unsupportedType, failed }

/// A photo chosen on the phone, ready to hand to [PairingUploadSender].
@immutable
class PickedImage {
  const PickedImage({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;
}

/// The live upload status plus its byte counters.
///
/// No `==`: a `status` change should always rebuild the upload button, so every
/// emit is a distinct instance. Widgets that only care about a subset must use
/// `buildWhen` (see the next task).
@immutable
class ImageUploadState {
  const ImageUploadState({
    required this.status,
    this.sentBytes = 0,
    this.totalBytes = 0,
  });

  const ImageUploadState.idle() : this(status: ImageUploadStatus.idle);

  final ImageUploadStatus status;
  final int sentBytes;
  final int totalBytes;

  /// Fraction acknowledged so far, `0` before any bytes are counted. Guards the
  /// divide so a zero-length total cannot produce a NaN.
  double get progress => totalBytes == 0 ? 0 : sentBytes / totalBytes;

  ImageUploadState copyWith({
    ImageUploadStatus? status,
    int? sentBytes,
    int? totalBytes,
  }) => ImageUploadState(
    status: status ?? this.status,
    sentBytes: sentBytes ?? this.sentBytes,
    totalBytes: totalBytes ?? this.totalBytes,
  );
}

/// Maps a host reject code to a failure. A `default` arm keeps the phone
/// degrading gracefully if the host grows a new code, rather than failing to
/// compile against one it has never heard of.
ImageUploadFailure _failureForCode(String code) {
  switch (code) {
    case 'too_large':
      return ImageUploadFailure.tooLarge;
    case 'unsupported_type':
      return ImageUploadFailure.unsupportedType;
    default:
      return ImageUploadFailure.failed;
  }
}

/// Orchestrates picking one image and uploading it over the pairing channel,
/// one upload at a time.
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
class ImageUploadCubit extends Cubit<ImageUploadState> {
  ImageUploadCubit({
    required Future<PickedImage?> Function() pickImage,
    required Future<String> Function({
      required String filename,
      required Uint8List bytes,
      void Function(int sent, int total)? onProgress,
    }) upload,
    int maxBytes = 25 * 1024 * 1024,
  })  : _pickImage = pickImage,
        _upload = upload,
        _maxBytes = maxBytes,
        super(const ImageUploadState.idle());

  final Future<PickedImage?> Function() _pickImage;
  final Future<String> Function({
    required String filename,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) _upload;

  /// The largest photo accepted before an upload is even attempted, so an
  /// oversized pick is refused locally instead of after a wasted round trip.
  final int _maxBytes;

  // Asynchronous delivery on purpose: with `sync: true` a `_paths.add(path)`
  // would run the listener (which writes into a `TextEditingController` and can
  // drive a rebuild) synchronously inside `pickAndUpload`'s `try` block, so any
  // exception it threw would land in the `catch` and be mis-reported as an
  // upload failure for an upload that actually succeeded. Plain `.broadcast()`
  // keeps the listener's work out of the cubit's error handling. Do not
  // reintroduce `sync: true` to quiet a test — add an event-loop turn instead.
  final _paths = StreamController<String>.broadcast();
  final _failures = StreamController<ImageUploadFailure>.broadcast();

  /// Host paths of committed uploads, ready to insert into the composer.
  Stream<String> get paths => _paths.stream;

  /// One event per upload failure, mapped to copy by the UI.
  Stream<ImageUploadFailure> get failures => _failures.stream;

  /// Picks a photo and uploads it. A no-op if closed or if an upload is already
  /// in flight — cancelling would need another protocol frame, so only one runs
  /// at a time.
  Future<void> pickAndUpload() async {
    if (isClosed) return;
    if (state.status != ImageUploadStatus.idle) return;

    emit(const ImageUploadState(status: ImageUploadStatus.picking));
    final image = await _pickImage();
    if (isClosed) return;
    // Backing out of the photo sheet is not a failure — no snackbar.
    if (image == null) {
      emit(const ImageUploadState.idle());
      return;
    }

    // Check locally before the round trip so the user hears about an oversized
    // photo immediately rather than after a wasted begin.
    if (image.bytes.length > _maxBytes) {
      _failures.add(ImageUploadFailure.tooLarge);
      emit(const ImageUploadState.idle());
      return;
    }

    emit(
      ImageUploadState(
        status: ImageUploadStatus.uploading,
        sentBytes: 0,
        totalBytes: image.bytes.length,
      ),
    );
    try {
      final path = await _upload(
        filename: image.filename,
        bytes: image.bytes,
        onProgress: (sent, total) {
          if (!isClosed) {
            emit(state.copyWith(sentBytes: sent, totalBytes: total));
          }
        },
      );
      if (!isClosed) _paths.add(path);
    } on PairingUploadException catch (e, st) {
      _failures.add(_failureForCode(e.code));
      AppLogger.instance.w(
        'Image upload rejected: ${e.code}',
        error: e,
        stackTrace: st,
      );
    } on Object catch (e, st) {
      _failures.add(ImageUploadFailure.failed);
      AppLogger.instance.w('Image upload failed', error: e, stackTrace: st);
    } finally {
      // State returns to idle before anything else, or the button spins forever.
      if (!isClosed) emit(const ImageUploadState.idle());
    }
  }

  @override
  Future<void> close() async {
    await _paths.close();
    await _failures.close();
    await super.close();
  }
}
