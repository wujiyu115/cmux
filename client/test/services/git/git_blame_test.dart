import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_blame.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/git/git_service.dart';

/// A canned `git blame --incremental` stream for two commits plus an
/// uncommitted block (all-zero hash), mimicking git's real format:
/// header line, tab-indented properties, `filename` trailer.
const _sampleBlame = '''
5c1b1e4f3c3d3c9e2a1b0c4d5e6f7a8b9c0d1e2f 3 3 2
author Ada Lovelace
author-mail <ada@example.com>
author-time 1700000000
author-tz +0100
summary Add parser core
filename lib/parser.dart
5c1b1e4f3c3d3c9e2a1b0c4d5e6f7a8b9c0d1e2f 5 5 1
author Ada Lovelace
author-mail <ada@example.com>
author-time 1700000000
author-tz +0100
summary Add parser core
filename lib/parser.dart
0000000000000000000000000000000000000000 1 1 1
author Not Committed Yet
author-mail <not.committed.yet>
author-time 1730000000
author-tz +0800
summary not committed yet
boundary
filename lib/parser.dart
9f9e002d0f0278e1a716cd407c1e3f7f8f6debe0 7 6 4
author Grace Hopper
author-mail <grace@example.com>
author-time 1600000000
author-tz -0500
summary Initial import
previous 1234567890abcdef1234567890abcdef12345678 lib/parser.dart
filename lib/parser.dart
''';

class _FakeRunner implements GitCommandRunner {
  _FakeRunner(this._stdout);

  final String _stdout;

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitCommandResult> runInDirectory(
    String dir,
    List<String> args,
  ) async => GitCommandResult(exitCode: 0, stdout: _stdout, stderr: '');
}

class _FailingRunner implements GitCommandRunner {
  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitCommandResult> runInDirectory(
    String dir,
    List<String> args,
  ) async => const GitCommandResult(
    exitCode: 128,
    stdout: '',
    stderr: 'fatal: no such path',
  );
}

void main() {
  group('parseIncrementalBlame', () {
    test('groups blocks per commit with ranges and properties', () {
      final entries = parseIncrementalBlame(_sampleBlame);

      expect(entries, hasLength(3));
      // Sorted by first range start: uncommitted(1), Ada(3), Grace(6).
      expect(entries[0].isUncommitted, isTrue);
      expect(entries[0].ranges.single, const GitBlameLineRange(start: 1, end: 1));

      final ada = entries[1];
      expect(ada.hash, '5c1b1e4f3c3d3c9e2a1b0c4d5e6f7a8b9c0d1e2f');
      expect(ada.authorName, 'Ada Lovelace');
      expect(ada.authorEmail, 'ada@example.com');
      expect(ada.authorTime, 1700000000);
      expect(ada.subject, 'Add parser core');
      // Two separate blocks of the same commit merge into two ranges.
      expect(ada.ranges, hasLength(2));
      expect(ada.ranges[0], const GitBlameLineRange(start: 3, end: 4));
      expect(ada.ranges[1], const GitBlameLineRange(start: 5, end: 5));

      final grace = entries[2];
      expect(grace.authorName, 'Grace Hopper');
      expect(
        grace.ranges.single,
        const GitBlameLineRange(start: 6, end: 9),
      );
      expect(grace.subject, 'Initial import');
    });

    test('forLine resolves the owning entry, null outside', () {
      final entries = parseIncrementalBlame(_sampleBlame);
      expect(entries[1].forLine(3)?.hash, entries[1].hash);
      expect(entries[1].forLine(4)?.hash, entries[1].hash);
      expect(entries[2].forLine(9)?.hash, entries[2].hash);
      expect(entries[0].forLine(10), isNull);
    });

    test('garbage input parses to an empty list', () {
      expect(parseIncrementalBlame(''), isEmpty);
      expect(parseIncrementalBlame('not git output\nat all'), isEmpty);
    });
  });

  group('GitService.blameFile', () {
    test('returns parsed entries on success', () async {
      final service = GitService(runner: _FakeRunner(_sampleBlame));
      final entries = await service.blameFile('/repo', 'lib/parser.dart');
      expect(entries, hasLength(3));
    });

    test('returns null on non-zero exit (not a repo / untracked)', () async {
      final service = GitService(runner: _FailingRunner());
      final entries = await service.blameFile('/repo', 'lib/parser.dart');
      expect(entries, isNull);
    });
  });
}
