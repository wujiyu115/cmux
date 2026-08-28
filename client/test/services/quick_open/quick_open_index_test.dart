import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/quick_open/quick_open_index.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
    for (final dir in [
      '/repo',
      '/repo/lib',
      '/repo/lib/src',
      '/repo/.git',
      '/repo/node_modules/pkg',
      '/repo/build',
    ]) {
      fs.ensureDir(dir);
    }
    for (final file in [
      '/repo/README.md',
      '/repo/lib/main.dart',
      '/repo/lib/src/terminal_session.dart',
      '/repo/.git/config',
      '/repo/node_modules/pkg/index.js',
      '/repo/build/app.exe',
      '/repo/.hidden.txt',
      '/repo/lib/.secret.dart',
    ]) {
      fs.files[file] = 'x';
    }
  });

  test('lists files, skipping ignored dirs and hidden entries', () async {
    final registry = QuickOpenIndexRegistry();
    final index = await registry.load(fs, '/repo');
    expect(
      index.files.map((e) => e.relativePath).toList(),
      allOf([
        contains('README.md'),
        contains('lib/main.dart'),
        contains('lib/src/terminal_session.dart'),
      ]),
    );
    for (final path in index.files.map((e) => e.relativePath)) {
      expect(path.startsWith('.'), isFalse);
      expect(path.contains('/.'), isFalse);
      expect(path.startsWith('node_modules/'), isFalse);
      expect(path.startsWith('build/'), isFalse);
    }
  });

  test('entry fields: absolute path, basename, relative path', () async {
    final registry = QuickOpenIndexRegistry();
    final index = await registry.load(fs, '/repo');
    final entry = index.files.firstWhere(
      (e) => e.relativePath == 'lib/main.dart',
    );
    expect(entry.path, '/repo/lib/main.dart');
    expect(entry.name, 'main.dart');
  });

  test('cap: index truncated beyond maxFiles', () async {
    for (var i = 0; i < 10; i++) {
      fs.files['/repo/file$i.txt'] = 'x';
    }
    final registry = QuickOpenIndexRegistry();
    final index = await registry.load(fs, '/repo', maxFiles: 5);
    expect(index.files.length, 5);
    expect(index.truncated, isTrue);
  });

  test('same (fs, root) shares one listing future', () async {
    var listings = 0;
    final registry = QuickOpenIndexRegistry(
      lister: (path) {
        listings++;
        return fs.listDirRecursive(path);
      },
    );
    final a = registry.load(fs, '/repo');
    final b = registry.load(fs, '/repo');
    await Future.wait([a, b]);
    expect(listings, 1);
  });

  test('cache hit returns immediately; background refresh replaces entry',
      () async {
    final registry = QuickOpenIndexRegistry();
    final first = await registry.load(fs, '/repo');
    expect(first.files.map((e) => e.name), contains('main.dart'));

    fs.files['/repo/new_file.md'] = 'x';
    final second = await registry.load(fs, '/repo');
    // Cache hit: stale view (no new_file yet)…
    expect(
      second.files.map((e) => e.name),
      isNot(contains('new_file.md')),
    );
    // …but a refresh was kicked; after it drains the next load sees the file.
    await registry.drainRefreshesForTest();
    final third = await registry.load(fs, '/repo');
    expect(third.files.map((e) => e.name), contains('new_file.md'));
  });

  test('different root loads separately', () async {
    fs.ensureDir('/other');
    fs.files['/other/x.txt'] = 'x';
    final registry = QuickOpenIndexRegistry();
    final repo = await registry.load(fs, '/repo');
    final other = await registry.load(fs, '/other');
    expect(repo.files.map((e) => e.relativePath), contains('README.md'));
    expect(other.files.map((e) => e.relativePath), ['x.txt']);
  });

  test('listing failure is not cached: next load retries', () async {
    var fail = true;
    final registry = QuickOpenIndexRegistry(
      lister: (path) {
        if (fail) throw StateError('boom');
        return fs.listDirRecursive(path);
      },
    );
    await expectLater(registry.load(fs, '/repo'), throwsStateError);
    fail = false;
    final index = await registry.load(fs, '/repo');
    expect(index.files, isNotEmpty);
  });
}
