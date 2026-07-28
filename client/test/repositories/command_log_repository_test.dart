import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/command_log_entry.dart';
import 'package:teampilot/repositories/command_log_repository.dart';

import '../support/in_memory_filesystem.dart';

/// Local wall-clock instant on the day under test. Day files are keyed by the
/// *local* date, so building the fixtures in local time keeps the test
/// timezone-independent.
DateTime _at(int hour) => DateTime(2026, 7, 20, hour);

CommandLogEntry _entry({
  String id = 'e1',
  String command = 'git status',
  required DateTime startedAt,
  int? exitCode = 0,
}) => CommandLogEntry(
  id: id,
  command: command,
  startedAt: startedAt,
  paneId: 'pane-1',
  surfaceId: 'sf-1',
  workspaceId: 'ws-1',
  paneName: 'pane one',
  surfaceName: 'surface one',
  workspaceName: 'demo',
  completedAt: startedAt.add(const Duration(seconds: 1)),
  exitCode: exitCode,
  workingDirectory: '/repo',
);

void main() {
  late InMemoryFilesystem fs;
  late CommandLogRepository repo;
  final today = _at(9);

  setUp(() {
    fs = InMemoryFilesystem();
    repo = CommandLogRepository(fs: fs, rootPath: '/root', clock: () => today);
  });

  test('directoryPath and fileFor use the yyyy-MM-dd day stem', () {
    expect(repo.directoryPath, '/root/logs/commands');
    expect(
      repo.fileFor(DateTime(2026, 1, 2)),
      '/root/logs/commands/2026-01-02.jsonl',
    );
  });

  test('ensureDirectory creates the folder before anything is logged', () async {
    expect((await fs.stat(repo.directoryPath)).exists, isFalse);
    await repo.ensureDirectory();
    expect((await fs.stat(repo.directoryPath)).isDirectory, isTrue);
  });

  test('load of a missing day returns an empty day, not an error', () async {
    final day = await repo.load(today);
    expect(day.entries, isEmpty);
    expect(day.skippedLines, 0);
    expect(day.date, DateTime(2026, 7, 20));
  });

  test('append writes one JSONL line per entry into the local day file', () async {
    await repo.append(_entry(startedAt: _at(9)));
    await repo.append(_entry(id: 'e2', command: 'ls', startedAt: _at(10)));

    final raw = fs.files[repo.fileFor(today)]!;
    expect(raw.endsWith('\n'), isTrue);
    final lines = const LineSplitter().convert(raw);
    expect(lines, hasLength(2));
    expect(jsonDecode(lines.first)['command'], 'git status');
    expect(jsonDecode(lines.last)['command'], 'ls');
  });

  test('append preserves every field through a round trip', () async {
    final started = _at(9);
    await repo.append(_entry(startedAt: started, exitCode: 3));

    final entry = (await repo.load(started)).entries.single;
    expect(entry.id, 'e1');
    expect(entry.command, 'git status');
    expect(entry.startedAt, started.toUtc());
    expect(entry.completedAt, started.add(const Duration(seconds: 1)).toUtc());
    expect(entry.exitCode, 3);
    expect(entry.paneId, 'pane-1');
    expect(entry.surfaceId, 'sf-1');
    expect(entry.workspaceId, 'ws-1');
    expect(entry.paneName, 'pane one');
    expect(entry.surfaceName, 'surface one');
    expect(entry.workspaceName, 'demo');
    expect(entry.workingDirectory, '/repo');
  });

  test('append redacts secrets and drops a line that is only a secret', () async {
    await repo.append(
      _entry(command: 'mysql --password hunter2', startedAt: _at(9)),
    );
    await repo.append(_entry(id: 'e2', command: 'Tr0ub4dor&3', startedAt: _at(9)));

    final entries = (await repo.load(today)).entries;
    expect(entries, hasLength(1));
    expect(entries.single.command, 'mysql --password [REDACTED]');
  });

  test('load returns rows newest first regardless of write order', () async {
    await repo.append(_entry(id: 'old', startedAt: _at(1)));
    await repo.append(_entry(id: 'new', startedAt: _at(5)));
    await repo.append(_entry(id: 'mid', startedAt: _at(3)));

    final ids = (await repo.load(today)).entries.map((e) => e.id).toList();
    expect(ids, ['new', 'mid', 'old']);
  });

  test('bad lines are skipped and counted, good lines survive', () async {
    final path = repo.fileFor(today);
    await repo.append(_entry(startedAt: _at(9)));
    // Truncated tail, non-object JSON, no command, unparseable timestamp.
    await fs.appendString(path, '{"command":"ls","started\n');
    await fs.appendString(path, '[1,2,3]\n');
    await fs.appendString(
      path,
      '{"command":"","startedAt":"2026-07-20T09:00:00Z"}\n',
    );
    await fs.appendString(path, '{"command":"ls","startedAt":"not-a-date"}\n');
    // Blank lines are ignored without counting as damage.
    await fs.appendString(path, '\n   \n');

    final day = await repo.load(today);
    expect(day.entries.map((e) => e.command), ['git status']);
    expect(day.skippedLines, 4);
  });

  test('the day file is never rewritten on read', () async {
    final path = repo.fileFor(today);
    await repo.append(_entry(startedAt: _at(9)));
    await fs.appendString(path, 'garbage\n');
    final before = fs.files[path];

    await repo.load(today);
    expect(fs.files[path], before);
  });

  test('a row written without an id still loads', () async {
    await fs.ensureDir(repo.directoryPath);
    await fs.appendString(
      repo.fileFor(today),
      '${jsonEncode({'command': 'ls', 'startedAt': '2026-07-20T09:00:00Z'})}\n',
    );

    final day = await repo.load(today);
    expect(day.skippedLines, 0);
    expect(day.entries.single.id, isNotEmpty);
    expect(day.entries.single.command, 'ls');
  });

  test('availableDates lists only valid day stems, newest first', () async {
    await fs.ensureDir(repo.directoryPath);
    for (final stem in ['2026-07-18', '2026-07-20', '2026-07-19']) {
      await fs.appendString('${repo.directoryPath}/$stem.jsonl', '');
    }
    // Ignored: wrong extension, non-date stem, impossible date, subdirectory.
    await fs.appendString('${repo.directoryPath}/2026-07-21.txt', '');
    await fs.appendString('${repo.directoryPath}/index.jsonl', '');
    await fs.appendString('${repo.directoryPath}/2026-02-30.jsonl', '');
    await fs.ensureDir('${repo.directoryPath}/nested');

    expect(await repo.availableDates(), [
      DateTime(2026, 7, 20),
      DateTime(2026, 7, 19),
      DateTime(2026, 7, 18),
    ]);
  });

  test('availableDates is empty when the directory does not exist', () async {
    expect(await repo.availableDates(), isEmpty);
  });

  test('applyRetention deletes whole day files outside the window', () async {
    await fs.ensureDir(repo.directoryPath);
    for (final stem in [
      '2026-07-10',
      '2026-07-18',
      '2026-07-19',
      '2026-07-20',
    ]) {
      await fs.appendString('${repo.directoryPath}/$stem.jsonl', 'x\n');
    }

    // A 3-day window ending today (2026-07-20) keeps 18 / 19 / 20.
    expect(await repo.applyRetention(3), [DateTime(2026, 7, 10)]);
    expect(await repo.availableDates(), [
      DateTime(2026, 7, 20),
      DateTime(2026, 7, 19),
      DateTime(2026, 7, 18),
    ]);
    expect(
      fs.files.containsKey('${repo.directoryPath}/2026-07-10.jsonl'),
      isFalse,
    );
  });

  test('applyRetention of 0 or less keeps everything', () async {
    await fs.ensureDir(repo.directoryPath);
    await fs.appendString('${repo.directoryPath}/2020-01-01.jsonl', 'x\n');
    expect(await repo.applyRetention(0), isEmpty);
    expect(await repo.applyRetention(-5), isEmpty);
    expect(await repo.availableDates(), hasLength(1));
  });

  group('day stem helpers', () {
    test('formatLogDate pads month and day', () {
      expect(formatLogDate(DateTime(2026, 1, 2)), '2026-01-02');
      expect(formatLogDate(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('parseLogDate rejects anything that is not a real date', () {
      expect(parseLogDate('2026-07-20'), DateTime(2026, 7, 20));
      expect(parseLogDate('2026-7-20'), isNull);
      expect(parseLogDate('index'), isNull);
      expect(parseLogDate('2026-13-01'), isNull);
      expect(parseLogDate('2026-02-30'), isNull);
      expect(parseLogDate(''), isNull);
    });
  });

  group('commandDurationLabel', () {
    test('scales the unit with the magnitude', () {
      expect(commandDurationLabel(const Duration(milliseconds: 820)), '820ms');
      expect(commandDurationLabel(const Duration(milliseconds: 1400)), '1.4s');
      expect(commandDurationLabel(const Duration(seconds: 123)), '2m 3s');
      expect(commandDurationLabel(const Duration(minutes: 64)), '1h 4m');
      expect(commandDurationLabel(const Duration(milliseconds: -5)), '0ms');
    });
  });
}
