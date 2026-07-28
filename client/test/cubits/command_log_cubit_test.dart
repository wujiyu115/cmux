import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/command_log_cubit.dart';
import 'package:teampilot/models/command_log_entry.dart';
import 'package:teampilot/repositories/command_log_repository.dart';

import '../support/in_memory_filesystem.dart';

DateTime _at(int hour, {int day = 20}) => DateTime(2026, 7, day, hour);

CommandLogEntry _entry({
  required String id,
  String command = 'git status',
  DateTime? startedAt,
  String paneId = 'pane-1',
  String surfaceId = 'sf-1',
  String workspaceId = 'ws-1',
  String paneName = 'pane one',
  String surfaceName = 'surface one',
  String workspaceName = 'demo',
  String workingDirectory = '/repo',
}) => CommandLogEntry(
  id: id,
  command: command,
  startedAt: startedAt ?? _at(9),
  paneId: paneId,
  surfaceId: surfaceId,
  workspaceId: workspaceId,
  paneName: paneName,
  surfaceName: surfaceName,
  workspaceName: workspaceName,
  completedAt: (startedAt ?? _at(9)).add(const Duration(seconds: 1)),
  exitCode: 0,
  workingDirectory: workingDirectory,
);

void main() {
  late InMemoryFilesystem fs;
  late CommandLogRepository repo;
  final now = _at(12);

  CommandLogCubit build() =>
      CommandLogCubit(repository: repo, clock: () => now);

  setUp(() {
    fs = InMemoryFilesystem();
    repo = CommandLogRepository(fs: fs, rootPath: '/root', clock: () => now);
  });

  test('load with no history selects today and reports no rows', () async {
    final cubit = build();
    await cubit.load();
    expect(cubit.state.dates, isEmpty);
    expect(cubit.state.selectedDate, DateTime(2026, 7, 20));
    expect(cubit.state.entries, isEmpty);
    expect(cubit.state.isLoading, isFalse);
    await cubit.close();
  });

  test('load prefers today, and falls back to the newest day on disk', () async {
    await repo.append(_entry(id: 'y', startedAt: _at(9, day: 18)));
    await repo.append(_entry(id: 'x', startedAt: _at(9, day: 19)));

    final cubit = build();
    await cubit.load();
    expect(cubit.state.dates, [DateTime(2026, 7, 19), DateTime(2026, 7, 18)]);
    expect(cubit.state.selectedDate, DateTime(2026, 7, 19));
    expect(cubit.state.entries.single.id, 'x');
    await cubit.close();

    await repo.append(_entry(id: 'today'));
    final fresh = build();
    await fresh.load();
    expect(fresh.state.selectedDate, DateTime(2026, 7, 20));
    expect(fresh.state.entries.single.id, 'today');
    await fresh.close();
  });

  test('selectDate loads another day and surfaces skipped lines', () async {
    await repo.append(_entry(id: 'a', startedAt: _at(9, day: 19)));
    await fs.appendString(repo.fileFor(_at(9, day: 19)), 'garbage\n');
    await repo.append(_entry(id: 'b'));

    final cubit = build();
    await cubit.load();
    expect(cubit.state.skippedLines, 0);

    await cubit.selectDate(DateTime(2026, 7, 19));
    expect(cubit.state.selectedDate, DateTime(2026, 7, 19));
    expect(cubit.state.entries.single.id, 'a');
    expect(cubit.state.skippedLines, 1);
    await cubit.close();
  });

  test('record appends to disk and prepends to the selected day', () async {
    final cubit = build();
    await cubit.load();

    await cubit.recordAndWait(_entry(id: 'first', startedAt: _at(9)));
    await cubit.recordAndWait(_entry(id: 'second', startedAt: _at(10)));

    expect(cubit.state.entries.map((e) => e.id), ['second', 'first']);
    expect((await repo.load(_at(9))).entries.map((e) => e.id), [
      'second',
      'first',
    ]);
    await cubit.close();
  });

  test('a row for another day is written but not shown', () async {
    final cubit = build();
    await cubit.load();
    await cubit.recordAndWait(_entry(id: 'yesterday', startedAt: _at(9, day: 19)));

    expect(cubit.state.entries, isEmpty);
    expect((await repo.load(_at(9, day: 19))).entries.single.id, 'yesterday');
    await cubit.close();
  });

  test('concurrent records never interleave a half-written line', () async {
    final cubit = build();
    await cubit.load();
    await Future.wait([
      for (var i = 0; i < 8; i++)
        cubit.recordAndWait(_entry(id: 'e$i', startedAt: _at(9))),
    ]);

    final day = await repo.load(_at(9));
    expect(day.entries, hasLength(8));
    expect(day.skippedLines, 0);
    await cubit.close();
  });

  group('filtering', () {
    Future<CommandLogCubit> seeded() async {
      await repo.append(
        _entry(id: 'a', command: 'git status', workingDirectory: '/repo'),
      );
      await repo.append(
        _entry(
          id: 'b',
          command: 'flutter test',
          startedAt: _at(10),
          paneId: 'pane-2',
          surfaceId: 'sf-2',
          surfaceName: 'surface two',
          paneName: 'pane two',
        ),
      );
      await repo.append(
        _entry(
          id: 'c',
          command: 'ls',
          startedAt: _at(11),
          workspaceId: 'ws-2',
          workspaceName: 'other',
          workingDirectory: '/tmp/scratch',
        ),
      );
      final cubit = build();
      await cubit.load();
      return cubit;
    }

    test('no filters shows every row, newest first', () async {
      final cubit = await seeded();
      expect(cubit.state.hasFilters, isFalse);
      expect(cubit.state.visible.map((e) => e.id), ['c', 'b', 'a']);
      await cubit.close();
    });

    test('workspace / surface / pane filters narrow by id', () async {
      final cubit = await seeded();
      cubit.setWorkspaceFilter('ws-2');
      expect(cubit.state.visible.map((e) => e.id), ['c']);
      cubit.setWorkspaceFilter('');
      cubit.setSurfaceFilter('sf-2');
      expect(cubit.state.visible.map((e) => e.id), ['b']);
      cubit.setSurfaceFilter('');
      cubit.setPaneFilter('pane-2');
      expect(cubit.state.visible.map((e) => e.id), ['b']);
      await cubit.close();
    });

    test('query matches command and working directory, case-insensitively', () async {
      final cubit = await seeded();
      cubit.setQuery('FLUTTER');
      expect(cubit.state.visible.map((e) => e.id), ['b']);
      cubit.setQuery('scratch');
      expect(cubit.state.visible.map((e) => e.id), ['c']);
      cubit.setQuery('nothing-here');
      expect(cubit.state.visible, isEmpty);
      await cubit.close();
    });

    test('filters combine, and clearFilters resets all of them', () async {
      final cubit = await seeded();
      cubit.setWorkspaceFilter('ws-1');
      cubit.setQuery('ls');
      expect(cubit.state.hasFilters, isTrue);
      expect(cubit.state.visible, isEmpty);

      cubit.clearFilters();
      expect(cubit.state.hasFilters, isFalse);
      expect(cubit.state.visible, hasLength(3));
      await cubit.close();
    });

    test('filter options are deduped, labelled, and in first-seen order', () async {
      final cubit = await seeded();
      expect(cubit.state.workspaceOptions, [('ws-2', 'other'), ('ws-1', 'demo')]);
      expect(cubit.state.surfaceOptions, [
        ('sf-1', 'surface one'),
        ('sf-2', 'surface two'),
      ]);
      expect(cubit.state.paneOptions, [
        ('pane-1', 'pane one'),
        ('pane-2', 'pane two'),
      ]);
      await cubit.close();
    });

    test('an unlabelled id falls back to the id itself', () async {
      await repo.append(_entry(id: 'a', workspaceName: '', paneName: ''));
      final cubit = build();
      await cubit.load();
      expect(cubit.state.workspaceOptions, [('ws-1', 'ws-1')]);
      expect(cubit.state.paneOptions, [('pane-1', 'pane-1')]);
      await cubit.close();
    });
  });

  test('prepareDirectory creates the log folder and returns it', () async {
    final cubit = build();
    expect((await fs.stat(cubit.directoryPath)).exists, isFalse);
    expect(await cubit.prepareDirectory(), repo.directoryPath);
    expect((await fs.stat(repo.directoryPath)).isDirectory, isTrue);
    await cubit.close();
  });

  test('applyRetention drops old day files and the dates that went with them', () async {
    await repo.append(_entry(id: 'old', startedAt: _at(9, day: 1)));
    await repo.append(_entry(id: 'new', startedAt: _at(9)));

    final cubit = build();
    await cubit.load();
    expect(cubit.state.dates, hasLength(2));

    expect(await cubit.applyRetention(days: 2), 1);
    expect(cubit.state.dates, [DateTime(2026, 7, 20)]);
    await cubit.close();
  });
}
