import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/git/git_command_runner.dart';
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
}
