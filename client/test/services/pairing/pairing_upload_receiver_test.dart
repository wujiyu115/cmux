import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/pairing_upload_receiver.dart';

void main() {
  late List<({String workspaceId, String cwd, String filename, int length})>
      written;
  late Object? sinkError;
  late String sinkPath;

  PairingUploadReceiver build({int maxBytes = 1024, int chunkSize = 4}) {
    return PairingUploadReceiver(
      maxBytes: maxBytes,
      chunkSize: chunkSize,
      sink:
          ({
            required String workspaceId,
            required String cwd,
            required String filename,
            required List<int> bytes,
          }) async {
            final error = sinkError;
            if (error != null) throw error;
            written.add((
              workspaceId: workspaceId,
              cwd: cwd,
              filename: filename,
              length: bytes.length,
            ));
            return sinkPath;
          },
    );
  }

  /// A successful begin for a 6-byte photo.jpg.
  UploadBeginResult beginPhoto(PairingUploadReceiver receiver, {int size = 6}) =>
      receiver.begin(
        workspaceId: 'ws-1',
        cwd: '/home/dev/app',
        filename: 'photo.jpg',
        size: size,
      );

  setUp(() {
    written = [];
    sinkError = null;
    sinkPath = '/home/dev/app/photo.jpg';
  });

  group('begin', () {
    test('returns a transfer id and the host-chosen chunk size', () {
      final receiver = build(chunkSize: 4);
      final result = beginPhoto(receiver);
      expect(result.isOk, isTrue);
      expect(result.chunkSize, 4, reason: 'the host dictates the chunk size');
      expect(result.transferId, greaterThan(0));
    });

    test('hands out distinct transfer ids', () {
      final receiver = build();
      expect(
        beginPhoto(receiver).transferId,
        isNot(beginPhoto(receiver).transferId),
      );
    });

    test('rejects a declared size over the cap', () {
      final result = build(maxBytes: 10).begin(
        workspaceId: 'ws-1',
        cwd: '/c',
        filename: 'a.png',
        size: 11,
      );
      expect(result.isOk, isFalse);
      expect(result.code, 'too_large');
    });

    test('accepts a declared size exactly at the cap', () {
      final result = build(maxBytes: 10).begin(
        workspaceId: 'ws-1',
        cwd: '/c',
        filename: 'a.png',
        size: 10,
      );
      expect(result.isOk, isTrue);
    });

    test('rejects a negative declared size', () {
      // Malformed request; the same range check covers it, which is why the
      // code name reads as "out of range" rather than literally "too big".
      final result = build().begin(
        workspaceId: 'ws-1',
        cwd: '/c',
        filename: 'a.png',
        size: -1,
      );
      expect(result.code, 'too_large');
    });

    test('accepts every allowlisted extension, in any case', () {
      final receiver = build();
      for (final ext in uploadImageExtensions) {
        for (final name in ['a.$ext', 'a.${ext.toUpperCase()}']) {
          final result = receiver.begin(
            workspaceId: 'ws-1',
            cwd: '/c',
            filename: name,
            size: 1,
          );
          expect(result.isOk, isTrue, reason: name);
        }
      }
    });

    test('allowlists heic', () {
      // iPhones shoot HEIC by default and image_picker's conversion is not
      // reliable across versions; omitting it fails randomly on iOS.
      expect(uploadImageExtensions, contains('heic'));
    });

    test('rejects a non-image extension', () {
      for (final name in ['a.sh', 'a.txt', 'a.dart', 'a.png.sh']) {
        final result = build().begin(
          workspaceId: 'ws-1',
          cwd: '/c',
          filename: name,
          size: 1,
        );
        expect(result.code, 'unsupported_type', reason: name);
      }
    });

    test('rejects a filename with no extension', () {
      expect(
        build()
            .begin(workspaceId: 'ws-1', cwd: '/c', filename: 'photo', size: 1)
            .code,
        'unsupported_type',
      );
    });

    test('rejects any filename carrying a path component', () {
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
        final result = build().begin(
          workspaceId: 'ws-1',
          cwd: '/c',
          filename: name,
          size: 1,
        );
        expect(result.code, 'bad_filename', reason: 'name: $name');
      }
    });

    test('rejects a filename containing a null byte', () {
      // A NUL truncates the path at the C layer, so 'photo\x00.sh' could pass an
      // extension check and land as 'photo'.
      expect(
        build()
            .begin(
              workspaceId: 'ws-1',
              cwd: '/c',
              filename: 'photo\x00.jpg',
              size: 1,
            )
            .code,
        'bad_filename',
      );
    });
  });

  group('chunk', () {
    test('accumulates in order and reports the running total', () {
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver).transferId;
      expect(receiver.chunk(id, 0, const [1, 2, 3, 4]).received, 4);
      expect(receiver.chunk(id, 1, const [5, 6]).received, 6);
    });

    test('rejects an unknown transfer id', () {
      expect(build().chunk(999, 0, const [1]).code, 'unknown_transfer');
    });

    test('abandons the transfer on a gap in the chunk index', () {
      // WebSocket preserves order, so a gap means something is wrong. Silently
      // writing a file with a hole in it would be worse than failing.
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      expect(receiver.chunk(id, 2, const [5, 6]).code, 'write_failed');
      expect(
        receiver.chunk(id, 1, const [5, 6]).code,
        'unknown_transfer',
        reason: 'the transfer is gone, not merely erroring',
      );
    });

    test('abandons the transfer when the bytes exceed the declared size', () {
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver, size: 6).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      expect(receiver.chunk(id, 1, const [5, 6, 7, 8]).code, 'too_large');
      expect(receiver.chunk(id, 2, const [9]).code, 'unknown_transfer');
    });
  });

  group('commit', () {
    test('hands the assembled bytes to the sink and returns its path', () async {
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      receiver.chunk(id, 1, const [5, 6]);

      final result = await receiver.commit(id);

      expect(result.isOk, isTrue);
      expect(result.path, '/home/dev/app/photo.jpg');
      expect(written.single.workspaceId, 'ws-1');
      expect(written.single.cwd, '/home/dev/app');
      expect(written.single.filename, 'photo.jpg');
      expect(written.single.length, 6);
    });

    test('rejects an unknown transfer id', () async {
      expect((await build().commit(999)).code, 'unknown_transfer');
    });

    test('rejects a short transfer without calling the sink', () async {
      // Truncation is what the size check exists to catch; half a file on disk
      // is worse than no file.
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver, size: 6).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      expect((await receiver.commit(id)).code, 'write_failed');
      expect(written, isEmpty);
    });

    test('reports write_failed when the sink throws', () async {
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver, size: 2).transferId;
      receiver.chunk(id, 0, const [1, 2]);
      sinkError = StateError('disk full');
      expect((await receiver.commit(id)).code, 'write_failed');
    });

    test('drops the transfer after a successful commit', () async {
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver, size: 2).transferId;
      receiver.chunk(id, 0, const [1, 2]);
      await receiver.commit(id);
      expect((await receiver.commit(id)).code, 'unknown_transfer');
    });
  });

  group('abandon', () {
    test('abandon drops one transfer', () {
      final receiver = build();
      final id = beginPhoto(receiver).transferId;
      receiver.abandon(id);
      expect(receiver.chunk(id, 0, const [1]).code, 'unknown_transfer');
    });

    test('abandon of an unknown id is harmless', () {
      expect(() => build().abandon(999), returnsNormally);
    });

    test('abandonAll drops every in-flight transfer', () {
      // The connection closing must release the bytes of every unfinished
      // transfer, or a phone that reconnects repeatedly feeds the desktop's
      // memory.
      final receiver = build();
      final a = beginPhoto(receiver).transferId;
      final b = beginPhoto(receiver).transferId;
      receiver.abandonAll();
      expect(receiver.chunk(a, 0, const [1]).code, 'unknown_transfer');
      expect(receiver.chunk(b, 0, const [1]).code, 'unknown_transfer');
    });
  });
}
