import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/pairing_upload_receiver.dart';
import 'package:teampilot/services/pairing/upload_limits.dart';

import '../../support/pairing_upload_doubles.dart';

void main() {
  late FakeUploadTarget target;
  late FakeUploadOpener opener;
  late List<({int transferId, int received})> acks;

  PairingUploadReceiver build({
    PairingUploadCaps caps = const PairingUploadCaps(
      imageMaxBytes: 1024,
      videoMaxBytes: 1024,
    ),
    int chunkSize = 4,
    int maxConcurrentTransfers = 4,
  }) {
    return PairingUploadReceiver(
      openTarget: opener.call,
      onAck: (transferId, received) =>
          acks.add((transferId: transferId, received: received)),
      caps: caps,
      chunkSize: chunkSize,
      maxConcurrentTransfers: maxConcurrentTransfers,
    );
  }

  /// Small, unequal caps so a test can tell which one was applied.
  PairingUploadReceiver tightCaps() => build(
    caps: const PairingUploadCaps(imageMaxBytes: 10, videoMaxBytes: 20),
  );

  /// A successful begin for a 6-byte photo.jpg.
  Future<UploadBeginResult> beginPhoto(
    PairingUploadReceiver receiver, {
    int size = 6,
  }) => receiver.begin(
    workspaceId: 'ws-1',
    cwd: '/home/dev/app',
    filename: 'photo.jpg',
    size: size,
  );

  /// Lets every queued flush and its ack settle.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    // One shared target so a test can read what landed without fishing it out of
    // the opener; a flush threshold above every payload here keeps the default
    // path "buffer and ack immediately", and tests that care lower it.
    target = FakeUploadTarget(
      path: '/home/dev/app/photo.jpg',
      preferredFlushBytes: 1024,
    );
    opener = FakeUploadOpener(target: target);
    acks = [];
  });

  group('begin', () {
    test('returns a transfer id and the host-chosen chunk size', () async {
      final receiver = build(chunkSize: 4);
      final result = await beginPhoto(receiver);
      expect(result.isOk, isTrue);
      expect(result.chunkSize, 4, reason: 'the host dictates the chunk size');
      expect(result.transferId, greaterThan(0));
    });

    test('opens the target with the pane workspaceId, cwd and filename', () async {
      await beginPhoto(build());
      expect(opener.opens.single.workspaceId, 'ws-1');
      expect(opener.opens.single.cwd, '/home/dev/app');
      expect(opener.opens.single.filename, 'photo.jpg');
    });

    test('hands out distinct transfer ids', () async {
      final receiver = build();
      expect(
        (await beginPhoto(receiver)).transferId,
        isNot((await beginPhoto(receiver)).transferId),
      );
    });

    test('replies no_target when the target cannot be opened', () async {
      // Resolving the pane's machine and creating the part-file happens here, so
      // a dead SSH host or an unwritable cwd is known before a single byte
      // crosses the network.
      opener.openError = StateError('no such directory');
      final receiver = build();
      expect((await beginPhoto(receiver)).code, 'no_target');
      // And the id sequence stays ungapped: the next successful begin gets 1.
      opener.openError = null;
      expect((await beginPhoto(receiver)).transferId, 1);
    });

    test('rejects a declared size over the cap', () async {
      final result = await tightCaps().begin(
        workspaceId: 'ws-1',
        cwd: '/c',
        filename: 'a.png',
        size: 11,
      );
      expect(result.isOk, isFalse);
      expect(result.code, 'too_large');
    });

    test('accepts a declared size exactly at the cap', () async {
      final result = await tightCaps().begin(
        workspaceId: 'ws-1',
        cwd: '/c',
        filename: 'a.png',
        size: 10,
      );
      expect(result.isOk, isTrue);
    });

    test('caps images and videos separately', () async {
      // A video budget an image can borrow would defeat the point of having two
      // numbers, so each extension must be held to its own cap.
      final receiver = tightCaps();
      Future<UploadBeginResult> at(String filename, int size) =>
          receiver.begin(
            workspaceId: 'ws-1',
            cwd: '/c',
            filename: filename,
            size: size,
          );
      expect((await at('a.png', 11)).code, 'too_large');
      expect((await at('a.mp4', 11)).isOk, isTrue);
      expect((await at('a.mp4', 20)).isOk, isTrue);
      expect((await at('a.mp4', 21)).code, 'too_large');
    });

    test('the shipped caps are 25 MiB for images and 512 MiB for videos', () {
      // Pins the product decision: a phone-shot minute of 4K HEVC is ~170 MiB,
      // so an image-sized cap would make video upload useless.
      const caps = PairingUploadCaps();
      expect(caps.imageMaxBytes, 25 * 1024 * 1024);
      expect(caps.videoMaxBytes, 512 * 1024 * 1024);
    });

    test('rejects a negative declared size', () async {
      // Malformed request; the same range check covers it, which is why the
      // code name reads as "out of range" rather than literally "too big".
      final result = await build().begin(
        workspaceId: 'ws-1',
        cwd: '/c',
        filename: 'a.png',
        size: -1,
      );
      expect(result.code, 'too_large');
    });

    test('refuses more than maxConcurrentTransfers at once', () async {
      // Each live transfer owns a part-file in the user's directory, so an
      // unbounded table means unbounded half-written files.
      final receiver = build(maxConcurrentTransfers: 2);
      expect((await beginPhoto(receiver)).isOk, isTrue);
      expect((await beginPhoto(receiver)).isOk, isTrue);
      expect((await beginPhoto(receiver)).code, 'too_many');
    });

    test('accepts every allowlisted extension, in any case', () async {
      final receiver = build();
      for (final ext in {...uploadImageExtensions, ...uploadVideoExtensions}) {
        for (final name in ['a.$ext', 'a.${ext.toUpperCase()}']) {
          final result = await receiver.begin(
            workspaceId: 'ws-1',
            cwd: '/c',
            filename: name,
            size: 1,
          );
          expect(result.isOk, isTrue, reason: name);
          await receiver.abandon(result.transferId);
        }
      }
    });

    test('allowlists heic', () {
      // iPhones shoot HEIC by default and image_picker's conversion is not
      // reliable across versions; omitting it fails randomly on iOS.
      expect(uploadImageExtensions, contains('heic'));
    });

    test('allowlists mov, which is where an iPhone puts HEVC', () {
      // HEVC / H.265 is a codec, not a container: the allowlist can only speak
      // about containers, and an iPhone's HEVC clip arrives as .mov.
      expect(uploadVideoExtensions, containsAll(const ['mp4', 'mov']));
    });

    test('rejects an unsupported extension', () async {
      for (final name in [
        'a.sh',
        'a.txt',
        'a.dart',
        'a.png.sh',
        'a.mp4.sh',
        // Raw elementary streams: a codec name, not a container.
        'a.hevc',
        'a.h265',
      ]) {
        final result = await build().begin(
          workspaceId: 'ws-1',
          cwd: '/c',
          filename: name,
          size: 1,
        );
        expect(result.code, 'unsupported_type', reason: name);
      }
    });

    test('rejects a filename with no extension', () async {
      expect(
        (await build().begin(
          workspaceId: 'ws-1',
          cwd: '/c',
          filename: 'photo',
          size: 1,
        )).code,
        'unsupported_type',
      );
    });

    test('rejects any filename carrying a path component', () async {
      // Rejected rather than basename'd: a phone sending a path is buggy or
      // hostile, and silently rewriting it hides that. Backslashes matter too —
      // a posix basename would not strip the Windows-style form.
      for (final name in [
        '../photo.jpg',
        '/etc/photo.jpg',
        'a/b.jpg',
        r'..\..\photo.jpg',
        r'a\b.jpg',
        '.',
        '..',
        '',
      ]) {
        final result = await build().begin(
          workspaceId: 'ws-1',
          cwd: '/c',
          filename: name,
          size: 1,
        );
        expect(result.code, 'bad_filename', reason: 'name: $name');
      }
      expect(opener.opens, isEmpty, reason: 'nothing was opened on disk');
    });

    test('rejects a filename containing a null byte', () async {
      // A NUL truncates the path at the C layer, so 'photo\x00.sh' could pass an
      // extension check and land as 'photo'.
      expect(
        (await build().begin(
          workspaceId: 'ws-1',
          cwd: '/c',
          filename: 'photo\x00.jpg',
          size: 1,
        )).code,
        'bad_filename',
      );
    });
  });

  group('chunk', () {
    test('acks the running total without writing while under the threshold',
        () async {
      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver)).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      receiver.chunk(id, 1, const [5, 6]);
      await settle();

      expect(acks.map((a) => a.received), [4, 6]);
      expect(acks.every((a) => a.transferId == id), isTrue);
      expect(target.appends, isEmpty, reason: 'buffered, not written');
    });

    test('flushes once the buffer reaches the threshold', () async {
      target.preferredFlushBytes = 8;
      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver, size: 12)).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      receiver.chunk(id, 1, const [5, 6, 7, 8]);
      await settle();

      expect(target.appends.single, const [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('withholds the ack of a flushing chunk until the write lands', () async {
      // The whole backpressure invariant: the phone's credit window only reopens
      // once the bytes are actually on disk, which is what keeps host memory
      // bounded no matter how slow a WSL or SFTP destination is.
      target.preferredFlushBytes = 8;
      final gate = Completer<void>();
      target.holdAppend = gate.future;

      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver, size: 8)).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      await settle();
      expect(acks.map((a) => a.received), [4], reason: 'sub-threshold: instant');

      receiver.chunk(id, 1, const [5, 6, 7, 8]);
      await settle();
      expect(
        acks.map((a) => a.received),
        [4],
        reason: 'the flushing chunk is not acked while the write is in flight',
      );

      gate.complete();
      await settle();
      expect(acks.map((a) => a.received), [4, 8]);
    });

    test('ignores an unknown transfer id', () async {
      final receiver = build();
      receiver.chunk(999, 0, const [1]);
      await settle();
      expect(acks, isEmpty);
      expect(target.appends, isEmpty);
    });

    test('abandons the transfer on a gap in the chunk index', () async {
      // WebSocket preserves order, so a gap means something is wrong. Silently
      // writing a file with a hole in it would be worse than failing.
      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver)).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      receiver.chunk(id, 2, const [5, 6]);
      await settle();

      expect(acks.map((a) => a.received), [4], reason: 'the gap is not acked');
      expect(target.abortCount, 1, reason: 'the part-file is deleted');
      expect((await receiver.commit(id)).code, 'unknown_transfer');
    });

    test('abandons the transfer when the bytes exceed the declared size',
        () async {
      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver, size: 6)).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      receiver.chunk(id, 1, const [5, 6, 7, 8]);
      await settle();

      expect(acks.map((a) => a.received), [4]);
      expect(target.abortCount, 1);
      expect((await receiver.commit(id)).code, 'unknown_transfer');
    });

    test('a failed flush stops acking, abandons on the next chunk, and fails '
        'the commit', () async {
      // A write error at byte N cannot be attributed to the chunk that caused
      // it — that is inherent to buffering — so it surfaces on whatever comes
      // next.
      target.preferredFlushBytes = 4;
      target.appendError = StateError('disk full');
      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver, size: 12)).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      await settle();
      expect(acks, isEmpty, reason: 'a failed write is never acked');

      receiver.chunk(id, 1, const [5, 6, 7, 8]);
      await settle();
      expect(target.abortCount, 1);
      expect((await receiver.commit(id)).code, 'unknown_transfer');
    });
  });

  group('commit', () {
    test('appends the buffered tail before committing the target', () async {
      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver)).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      receiver.chunk(id, 1, const [5, 6]);

      final result = await receiver.commit(id);

      expect(result.isOk, isTrue);
      expect(result.path, '/home/dev/app/photo.jpg');
      expect(target.calls, ['append', 'commit'], reason: 'tail before commit');
      expect(target.appendedBytes, 6);
    });

    test('commits a zero-byte transfer without appending', () async {
      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver, size: 0)).transferId;

      final result = await receiver.commit(id);

      expect(result.path, '/home/dev/app/photo.jpg');
      expect(target.calls, ['commit']);
    });

    test('does not re-append bytes already flushed', () async {
      target.preferredFlushBytes = 4;
      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver, size: 6)).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      await settle();
      receiver.chunk(id, 1, const [5, 6]);

      await receiver.commit(id);

      expect(target.appends, [
        const [1, 2, 3, 4],
        const [5, 6],
      ]);
      expect(target.appendedBytes, 6);
    });

    test('rejects an unknown transfer id', () async {
      expect((await build().commit(999)).code, 'unknown_transfer');
    });

    test('rejects a short transfer, aborts it, and never commits', () async {
      // Truncation is what the size check exists to catch; half a file on disk
      // is worse than no file.
      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver, size: 6)).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      expect((await receiver.commit(id)).code, 'write_failed');
      expect(target.commitCount, 0);
      expect(target.abortCount, 1);
    });

    test('reports write_failed and aborts when the target commit throws',
        () async {
      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver, size: 2)).transferId;
      receiver.chunk(id, 0, const [1, 2]);
      target.commitError = StateError('disk full');
      expect((await receiver.commit(id)).code, 'write_failed');
      expect(target.abortCount, 1, reason: 'no part-file left behind');
    });

    test('drops the transfer after a successful commit', () async {
      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver, size: 2)).transferId;
      receiver.chunk(id, 0, const [1, 2]);
      await receiver.commit(id);
      expect((await receiver.commit(id)).code, 'unknown_transfer');
      expect(target.commitCount, 1);
    });
  });

  group('abandon', () {
    test('drops one transfer and deletes its part-file', () async {
      final receiver = build();
      final id = (await beginPhoto(receiver)).transferId;
      await receiver.abandon(id);
      expect(target.abortCount, 1);
      receiver.chunk(id, 0, const [1]);
      await settle();
      expect(acks, isEmpty);
    });

    test('abandon of an unknown id is harmless', () async {
      await expectLater(build().abandon(999), completes);
      expect(target.abortCount, 0);
    });

    test('aborts only after an in-flight append finishes', () async {
      // Deleting the part-file while an appendBytes is open would just recreate
      // it, so the abort has to queue behind the write on the transfer's lock.
      target.preferredFlushBytes = 4;
      final gate = Completer<void>();
      target.holdAppend = gate.future;

      final receiver = build(chunkSize: 4);
      final id = (await beginPhoto(receiver, size: 8)).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      await settle();

      final abandoned = receiver.abandon(id);
      await settle();
      expect(target.abortCount, 0, reason: 'still waiting on the append');

      gate.complete();
      await abandoned;
      expect(target.abortCount, 1);
      expect(target.calls, ['append', 'abort']);
    });

    test('abandonAll aborts every in-flight transfer', () async {
      // A connection closing mid-upload must not leave a 300 MB `.tp-upload`
      // behind in the user's working directory.
      opener.target = null; // one target per transfer, so both can be checked
      final receiver = build();
      await beginPhoto(receiver);
      await beginPhoto(receiver);
      await receiver.abandonAll();
      expect(opener.handedOut.map((t) => t.abortCount), [1, 1]);
    });
  });
}
