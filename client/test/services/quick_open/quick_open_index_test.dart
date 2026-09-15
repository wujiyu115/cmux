import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/workspace_index_dirs.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/quick_open/quick_open_index.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeGitRunner implements GitCommandRunner {
  _FakeGitRunner({this.result, this.error});

  final GitCommandResult? result;
  final Object? error;
  final List<(String, List<String>)> calls = [];

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args) async {
    calls.add((dir, args));
    if (error != null) throw error!;
    return result!;
  }
}

/// Minimal [Filesystem] without [FsSymlinkLister]: the registry must fall
/// back to the plain non-following listing for such backends.
class _PlainFilesystem implements Filesystem {
  final files = <String, String>{};
  final dirs = <String>{};

  @override
  p.Context get pathContext => p.Context(style: p.Style.posix);

  @override
  Future<FsStat> stat(String path) async {
    if (files.containsKey(path)) {
      return FsStat(kind: FsEntityKind.file, size: files[path]!.length);
    }
    if (dirs.contains(path)) return const FsStat(kind: FsEntityKind.directory);
    return const FsStat(kind: FsEntityKind.notFound);
  }

  @override
  Future<void> ensureDir(String path) async => dirs.add(path);

  @override
  Future<void> removeRecursive(String path) async {}

  @override
  Future<void> rename(String from, String to) async {}

  @override
  Future<String?> readString(String path) async => files[path];

  @override
  Future<List<int>?> readBytes(String path) async =>
      files[path]?.codeUnits;

  @override
  Future<void> writeString(String path, String content) async =>
      files[path] = content;

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {}

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) async {
    final all = files[path]?.codeUnits;
    if (all == null) return null;
    final end = (offset + length).clamp(0, all.length);
    return all.sublist(offset.clamp(0, all.length), end);
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {}

  @override
  Future<void> atomicWrite(String path, String content) async {}

  @override
  Future<List<FsDirEntry>> listDir(String path) async => [
    for (final key in {...files.keys, ...dirs})
      if (pathContext.dirname(key) == path)
        FsDirEntry(
          name: pathContext.basename(key),
          isDirectory: dirs.contains(key),
        ),
  ];

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async => false;

  @override
  Future<String?> readSymlinkTarget(String linkPath) async => null;

  @override
  Future<String?> resolveSymlink(String path) async => path;

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {}

  @override
  Future<void> copyFile(String source, String destination) async {}

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) async => [
    for (final key in files.keys)
      if (key == path || pathContext.isWithin(path, key))
        FsDirEntry(
          name: pathContext.relative(key, from: path),
          isDirectory: false,
        ),
  ];

  @override
  Future<String> createTempDir({String? prefix, String? parent}) async =>
      '/tmp/x';

  @override
  Future<void> appendString(String path, String content) async {}
}

/// Counts symlink scans so tests can observe when [_scanSymlinkedDirs] runs
/// relative to the (possibly gated) base listing.
class _CountingSymlinkFs extends InMemoryFilesystem {
  int symlinkScans = 0;

  @override
  Future<List<String>> listSymlinkedDirs(String root) {
    symlinkScans++;
    return super.listSymlinkedDirs(root);
  }
}

