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
  late List<PickedMedia> picked;
  late Object? pickError;
  late Object? uploadError;

  /// Filenames the fake upload refuses — per-file, unlike [uploadError] which
  /// fails everything, so a batch can fail in the middle and keep going.
  late Set<String> failUploadFor;
  late int uploadCalls;
  late List<String> uploadNames;
  late int maxInFlight;
  int inFlight = 0;
  late List<int> progressTicks;
  late int cancelCalls;
  late void Function(void Function(int, int)? onProgress)? driveProgress;

  MediaUploadCubit build() {
    final cubit = MediaUploadCubit(
      caps: caps,
      pickMedia: () async {
        final error = pickError;
        if (error != null) throw error;
        return picked;
      },
      cancelUpload: () => cancelCalls++,
      upload:
          ({
            required String filename,
            required UploadSource source,
            void Function(int sent, int total)? onProgress,
          }) async {
            uploadCalls++;
            uploadNames.add(filename);
            inFlight++;
            if (inFlight > maxInFlight) maxInFlight = inFlight;
            try {
              // A real transfer takes turns on the event loop; without this the
              // fake resolves synchronously and nothing can observe whether two
              // uploads ever ran at once.
              await Future<void>.delayed(Duration.zero);
              if (failUploadFor.contains(filename)) {
                throw const PairingUploadException('boom');
              }
              final error = uploadError;
              if (error != null) throw error;
              driveProgress?.call(onProgress);
              return '/home/dev/app/$filename';
            } finally {
              inFlight--;
            }
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
    uploadNames = [];
    maxInFlight = 0;
    inFlight = 0;
    cancelCalls = 0;
    progressTicks = [];
    failUploadFor = {};
    uploadError = null;
    pickError = null;
    driveProgress = null;
    picked = [
      PickedMedia(
        filename: 'photo.jpg',
        source: MemoryUploadSource(Uint8List.fromList(List.filled(10, 1))),
      ),
    ];
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
    // Backing out of the photo sheet is not an error — an empty pick, now that
    // the picker hands back a list.
    picked = const [];
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
    picked = [
      PickedMedia(
        filename: 'huge.png',
        source: MemoryUploadSource(Uint8List.fromList(List.filled(101, 1))),
      ),
    ];
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
    picked = [
      PickedMedia(
        filename: 'clip.mp4',
        source: MemoryUploadSource(Uint8List(200)),
      ),
    ];
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);
    expect(failures, isEmpty);
    expect(uploadCalls, 1);
    await cubit.close();
  });

  test('refuses an oversized video and names the video cap', () async {
    picked = [
      PickedMedia(
        filename: 'clip.mp4',
        source: MemoryUploadSource(Uint8List(301)),
      ),
    ];
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
    picked = [PickedMedia(filename: 'notes.txt', source: source)];
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

  test(
    'maps a non-protocol error to a generic failure and returns to idle',
    () async {
      uploadError = StateError('socket died');
      final cubit = build();
      await cubit.pickAndUpload();
      await Future<void>.delayed(Duration.zero);
      expect(failures.single.reason, MediaUploadFailureReason.failed);
      expect(cubit.state.status, MediaUploadStatus.idle);
      await cubit.close();
    },
  );

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

  test('a throwing picker reports a failure and returns to idle', () async {
    // Regression: `pickAndUpload` is called from an `onTap` and nobody awaits
    // it, so an exception out of the picker used to escape silently and leave
    // the status pinned at `picking` — a spinner that never stopped and, via the
    // single-flight guard, an attach button dead for the rest of the session.
    pickError = StateError('no activity found to handle the intent');
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);

    expect(failures.single.reason, MediaUploadFailureReason.failed);
    expect(cubit.state.status, MediaUploadStatus.idle);
    expect(uploadCalls, 0);
    await cubit.close();
  });

  test('stays usable after a throwing picker', () async {
    pickError = StateError('boom');
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);

    pickError = null;
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);

    expect(uploadCalls, 1, reason: 'the second attempt was not blocked');
    expect(paths, ['/home/dev/app/photo.jpg']);
    await cubit.close();
  });

  test('ignores a second request while one is in flight', () async {
    // One batch at a time; cancelling would need another protocol frame.
    final cubit = build();
    final first = cubit.pickAndUpload();
    await cubit.pickAndUpload();
    await first;
    expect(uploadCalls, 1);
    await cubit.close();
  });

  group('multi pick batches', () {
    test(
      'uploads one file at a time, in pick order, one path per file',
      () async {
        picked = [
          PickedMedia(
            filename: 'a.png',
            source: MemoryUploadSource(Uint8List(10)),
          ),
          PickedMedia(
            filename: 'b.png',
            source: MemoryUploadSource(Uint8List(10)),
          ),
          PickedMedia(
            filename: 'c.mp4',
            source: MemoryUploadSource(Uint8List(20)),
          ),
        ];
        final cubit = build();
        await cubit.pickAndUpload();
        await Future<void>.delayed(Duration.zero);
        expect(uploadNames, ['a.png', 'b.png', 'c.mp4']);
        expect(
          maxInFlight,
          1,
          reason: 'sequential uploads keep peak memory at one file',
        );
        expect(paths, [
          '/home/dev/app/a.png',
          '/home/dev/app/b.png',
          '/home/dev/app/c.mp4',
        ]);
        expect(cubit.state.status, MediaUploadStatus.idle);
        await cubit.close();
      },
    );

    test('one failed upload does not stop the rest of the batch', () async {
      picked = [
        PickedMedia(
          filename: 'a.png',
          source: MemoryUploadSource(Uint8List(10)),
        ),
        PickedMedia(
          filename: 'b.png',
          source: MemoryUploadSource(Uint8List(10)),
        ),
        PickedMedia(
          filename: 'c.png',
          source: MemoryUploadSource(Uint8List(10)),
        ),
      ];
      failUploadFor = {'b.png'};
      final cubit = build();
      await cubit.pickAndUpload();
      await Future<void>.delayed(Duration.zero);
      expect(uploadNames, ['a.png', 'b.png', 'c.png']);
      expect(paths, ['/home/dev/app/a.png', '/home/dev/app/c.png']);
      expect(failures.single.reason, MediaUploadFailureReason.failed);
      expect(cubit.state.status, MediaUploadStatus.idle);
      await cubit.close();
    });

    test(
      'an oversized pick is refused locally while the rest still upload',
      () async {
        final huge = _TrackingSource(101);
        picked = [
          PickedMedia(filename: 'huge.png', source: huge),
          PickedMedia(
            filename: 'photo.jpg',
            source: MemoryUploadSource(Uint8List(10)),
          ),
        ];
        final cubit = build();
        await cubit.pickAndUpload();
        await Future<void>.delayed(Duration.zero);
        expect(failures.single.reason, MediaUploadFailureReason.tooLarge);
        expect(uploadCalls, 1);
        expect(paths, ['/home/dev/app/photo.jpg']);
        expect(huge.closed, isTrue);
        await cubit.close();
      },
    );

    test('identical local rejects collapse into one failure event', () async {
      // Two oversized images and one oversized video picked together: one
      // image sentence and one video sentence — not three snackbars, and not
      // two identical image snackbars queued four seconds apart.
      final first = _TrackingSource(101);
      final second = _TrackingSource(101);
      final video = _TrackingSource(301);
      picked = [
        PickedMedia(filename: 'huge1.png', source: first),
        PickedMedia(filename: 'huge2.png', source: second),
        PickedMedia(filename: 'huge.mp4', source: video),
      ];
      final cubit = build();
      final statuses = <MediaUploadStatus>[];
      final sub = cubit.stream.listen((s) => statuses.add(s.status));
      await cubit.pickAndUpload();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(failures.map((f) => f.kind), [
        UploadMediaKind.image,
        UploadMediaKind.video,
      ]);
      expect(uploadCalls, 0);
      // Never entered uploading: nothing sent, so no bytes were ever counted.
      expect(statuses, [MediaUploadStatus.picking, MediaUploadStatus.idle]);
      expect([first.closed, second.closed, video.closed], everyElement(isTrue));
      await cubit.close();
    });

    test('progress aggregates across the batch', () async {
      picked = [
        PickedMedia(
          filename: 'a.png',
          source: MemoryUploadSource(Uint8List(10)),
        ),
        PickedMedia(
          filename: 'b.png',
          source: MemoryUploadSource(Uint8List(10)),
        ),
      ];
      driveProgress = (onProgress) {
        onProgress?.call(4, 10);
        onProgress?.call(10, 10);
      };
      final cubit = build();
      final uploading = <MediaUploadState>[];
      final sub = cubit.stream.listen((s) {
        if (s.status == MediaUploadStatus.uploading) uploading.add(s);
      });
      await cubit.pickAndUpload();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      // File A sweeps 0 → 10 of 20; file B picks up at 10 and closes the ring.
      expect(uploading.map((s) => s.sentBytes), [0, 4, 10, 10, 14, 20]);
      expect(uploading.every((s) => s.totalBytes == 20), isTrue);
      await cubit.close();
    });

    test('cancel skips the files not yet sent', () async {
      final a = _TrackingSource(10);
      final b = _TrackingSource(10);
      final c = _TrackingSource(10);
      final uploadStarted = Completer<void>();
      final held = Completer<String>();
      final sent = <String>[];
      late MediaUploadCubit cubit;
      cubit = MediaUploadCubit(
        pickMedia: () async => [
          PickedMedia(filename: 'a.png', source: a),
          PickedMedia(filename: 'b.png', source: b),
          PickedMedia(filename: 'c.png', source: c),
        ],
        cancelUpload: () => held.completeError(const PairingUploadCancelled()),
        upload: ({required filename, required source, onProgress}) {
          sent.add(filename);
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
      expect(sent, ['a.png'], reason: 'b and c were never started');
      expect(cubit.state.status, MediaUploadStatus.idle);
      expect(failures, isEmpty, reason: 'the user did this on purpose');
      expect(paths, isEmpty);
      // The skipped files still have to surrender their handles.
      expect([a.closed, b.closed, c.closed], everyElement(isTrue));
      await cubit.close();
    });
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
    picked = [PickedMedia(filename: 'huge.png', source: source)];
    final cubit = build();
    await cubit.pickAndUpload();
    await Future<void>.delayed(Duration.zero);
    expect(source.closed, isTrue);
    await cubit.close();
  });

  test('closes the source after a successful upload', () async {
    final source = _TrackingSource(10);
    picked = [PickedMedia(filename: 'photo.jpg', source: source)];
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
