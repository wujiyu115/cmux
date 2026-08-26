import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/filesystem_upload_target.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() => fs = InMemoryFilesystem());

  Future<FilesystemUploadTarget> open({
    String directory = '/home/dev/app',
    String filename = 'photo.jpg',
  }) => openFilesystemUploadTarget(
    filesystem: fs,
    directory: directory,
    filename: filename,
  );

  group('uploadPartName', () {
    test('is hidden, keeps the stem, and drops the real extension', () {
      final name = uploadPartName('holiday.mp4');
      expect(name, startsWith('.holiday.'), reason: 'hidden, stem preserved');
      expect(name, endsWith(uploadPartSuffix));
      expect(
        name,
        isNot(contains('.mp4')),
        reason: 'a half-written .mp4 would invite thumbnailers and indexers',
      );
    });

    test('two calls for the same name do not collide', () {
      expect(uploadPartName('photo.jpg'), isNot(uploadPartName('photo.jpg')));
    });

    test('handles a name with no extension', () {
      expect(uploadPartName('Makefile'), startsWith('.Makefile.'));
    });
  });

  group('open', () {
    test('creates the directory and an empty part-file inside it', () async {
      final target = await open();

      expect(fs.directories, contains('/home/dev/app'));
      expect(fs.byteFiles[target.partPath], isEmpty);
      expect(
        fs.pathContext.dirname(target.partPath),
        '/home/dev/app',
        reason:
            'the part-file must share the destination filesystem, or the '
            'rename at commit crosses a mount point and fails',
      );
    });

    test('two concurrent opens of the same name get separate part-files',
        () async {
      final a = await open();
      final b = await open();
      expect(a.partPath, isNot(b.partPath));
    });

    test('advertises a flush size', () async {
      // An InMemoryFilesystem is not a LocalFilesystem, so it lands on the
      // conservative "one append is expensive" figure.
      expect((await open()).preferredFlushBytes, greaterThan(0));
    });
  });

  group('append + commit', () {
    test('renames the accumulated bytes onto the requested name', () async {
      final target = await open();
      await target.append(const [1, 2, 3]);
      await target.append(const [4, 5]);

      final path = await target.commit();

      expect(path, '/home/dev/app/photo.jpg');
      expect(fs.byteFiles[path], const [1, 2, 3, 4, 5]);
      expect(
        fs.byteFiles.containsKey(target.partPath),
        isFalse,
        reason: 'the part-file is gone, not copied',
      );
    });

    test('commits an empty file when nothing was appended', () async {
      final target = await open();
      expect(fs.byteFiles[await target.commit()], isEmpty);
    });

    test('never overwrites an existing file', () async {
      // This is also the symlink defence: a planted `photo.jpg` pointing at
      // /etc/passwd makes us land on `photo-1.jpg` instead of following it.
      fs.byteFiles['/home/dev/app/photo.jpg'] = const [9, 9, 9];
      final target = await open();
      await target.append(const [1]);

      expect(await target.commit(), '/home/dev/app/photo-1.jpg');
      expect(
        fs.byteFiles['/home/dev/app/photo.jpg'],
        const [9, 9, 9],
        reason: 'the pre-existing file is untouched',
      );
    });

    test('suffixes past several taken names', () async {
      fs.byteFiles['/home/dev/app/photo.jpg'] = const [1];
      fs.byteFiles['/home/dev/app/photo-1.jpg'] = const [1];
      expect(await (await open()).commit(), '/home/dev/app/photo-2.jpg');
    });

    test('joins with the filesystem pathContext, not a hardcoded separator',
        () async {
      // The destination may be a WSL distro or a remote POSIX host reached from
      // Windows, so all path arithmetic goes through the backend's own context.
      final target = await open(directory: '/srv/data');
      expect(await target.commit(), '/srv/data/photo.jpg');
    });
  });

  group('abort', () {
    test('removes the part-file and nothing else', () async {
      fs.byteFiles['/home/dev/app/photo.jpg'] = const [9];
      final target = await open();
      await target.append(const [1, 2]);

      await target.abort();

      expect(fs.byteFiles.containsKey(target.partPath), isFalse);
      expect(fs.byteFiles['/home/dev/app/photo.jpg'], const [9]);
      expect(fs.directories, contains('/home/dev/app'));
    });

    test('is harmless twice, and after the part-file is already gone', () async {
      // Abort runs on paths that are already failing, so it must never throw and
      // mask the original error.
      final target = await open();
      await target.abort();
      await expectLater(target.abort(), completes);
    });
  });
}