class _FailingSymlinkScanFs extends InMemoryFilesystem {
  @override
  Future<List<String>> listSymlinkedDirs(String root) async {
    throw StateError('find failed');
  }
}

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

  test('entry lowercase cache: lowerName and normalized lowerRelativePath', () {
    final entry = QuickOpenFileEntry(
      path: r'C:\repo\Docs\README.MD',
      name: 'README.MD',
      relativePath: r'Docs\README.MD',
    );
    expect(entry.lowerName, 'readme.md');
    expect(entry.lowerRelativePath, 'docs/readme.md');
    // Originals are untouched.
    expect(entry.name, 'README.MD');
    expect(entry.relativePath, r'Docs\README.MD');
  });

  test('default maxFiles is 200000', () {
    expect(QuickOpenIndexRegistry().maxFiles, 200000);
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

  test(
    'cache hit returns immediately; background refresh replaces entry',
    () async {
      final registry = QuickOpenIndexRegistry();
      final first = await registry.load(fs, '/repo');
      expect(first.files.map((e) => e.name), contains('main.dart'));

      fs.files['/repo/new_file.md'] = 'x';
      final second = await registry.load(fs, '/repo');
      // Cache hit: stale view (no new_file yet)…
      expect(second.files.map((e) => e.name), isNot(contains('new_file.md')));
      // …but a refresh was kicked; after it drains the next load sees the file.
      await registry.drainRefreshesForTest();
      final third = await registry.load(fs, '/repo');
      expect(third.files.map((e) => e.name), contains('new_file.md'));
    },
  );

  test('latestIndex waits for the in-flight refresh, then serves it', () async {
    final registry = QuickOpenIndexRegistry();
    await registry.load(fs, '/repo');
    fs.files['/repo/new_file.md'] = 'x';

    final stale = await registry.load(fs, '/repo');
    expect(stale.files.map((e) => e.name), isNot(contains('new_file.md')));

    final latest = await registry.latestIndex(fs, '/repo');
    expect(latest!.files.map((e) => e.name), contains('new_file.md'));
  });

  test('latestIndex is null for a root with no cache entry', () async {
    final registry = QuickOpenIndexRegistry();
    expect(await registry.latestIndex(fs, '/repo'), isNull);
  });

  test(
    'latestIndex serves the cold listing itself while it is in flight',
    () async {
      final registry = QuickOpenIndexRegistry();
      final cold = registry.load(fs, '/repo');
      final latest = await registry.latestIndex(fs, '/repo');
      expect(latest, isNotNull);
      expect(await cold, same(latest));
    },
  );

  test('a second load while a refresh is in flight reuses it', () async {
    var listings = 0;
    final gate = Completer<void>();
    final registry = QuickOpenIndexRegistry(
      lister: (path) {
        listings++;
        if (listings == 1) return fs.listDirRecursive(path);
        return gate.future.then((_) => fs.listDirRecursive(path));
      },
    );
    await registry.load(fs, '/repo');
    fs.files['/repo/new_file.md'] = 'x';

    registry.load(fs, '/repo'); // kicks the refresh (listing 2, gated)
    registry.load(fs, '/repo'); // refresh in flight → must not stack a third
    gate.complete();
    await registry.drainRefreshesForTest();
    expect(listings, 2);

    final served = await registry.load(fs, '/repo');
    expect(served.files.map((e) => e.name), contains('new_file.md'));
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

  group('prewarm', () {
    test('cold root fills the cache once; repeat prewarms never re-list', () async {
      var listings = 0;
      final registry = QuickOpenIndexRegistry(
        lister: (path) {
          listings++;
          return fs.listDirRecursive(path);
        },
      );
      await registry.prewarm(fs, '/repo');
      await registry.prewarm(fs, '/repo');
      await registry.drainRefreshesForTest();
      expect(listings, 1);
      // The warmed entry is what the dialog's load serves.
      final index = await registry.load(fs, '/repo');
      expect(index.files.map((e) => e.name), contains('main.dart'));
    });

    test('warm entry: prewarm does not kick a revalidation', () async {
      var listings = 0;
      final registry = QuickOpenIndexRegistry(
        lister: (path) {
          listings++;
          return fs.listDirRecursive(path);
        },
      );
      await registry.load(fs, '/repo');
      await registry.drainRefreshesForTest();
      expect(listings, 1);

      await registry.prewarm(fs, '/repo');
      await registry.prewarm(fs, '/repo');
      await registry.drainRefreshesForTest();
      expect(listings, 1);
    });

    test('prewarm and load racing the cold listing share one future', () async {
      var listings = 0;
      final gate = Completer<void>();
      final registry = QuickOpenIndexRegistry(
        lister: (path) {
          listings++;
          return gate.future.then((_) => fs.listDirRecursive(path));
        },
      );
      final prewarmed = registry.prewarm(fs, '/repo');
      final loaded = registry.load(fs, '/repo');
      gate.complete();
      await Future.wait([prewarmed, loaded]);
      expect(listings, 1);
    });

    test('prewarm failure is not cached: the next load retries', () async {
      var fail = true;
      final registry = QuickOpenIndexRegistry(
        lister: (path) {
          if (fail) throw StateError('boom');
          return fs.listDirRecursive(path);
        },
      );
      await expectLater(registry.prewarm(fs, '/repo'), throwsStateError);
      fail = false;
      final index = await registry.load(fs, '/repo');
      expect(index.files, isNotEmpty);
    });

    test('prewarm keys by dirs rules like load', () async {
      var listings = 0;
      final registry = QuickOpenIndexRegistry(
        lister: (path) {
          listings++;
          return fs.listDirRecursive(path);
        },
      );
      await registry.prewarm(
        fs,
        '/repo',
        dirs: WorkspaceIndexDirs(excluded: ['lib']),
      );
      await registry.prewarm(fs, '/repo');
      await registry.drainRefreshesForTest();
      expect(listings, 2);

      final excluded = await registry.latestIndex(
        fs,
        '/repo',
        dirs: WorkspaceIndexDirs(excluded: ['lib']),
      );
      expect(
        excluded!.files.map((e) => e.relativePath),
        isNot(contains('lib/main.dart')),
      );
    });

    test('empty root prewarms nothing', () async {
      var listings = 0;
      final registry = QuickOpenIndexRegistry(
        lister: (path) {
          listings++;
          return fs.listDirRecursive(path);
        },
      );
      await registry.prewarm(fs, '');
      await registry.drainRefreshesForTest();
      expect(listings, 0);
    });
  });

  group('gitignore-aware listing via git ls-files', () {
    test(
      'git listing wins: gitignore-excluded files stay out of the index',
      () async {
        final runner = _FakeGitRunner(
          result: const GitCommandResult(
            exitCode: 0,
            stdout: 'README.md\x00lib/main.dart\x00',
            stderr: '',
          ),
        );
        final registry = QuickOpenIndexRegistry(gitRunner: runner);
        final index = await registry.load(fs, '/repo');

        expect(index.files.map((e) => e.relativePath).toList(), [
          'README.md',
          'lib/main.dart',
        ]);
        expect(index.truncated, isFalse);
        expect(runner.calls, hasLength(1));
        expect(runner.calls.single.$1, '/repo');
        expect(runner.calls.single.$2, contains('ls-files'));
        expect(runner.calls.single.$2, contains('--cached'));
        expect(runner.calls.single.$2, contains('--others'));
        expect(runner.calls.single.$2, contains('--exclude-standard'));
        expect(runner.calls.single.$2, contains('-z'));
      },
    );

    test('git entry fields use absolute path and basename', () async {
      final runner = _FakeGitRunner(
        result: const GitCommandResult(
          exitCode: 0,
          stdout: 'lib/main.dart\x00',
          stderr: '',
        ),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');
      final entry = index.files.single;
      expect(entry.path, '/repo/lib/main.dart');
      expect(entry.name, 'main.dart');
      expect(entry.relativePath, 'lib/main.dart');
    });

    test('git non-zero exit falls back to the recursive listing', () async {
      fs.files['/repo/vendor/app.log'] = 'x';
      final runner = _FakeGitRunner(
        result: const GitCommandResult(
          exitCode: 128,
          stdout: '',
          stderr: 'fatal: not a git repository',
        ),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');

      // vendor/ is ignored by git in real life but NOT in the hardcoded list,
      // so its presence proves we took the fallback path.
      expect(
        index.files.map((e) => e.relativePath),
        contains('vendor/app.log'),
      );
      expect(index.files.map((e) => e.relativePath), contains('README.md'));
      expect(
        index.files.map((e) => e.relativePath),
        isNot(contains('node_modules/pkg/index.js')),
      );
    });

    test('empty git output falls back to the recursive listing', () async {
      final runner = _FakeGitRunner(
        result: const GitCommandResult(exitCode: 0, stdout: '', stderr: ''),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');
      expect(index.files.map((e) => e.relativePath), contains('README.md'));
    });

    test('git runner throwing falls back to the recursive listing', () async {
      final runner = _FakeGitRunner(error: StateError('ssh down'));
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');
      expect(index.files.map((e) => e.relativePath), contains('README.md'));
    });

    test('git listing splits filenames with spaces on NUL', () async {
      final runner = _FakeGitRunner(
        result: const GitCommandResult(
          exitCode: 0,
          stdout: 'my file.txt\x00lib/with space.dart\x00',
          stderr: '',
        ),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');
      expect(index.files.map((e) => e.name).toSet(), {
        'my file.txt',
        'with space.dart',
      });
    });

    test('git listing honors the maxFiles cap', () async {
      final stdout = [for (var i = 0; i < 6; i++) 'file$i.txt\x00'].join();
      final runner = _FakeGitRunner(
        result: GitCommandResult(exitCode: 0, stdout: stdout, stderr: ''),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo', maxFiles: 5);
      expect(index.files, hasLength(5));
      expect(index.truncated, isTrue);
    });

    test('git listing tolerates stdout without a trailing NUL', () async {
      final runner = _FakeGitRunner(
        result: const GitCommandResult(
          exitCode: 0,
          stdout: 'lib/main.dart\x00README.md',
          stderr: '',
        ),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');
      expect(index.files.map((e) => e.relativePath).toList(), [
        'README.md',
        'lib/main.dart',
      ]);
      expect(index.truncated, isFalse);
    });

    test(
      'git POSIX paths join with the backend\'s native separators',
      () async {
        final windowsFs = InMemoryFilesystem(
          pathContext: p.Context(style: p.Style.windows),
        );
        final runner = _FakeGitRunner(
          result: const GitCommandResult(
            exitCode: 0,
            stdout: 'lib/main.dart\x00',
            stderr: '',
          ),
        );
        final registry = QuickOpenIndexRegistry(gitRunner: runner);
        final index = await registry.load(windowsFs, r'C:\repo');
        final entry = index.files.single;
        expect(entry.relativePath, r'lib\main.dart');
        expect(entry.path, r'C:\repo\lib\main.dart');
      },
    );
  });

  group('index dir rules', () {
    test('recursive path: exclude drops a subtree, include carves it back', () async {
      final registry = QuickOpenIndexRegistry();
      final index = await registry.load(
        fs,
        '/repo',
        dirs: WorkspaceIndexDirs(
          excluded: ['lib'],
          included: ['lib/src'],
        ),
      );

      final paths = index.files.map((e) => e.relativePath).toSet();
      expect(paths, contains('lib/src/terminal_session.dart'));
      expect(paths, isNot(contains('lib/main.dart')));
      expect(paths, contains('README.md'));
    });

    test('recursive path: include overrides the built-in ignores', () async {
      final registry = QuickOpenIndexRegistry();
      final index = await registry.load(
        fs,
        '/repo',
        dirs: WorkspaceIndexDirs(included: ['node_modules']),
      );

      expect(
        index.files.map((e) => e.relativePath),
        contains('node_modules/pkg/index.js'),
      );
    });

    test('git path: user rules apply, built-in ignores do not', () async {
      final runner = _FakeGitRunner(
        result: const GitCommandResult(
          exitCode: 0,
          stdout:
              'README.md\x00lib/main.dart\x00lib/src/terminal_session.dart\x00'
              'node_modules/pkg/index.js\x00',
          stderr: '',
        ),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(
        fs,
        '/repo',
        dirs: WorkspaceIndexDirs(
          excluded: ['lib'],
          included: ['lib/src'],
        ),
      );

      final paths = index.files.map((e) => e.relativePath).toSet();
      // node_modules is a built-in ignore but git reported the file as
      // tracked — the git source applies user rules only.
      expect(paths, {
        'README.md',
        'lib/src/terminal_session.dart',
        'node_modules/pkg/index.js',
      });
    });

    test('excluded files do not consume the maxFiles quota', () async {
      final stdout = [
        for (final path in [
          'ex/a.txt',
          'ex/b.txt',
          'ex/c.txt',
          'keep/d.txt',
          'keep/e.txt',
        ])
          '$path\x00',
      ].join();
      final runner = _FakeGitRunner(
        result: GitCommandResult(exitCode: 0, stdout: stdout, stderr: ''),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(
        fs,
        '/repo',
        maxFiles: 3,
        dirs: WorkspaceIndexDirs(excluded: ['ex']),
      );

      expect(index.files.map((e) => e.relativePath).toList(), [
        'keep/d.txt',
        'keep/e.txt',
      ]);
      expect(index.truncated, isFalse);
    });

    test('different rules cache separately from the rule-free listing', () async {
      final registry = QuickOpenIndexRegistry();
      final excluded = await registry.load(
        fs,
        '/repo',
        dirs: WorkspaceIndexDirs(excluded: ['lib']),
      );
      final unfiltered = await registry.load(fs, '/repo');

      expect(
        excluded.files.map((e) => e.relativePath),
        isNot(contains('lib/main.dart')),
      );
      expect(
        unfiltered.files.map((e) => e.relativePath),
        contains('lib/main.dart'),
      );
    });
  });

  group('directory symlink support', () {
    setUp(() {
      fs.ensureDir('/external/docs');
      fs.files['/external/docs/guide.md'] = 'x';
      fs.files['/external/docs/notes.txt'] = 'x';
    });

    test('recursive path indexes files under a linked directory', () async {
      await fs.createSymlink(target: '/external/docs', linkPath: '/repo/linked');
      final registry = QuickOpenIndexRegistry();
      final index = await registry.load(fs, '/repo');

      expect(
        index.files.map((e) => e.relativePath),
        allOf([
          contains('linked/guide.md'),
          contains('linked/notes.txt'),
          contains('README.md'),
        ]),
      );
      final entry = index.files.firstWhere(
        (e) => e.relativePath == 'linked/guide.md',
      );
      expect(entry.path, '/repo/linked/guide.md');
      expect(entry.name, 'guide.md');
    });

    test('git path indexes linked contents and drops the dir-link row', () async {
      await fs.createSymlink(target: '/external/docs', linkPath: '/repo/linked');
      final runner = _FakeGitRunner(
        result: const GitCommandResult(
          // git reports the directory link itself as a tracked entry.
          exitCode: 0,
          stdout: 'README.md\x00linked\x00',
          stderr: '',
        ),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');

      final paths = index.files.map((e) => e.relativePath).toList();
      expect(paths, contains('README.md'));
      expect(paths, contains('linked/guide.md'));
      expect(paths, contains('linked/notes.txt'));
      // The unopenable link row itself is replaced by its contents.
      expect(paths, isNot(contains('linked')));
    });

    test('a symlink cycle terminates and still indexes the tree', () async {
      await fs.createSymlink(target: '/repo', linkPath: '/repo/loop');
      final registry = QuickOpenIndexRegistry();
      final index = await registry.load(fs, '/repo');

      // The loop link's own row resolves into the tree's files; no hang.
      expect(index.files.map((e) => e.relativePath), contains('README.md'));
      expect(index.files.map((e) => e.relativePath), contains('lib/main.dart'));
    });

    test('ignore rules apply to linked paths', () async {
      fs.ensureDir('/external/pkg');
      fs.files['/external/pkg/index.js'] = 'x';
      await fs.createSymlink(target: '/external/pkg', linkPath: '/repo/node_modules/link');
      final registry = QuickOpenIndexRegistry();
      final index = await registry.load(fs, '/repo');

      for (final path in index.files.map((e) => e.relativePath)) {
        expect(path.startsWith('node_modules/'), isFalse);
      }
    });

    test('linked entries respect the maxFiles cap', () async {
      for (var i = 0; i < 4; i++) {
        fs.files['/external/docs/extra$i.txt'] = 'x';
      }
      await fs.createSymlink(target: '/external/docs', linkPath: '/repo/linked');
      final registry = QuickOpenIndexRegistry();
      final index = await registry.load(fs, '/repo', maxFiles: 5);
      expect(index.files.length, 5);
      expect(index.truncated, isTrue);
    });

    test('backends without the capability keep the legacy listing', () async {
      await fs.createSymlink(target: '/external/docs', linkPath: '/repo/linked');
      final plain = _PlainFilesystem();
      plain.files['/repo/README.md'] = 'x';
      final registry = QuickOpenIndexRegistry();
      final index = await registry.load(plain, '/repo');
      expect(index.files.map((e) => e.relativePath), ['README.md']);
    });

    test('the symlink scan starts before the base listing completes', () async {
      final scanFs = _CountingSymlinkFs();
      scanFs.ensureDir('/repo');
      scanFs.ensureDir('/external/docs');
      scanFs.files['/repo/README.md'] = 'x';
      scanFs.files['/external/docs/guide.md'] = 'x';
      await scanFs.createSymlink(
        target: '/external/docs',
        linkPath: '/repo/linked',
      );

      final baseGate = Completer<void>();
      final registry = QuickOpenIndexRegistry(
        lister: (path) =>
            baseGate.future.then((_) => scanFs.listDirRecursive(path)),
      );
      final loading = registry.load(scanFs, '/repo');
      await Future<void>.delayed(Duration.zero);
      // Sequential order would leave the scan waiting behind the gated base
      // listing; the concurrent scan has already run.
      expect(scanFs.symlinkScans, 1);

      baseGate.complete();
      final index = await loading;
      expect(
        index.files.map((e) => e.relativePath),
        allOf([contains('README.md'), contains('linked/guide.md')]),
      );
    });

    test('a failed symlink scan leaves the base listing intact', () async {
      final scanFs = _FailingSymlinkScanFs();
      scanFs.ensureDir('/repo');
      scanFs.files['/repo/README.md'] = 'x';
      final registry = QuickOpenIndexRegistry();
      final index = await registry.load(scanFs, '/repo');
      expect(index.files.map((e) => e.relativePath), ['README.md']);
    });
  });

  group('multi-root helpers', () {
    test('normalizeQuickOpenRoots drops empties, dupes and nested roots', () {
      expect(
        normalizeQuickOpenRoots([
          '/repo',
          '',
          '  ',
          '/repo',
          '/repo/lib',
          '/wt',
        ], fs.pathContext),
        ['/repo', '/wt'],
      );
    });

    test(
      'normalizeQuickOpenRoots keeps the outer root when it comes later',
      () {
        expect(
          normalizeQuickOpenRoots(['/repo/lib', '/repo'], fs.pathContext),
          ['/repo'],
        );
      },
    );

    test('normalizeQuickOpenRoots normalizes separators', () {
      final ctx = p.Context(style: p.Style.windows);
      expect(
        normalizeQuickOpenRoots([r'C:\repo\', r'C:\repo\lib', r'C:\wt'], ctx),
        [r'C:\repo', r'C:\wt'],
      );
    });

    QuickOpenFileEntry makeEntry(String path, String relative) =>
        QuickOpenFileEntry(
          path: path,
          name: fs.pathContext.basename(relative),
          relativePath: relative,
        );

    test('mergeQuickOpenIndexes prefixes secondary roots, sorts by path', () {
      final merged = mergeQuickOpenIndexes(
        roots: ['/repo', '/wt/feature-x'],
        indexesByRoot: {
          '/repo': QuickOpenIndex(
            truncated: false,
            files: [
              makeEntry('/repo/README.md', 'README.md'),
              makeEntry('/repo/lib/main.dart', 'lib/main.dart'),
            ],
          ),
          '/wt/feature-x': QuickOpenIndex(
            truncated: false,
            files: [
              makeEntry(
                '/wt/feature-x/lib/brand_new.dart',
                'lib/brand_new.dart',
              ),
            ],
          ),
        },
        ctx: fs.pathContext,
      );
      expect(merged.files.map((e) => e.relativePath).toList(), [
        'README.md',
        'feature-x/lib/brand_new.dart',
        'lib/main.dart',
      ]);
      expect(merged.files[1].path, '/wt/feature-x/lib/brand_new.dart');
      expect(merged.files[1].name, 'brand_new.dart');
      expect(merged.truncated, isFalse);
    });

    test('mergeQuickOpenIndexes ors truncation and skips missing roots', () {
      final merged = mergeQuickOpenIndexes(
        roots: ['/repo', '/missing', '/wt'],
        indexesByRoot: {
          '/repo': const QuickOpenIndex(files: [], truncated: true),
        },
        ctx: fs.pathContext,
      );
      expect(merged.files, isEmpty);
      expect(merged.truncated, isTrue);
    });
  });
}
