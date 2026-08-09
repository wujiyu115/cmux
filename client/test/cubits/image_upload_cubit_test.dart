import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/image_upload_cubit.dart';
import 'package:teampilot/services/pairing/pairing_upload_sender.dart';

void main() {
  late List<String> paths;
  late List<ImageUploadFailure> failures;
  late PickedImage? picked;
  late Object? uploadError;
  late int uploadCalls;
  late List<int> progressTicks;
  late String uploadedPath;
  late void Function(void Function(int, int)? onProgress)? driveProgress;

  ImageUploadCubit build({int maxBytes = 100}) {
    final cubit = ImageUploadCubit(
      maxBytes: maxBytes,
      pickImage: () async => picked,
      upload:
          ({
            required String filename,
            required Uint8List bytes,
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
    progressTicks = [];
    uploadError = null;
    uploadedPath = '/home/dev/app/photo.jpg';
    driveProgress = null;
    picked = PickedImage(
      filename: 'photo.jpg',
      bytes: Uint8List.fromList(List.filled(10, 1)),
    );
  });

  test('starts idle with no progress', () {
    final cubit = build();
    expect(cubit.state.status, ImageUploadStatus.idle);
    expect(cubit.state.progress, 0);
    cubit.close();
  });

  test('emits the host path and returns to idle', () async {
    final cubit = build();
    await cubit.pickAndUpload();
    expect(paths, ['/home/dev/app/photo.jpg']);
    expect(cubit.state.status, ImageUploadStatus.idle);
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
    expect(cubit.state.status, ImageUploadStatus.idle);
    await cubit.close();
  });

  test('refuses an oversized image without a round trip', () async {
    // Checking locally means the user hears about it immediately instead of
    // after a wasted begin.
    picked = PickedImage(
      filename: 'huge.png',
      bytes: Uint8List.fromList(List.filled(101, 1)),
    );
    final cubit = build(maxBytes: 100);
    await cubit.pickAndUpload();
    expect(failures, [ImageUploadFailure.tooLarge]);
    expect(uploadCalls, 0);
    await cubit.close();
  });

  test('maps the host too_large code', () async {
    uploadError = const PairingUploadException('too_large');
    final cubit = build();
    await cubit.pickAndUpload();
    expect(failures, [ImageUploadFailure.tooLarge]);
    await cubit.close();
  });

  test('maps the host unsupported_type code', () async {
    uploadError = const PairingUploadException('unsupported_type');
    final cubit = build();
    await cubit.pickAndUpload();
    expect(failures, [ImageUploadFailure.unsupportedType]);
    await cubit.close();
  });

  test('maps every other host code to a generic failure', () async {
    for (final code in ['bad_filename', 'no_target', 'write_failed', 'weird']) {
      failures = [];
      uploadError = PairingUploadException(code);
      final cubit = build();
      await cubit.pickAndUpload();
      expect(failures, [ImageUploadFailure.failed], reason: code);
      await cubit.close();
    }
  });

  test('maps a non-protocol error to a generic failure and returns to idle',
      () async {
    uploadError = StateError('socket died');
    final cubit = build();
    await cubit.pickAndUpload();
    expect(failures, [ImageUploadFailure.failed]);
    expect(cubit.state.status, ImageUploadStatus.idle);
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

  test('close does not emit after the cubit is gone', () async {
    final cubit = build();
    await cubit.close();
    await expectLater(cubit.pickAndUpload(), completes);
    expect(uploadCalls, 0);
  });
}
