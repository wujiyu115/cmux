import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory root;
  late LocalFilesystem fs;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('teampilot_local_fs_');
    fs = LocalFilesystem(pathContext: p.context);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('rename moves a file', () async {
    final from = p.join(root.path, 'a.txt');
    final to = p.join(root.path, 'b.txt');
    await fs.writeString(from, 'hello');

    await fs.rename(from, to);

    expect(await File(from).exists(), isFalse);
    expect(await fs.readString(to), 'hello');
  });

  test('rename moves a directory tree', () async {
    final from = p.join(root.path, 'repo');
    final to = p.join(root.path, 'repo.bak');
    await fs.ensureDir(p.join(from, 'files', 'skill-a'));
    await fs.writeString(p.join(from, 'meta.json'), '{}');
    await fs.writeBytes(p.join(from, 'files', 'skill-a', 'SKILL.md'), [
      1,
      2,
      3,
    ]);

    await fs.rename(from, to);

    expect(await Directory(from).exists(), isFalse);
    expect((await fs.stat(p.join(to, 'meta.json'))).isFile, isTrue);
    expect(
      (await fs.stat(p.join(to, 'files', 'skill-a', 'SKILL.md'))).isFile,
      isTrue,
    );
  });

  test('ensureDir is a no-op when path is an existing symlink', () async {
    final target = p.join(root.path, 'target');
    final link = p.join(root.path, 'link');
    await fs.ensureDir(target);
    await Link(link).create(target);

    await expectLater(fs.ensureDir(link), completes);
    expect(Link(link).existsSync(), isTrue);
  });

  test(
    'listDir reports a symlink/junction to a directory as a directory',
    () async {
      final target = p.join(root.path, 'installed', 'brainstorming');
      await fs.ensureDir(target);
      final container = p.join(root.path, 'skills');
      await fs.ensureDir(container);
      await fs.createSymlink(
        target: target,
        linkPath: p.join(container, 'brainstorming'),
      );

      final entries = await fs.listDir(container);

      expect(entries, hasLength(1));
      expect(entries.single.name, 'brainstorming');
      expect(entries.single.isDirectory, isTrue);
    },
  );

  test('rename replaces an existing destination directory', () async {
    final from = p.join(root.path, 'next');
    final to = p.join(root.path, 'current');
    await fs.ensureDir(p.join(to, 'old'));
    await fs.writeString(p.join(to, 'old', 'stale.txt'), 'stale');
    await fs.writeString(p.join(from, 'fresh.txt'), 'fresh');

    await fs.rename(from, to);

    expect(await Directory(from).exists(), isFalse);
    expect(await fs.readString(p.join(to, 'fresh.txt')), 'fresh');
    expect(await File(p.join(to, 'old', 'stale.txt')).exists(), isFalse);
  });

  group('FsSymlinkLister', () {
    // Directory targets become junctions on Windows (no privilege needed);
    // file/dangling links may still fail without Developer Mode → skip.
    Future<void> createLink({
      required String target,
      required String linkPath,
    }) async {
      try {
        await fs.createSymlink(target: target, linkPath: linkPath);
      } on Object {
        markTestSkipped('symlink creation unavailable on this host');
      }
    }

    test('listSymlinkedDirs reports directory links by absolute path',
        () async {
      final docs = p.join(root.path, 'external', 'docs');
      await fs.ensureDir(docs);
      await fs.writeString(p.join(docs, 'guide.md'), 'x');
      await fs.ensureDir(p.join(root.path, 'repo'));
      await createLink(
        target: docs,
        linkPath: p.join(root.path, 'repo', 'linked'),
      );

      final links = await fs.listSymlinkedDirs(root.path);

      expect(links, [p.join(root.path, 'repo', 'linked')]);
    });

    test('listSymlinkedDirs skips file links and dangling links', () async {
      await fs.ensureDir(p.join(root.path, 'repo'));
      await fs.writeString(p.join(root.path, 'repo', 'file.txt'), 'x');
      await createLink(
        target: p.join(root.path, 'repo', 'file.txt'),
        linkPath: p.join(root.path, 'repo', 'file-link'),
      );
      await createLink(
        target: p.join(root.path, 'nowhere'),
        linkPath: p.join(root.path, 'repo', 'dangling'),
      );

      expect(await fs.listSymlinkedDirs(root.path), isEmpty);
    });

    test('listDirRecursiveFollowLinks lists the linked tree under the link',
        () async {
      final docs = p.join(root.path, 'external', 'docs');
      await fs.ensureDir(p.join(docs, 'sub'));
      await fs.writeString(p.join(docs, 'guide.md'), 'x');
      await fs.writeString(p.join(docs, 'sub', 'deep.dart'), 'x');
      await fs.ensureDir(p.join(root.path, 'repo'));
      await createLink(
        target: docs,
        linkPath: p.join(root.path, 'repo', 'linked'),
      );

      final entries = await fs.listDirRecursiveFollowLinks(
        p.join(root.path, 'repo', 'linked'),
      );

      final byName = {for (final e in entries) e.name: e};
      expect(byName['guide.md']!.isDirectory, isFalse);
      expect(byName[p.join('sub', 'deep.dart')]!.isDirectory, isFalse);
      expect(byName['sub']!.isDirectory, isTrue);
    });

    test('listDirRecursiveFollowLinks terminates on a link cycle', () async {
      final repo = p.join(root.path, 'repo');
      await fs.ensureDir(p.join(repo, 'sub'));
      await fs.writeString(p.join(repo, 'sub', 'file.txt'), 'x');
      await createLink(target: repo, linkPath: p.join(repo, 'loop'));

      final entries = await fs.listDirRecursiveFollowLinks(repo);

      // The SDK detects the cycle: the walk stays bounded and the real file
      // is still reported.
      expect(entries, hasLength(lessThan(10)));
      expect(entries.map((e) => e.name), contains(p.join('sub', 'file.txt')));
      // The junction is followed at most one level before the cycle is cut —
      // no path nests deeper than two loop segments.
      for (final e in entries) {
        final loopSegments = e.name
            .split(p.separator)
            .where((segment) => segment == 'loop')
            .length;
        expect(loopSegments, lessThan(3), reason: e.name);
      }
    });
  });
}
