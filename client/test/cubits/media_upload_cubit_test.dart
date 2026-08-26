import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/media_upload_cubit.dart';
import 'package:teampilot/services/pairing/pairing_upload_sender.dart';
import 'package:teampilot/services/pairing/upload_limits.dart';
import 'package:teampilot/services/pairing/upload_source.dart';

void main() {
  late List<String> paths;
  late List<MediaUploadFailure> failures;

  /// Small, unequal caps so a test can tell which one was applied.
  const caps = PairingUploadCaps(imageMaxBytes: 100, videoMaxBytes: 300);
  late PickedMedia? picked;
  late Object? uploadError;
  late int uploadCalls;
  late List<int> progressTicks;
  late int cancelCalls;
  late String uploadedPath;
  late void Function(void Function(int, int)? onProgress)? driveProgress;

  MediaUploadCubit build() {
    final cubit = MediaUploadCubit(
      caps: caps,
      pickMedia: () async => picked,
      cancelUpload: () => cancelCalls++,
      upload:
          ({
            required String filename,
            required UploadSource source,
            void Function(int sent, int total)? onProgress,
          }) async {
            uploadCalls++;
            final error = uploadError;
            if (error != null) throw error;
            driveProgress?.call(onProgress);
            return uploadedPath;
          },
    );
    cubit.paths.listen(paths.add);
    cubit.failures.listen(failures.add);
    return cubit;
  }

  setUp(() {
    paths = [];
    failures = [];
    uploadCalls = 0;
    cancelCalls = 0;
    progressTicks = [];
    uploadError = null;
    uploadedPath = '/home/dev/app/photo.jpg';
    driveProgress = null;
    picked = PickedMedia(
      filename: 'photo.jpg',
      source: MemoryUploadSource(Uint8List.fromList(List.filled(10, 1))),
    );
  });

  test('starts idle with no progress', () {
    final cubit = build();
    expect(cubit.state.status, MediaUploadStatus.idle);
    expect(cubit.state.progress, 0);
    cubit.close();
  });

  test('emits the host path and returns to idle', () async {
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);
    expect(paths, ['/home/dev/app/photo.jpg']);
    expect(cubit.state.status, MediaUploadStatus.idle);
    expect(failures, isEmpty);
    await cubit.close();
  });

  test('a cancelled pick uploads nothing and reports no failure', () async {
    // Backing out of the photo sheet is not an error.
    picked = null;
    final cubit = build();
    await cubit.pickAndUpload();
    expect(uploadCalls, 0);
    expect(failures, isEmpty);
    expect(cubit.state.status, MediaUploadStatus.idle);
    await cubit.close();
  });

  test('refuses an oversized image without a round trip', () async {
    // Checking locally means the user hears about it immediately instead of
    // after a wasted begin.
    picked = PickedMedia(
      filename: 'huge.png',
      source: MemoryUploadSource(Uint8List.fromList(List.filled(101, 1))),
    );
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);
    expect(failures.single.reason, MediaUploadFailureReason.tooLarge);
    expect(failures.single.kind, UploadMediaKind.image);
    expect(failures.single.limitBytes, 100);
    expect(uploadCalls, 0);
    await cubit.close();
  });

  test('accepts a video larger than the image cap', () async {
    // The whole point of per-kind caps: a 200-byte clip passes where a 200-byte
    // photo would not.
    picked = PickedMedia(
      filename: 'clip.mp4',
      source: MemoryUploadSource(Uint8List(200)),
    );
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);
    expect(failures, isEmpty);
    expect(uploadCalls, 1);
    await cubit.close();
  });

  test('refuses an oversized video and names the video cap', () async {
    picked = PickedMedia(
      filename: 'clip.mp4',
      source: MemoryUploadSource(Uint8List(301)),
    );
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);
    expect(failures.single.reason, MediaUploadFailureReason.tooLarge);
    expect(failures.single.kind, UploadMediaKind.video);
    expect(failures.single.limitBytes, 300);
    expect(uploadCalls, 0);
    await cubit.close();
  });

  test('refuses a disallowed extension without a round trip', () async {
    final source = _TrackingSource(4);
    picked = PickedMedia(filename: 'notes.txt', source: source);
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);
    expect(failures.single.reason, MediaUploadFailureReason.unsupportedType);
    expect(uploadCalls, 0);
    expect(source.closed, isTrue);
    await cubit.close();
  });

  test('maps the host too_large code', () async {
    uploadError = const PairingUploadException('too_large');
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);
    expect(failures.single.reason, MediaUploadFailureReason.tooLarge);
    expect(
      failures.single.limitBytes,
      100,
      reason: 'the host sends no number, so the phone recomputes it',
    );
    await cubit.close();
  });

  test('maps the host unsupported_type code', () async {
    uploadError = const PairingUploadException('unsupported_type');
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);
    expect(failures.single.reason, MediaUploadFailureReason.unsupportedType);
    await cubit.close();
  });

  test('maps every other host code to a generic failure', () async {
    for (final code in ['bad_filename', 'no_target', 'write_failed', 'weird']) {
      failures = [];
      uploadError = PairingUploadException(code);
      final cubit = build();
      await cubit.pickAndUpload();
      await Future<void>.delayed(Duration.zero);
      expect(
        failures.single.reason,
        MediaUploadFailureReason.failed,
        reason: code,
      );
      await cubit.close();
    }
  });

  test('maps a non-protocol error to a generic failure and returns to idle',
      () async {
    uploadError = StateError('socket died');
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);
    expect(failures.single.reason, MediaUploadFailureReason.failed);
    expect(cubit.state.status, MediaUploadStatus.idle);
    await cubit.close();
  });

  test('tracks progress while uploading', () async {
    driveProgress = (onProgress) {
      onProgress?.call(4, 10);
      progressTicks.add(4);
      onProgress?.call(10, 10);
      progressTicks.add(10);
    };
    final cubit = build();
    await cubit.pickAndUpload();
    expect(progressTicks, [4, 10]);
    await cubit.close();
  });

  test('ignores a second request while one is in flight', () async {
    // One upload at a time; cancelling would need another protocol frame.
    final cubit = build();
    final first = cubit.pickAndUpload();
    await cubit.pickAndUpload();
    await first;
    expect(uploadCalls, 1);
    await cubit.close();
  });

  group('cancel', () {
    test('goes uploading → cancelling → idle with no failure event', () async {
      // Cancelling is a user action, like backing out of the photo sheet, so it
      // must not raise a snackbar.
      final uploadStarted = Completer<void>();
      final held = Completer<String>();
      late MediaUploadCubit cubit;
      cubit = MediaUploadCubit(
        pickMedia: () async => picked,
        cancelUpload: () {
          cancelCalls++;
          held.completeError(const PairingUploadCancelled());
        },
        upload: ({required filename, required source, onProgress}) {
          uploadStarted.complete();
          return held.future;
        },
      );
      cubit.paths.listen(paths.add);
      cubit.failures.listen(failures.add);

      final done = cubit.pickAndUpload();
      await uploadStarted.future;
      expect(cubit.state.status, MediaUploadStatus.uploading);

      cubit.cancel();
      expect(cubit.state.status, MediaUploadStatus.cancelling);

      await done;
      await Future<void>.delayed(Duration.zero);
      expect(cancelCalls, 1);
      expect(cubit.state.status, MediaUploadStatus.idle);
      expect(failures, isEmpty, reason: 'the user did this on purpose');
      expect(paths, isEmpty);
      await cubit.close();
    });

    test('is a no-op when idle', () async {
      final cubit = build();
      cubit.cancel();
      expect(cancelCalls, 0);
      expect(cubit.state.status, MediaUploadStatus.idle);
      await cubit.close();
    });
  });

  test('closes the source of a locally rejected pick', () async {
    // A leaked RandomAccessFile is a real OS handle on iOS, and the reject path
    // is the easiest one to forget.
    final source = _TrackingSource(101);
    picked = PickedMedia(filename: 'huge.png', source: source);
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);
    expect(source.closed, isTrue);
    await cubit.close();
  });

  test('closes the source after a successful upload', () async {
    final source = _TrackingSource(10);
    picked = PickedMedia(filename: 'photo.jpg', source: source);
    final cubit = build();
    await cubit.pickAndUpload();
    expect(source.closed, isTrue);
    await cubit.close();
  });

  test('close does not emit after the cubit is gone', () async {
    final cubit = build();
    await cubit.close();
    await expectLater(cubit.pickAndUpload(), completes);
    expect(uploadCalls, 0);
  });
}

/// Reports [length] bytes and remembers whether it was closed.
class _TrackingSource implements UploadSource {
  _TrackingSource(this.length);

  @override
  final int length;

  var closed = false;

  @override
  Future<Uint8List> read(int maxBytes) async => Uint8List(0);

  @override
  Future<void> close() async => closed = true;
}
