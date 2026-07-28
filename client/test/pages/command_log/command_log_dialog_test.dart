import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/command_log_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/command_log_entry.dart';
import 'package:teampilot/pages/command_log/command_log_dialog.dart';
import 'package:teampilot/repositories/command_log_repository.dart';
import 'package:teampilot/services/io/system_folder_opener.dart';

import '../../support/in_memory_filesystem.dart';

DateTime _at(int hour, {int minute = 0, int day = 20}) =>
    DateTime(2026, 7, day, hour, minute);

CommandLogEntry _entry({
  required String id,
  String command = 'git status',
  DateTime? startedAt,
  Duration? took = const Duration(milliseconds: 400),
  int? exitCode = 0,
  String paneId = 'pane-1',
  String surfaceId = 'sf-1',
  String workspaceId = 'ws-1',
  String workingDirectory = '/repo',
}) {
  final start = startedAt ?? _at(9);
  return CommandLogEntry(
    id: id,
    command: command,
    startedAt: start,
    paneId: paneId,
    surfaceId: surfaceId,
    workspaceId: workspaceId,
    paneName: 'pane one',
    surfaceName: 'surface one',
    workspaceName: 'demo',
    completedAt: took == null ? null : start.add(took),
    exitCode: exitCode,
    workingDirectory: workingDirectory,
  );
}

void main() {
  late InMemoryFilesystem fs;
  late CommandLogRepository repo;
  late CommandLogCubit cubit;
  final now = _at(12);

  setUp(() {
    fs = InMemoryFilesystem();
    repo = CommandLogRepository(fs: fs, rootPath: '/root', clock: () => now);
    cubit = CommandLogCubit(repository: repo, clock: () => now);
  });

  tearDown(() => cubit.close());

  /// Opens the dialog over a trivial host route and returns its localizations.
  Future<AppLocalizations> open(
    WidgetTester tester, {
    void Function(String command)? onInsert,
    void Function(String command)? onRun,
    SystemFolderOpener? folderOpener,
  }) async {
    late BuildContext hostContext;
    final theme = ThemeData(useMaterial3: true);
    // TpTheme sits above MaterialApp so the root-navigator dialog resolves it.
    await tester.pumpWidget(
      TpTheme(
        data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: theme,
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    );
    showCommandLogDialog(
      hostContext,
      cubit: cubit,
      onInsert: onInsert,
      onRun: onRun,
      folderOpener: folderOpener,
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(CommandLogDialog)));
  }

  testWidgets('opening loads the day and renders one row per entry', (
    tester,
  ) async {
    await repo.append(_entry(id: 'a', command: 'git status'));
    await repo.append(
      _entry(id: 'b', command: 'flutter test', startedAt: _at(10, minute: 30)),
    );

    final l10n = await open(tester);

    expect(find.text(l10n.commandLogTitle), findsOneWidget);
    expect(find.text('git status'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);
    expect(find.text('10:30:00'), findsOneWidget);
    expect(find.text('400ms'), findsNWidgets(2));
    expect(find.text(l10n.commandLogEntryCount(2)), findsOneWidget);
  });

  testWidgets('a row with no status shows em dashes for exit code and duration', (
    tester,
  ) async {
    await repo.append(_entry(id: 'a', exitCode: null, took: null));
    await open(tester);
    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets('the empty state distinguishes "no rows" from "no matches"', (
    tester,
  ) async {
    final l10n = await open(tester);
    expect(find.text(l10n.commandLogEmpty), findsOneWidget);

    cubit.setQuery('nothing');
    await tester.pumpAndSettle();
    expect(find.text(l10n.commandLogNoMatches), findsOneWidget);
  });

  testWidgets('search narrows the visible rows', (tester) async {
    await repo.append(_entry(id: 'a', command: 'git status'));
    await repo.append(_entry(id: 'b', command: 'flutter test'));

    final l10n = await open(tester);
    await tester.enterText(find.byType(TextField), 'flutter');
    await tester.pumpAndSettle();

    expect(find.text('git status'), findsNothing);
    expect(find.text('flutter test'), findsOneWidget);
    expect(find.text(l10n.commandLogEntryCount(1)), findsOneWidget);

    await tester.tap(find.text(l10n.commandLogClearFilters));
    await tester.pumpAndSettle();
    expect(find.text('git status'), findsOneWidget);
  });

  testWidgets('footer actions stay disabled until a row is selected', (
    tester,
  ) async {
    await repo.append(_entry(id: 'a'));
    var inserted = 0;
    final l10n = await open(tester, onInsert: (_) => inserted++);

    await tester.tap(find.text(l10n.commandLogInsertIntoPane));
    await tester.pumpAndSettle();
    expect(inserted, 0);
    expect(find.byType(CommandLogDialog), findsOneWidget);

    await tester.tap(find.text('git status'));
    await tester.pump();
    await tester.tap(find.text(l10n.commandLogInsertIntoPane));
    await tester.pumpAndSettle();
    expect(inserted, 1);
    // Insert hands off to the pane, so the window closes behind it.
    expect(find.byType(CommandLogDialog), findsNothing);
  });

  testWidgets('run sends the selected command and closes', (tester) async {
    await repo.append(_entry(id: 'a', command: 'flutter test'));
    final ran = <String>[];
    final l10n = await open(tester, onRun: ran.add);

    await tester.tap(find.text('flutter test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commandLogRunInPane));
    await tester.pumpAndSettle();

    expect(ran, ['flutter test']);
    expect(find.byType(CommandLogDialog), findsNothing);
  });

  testWidgets('double-tapping a row runs it', (tester) async {
    await repo.append(_entry(id: 'a', command: 'flutter test'));
    final ran = <String>[];
    await open(tester, onRun: ran.add);

    final row = find.text('flutter test');
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(ran, ['flutter test']);
  });

  testWidgets('run stays disabled when the host cannot run commands', (
    tester,
  ) async {
    await repo.append(_entry(id: 'a'));
    final l10n = await open(tester);

    await tester.tap(find.text('git status'));
    await tester.pump();
    await tester.tap(find.text(l10n.commandLogRunInPane));
    await tester.pumpAndSettle();
    expect(find.byType(CommandLogDialog), findsOneWidget);
  });

  testWidgets('a corrupt tail is reported instead of silently shortening', (
    tester,
  ) async {
    await repo.append(_entry(id: 'a'));
    await fs.appendString(repo.fileFor(_at(9)), 'garbage\n');

    final l10n = await open(tester);
    expect(find.text(l10n.commandLogEntryCount(1)), findsOneWidget);
    expect(find.text(l10n.commandLogSkippedLines(1)), findsOneWidget);
  });

  testWidgets('open folder creates the log directory and reveals it', (
    tester,
  ) async {
    final revealed = <String>[];
    final l10n = await open(
      tester,
      folderOpener: SystemFolderOpener(
        isMacOS: false,
        isWindows: true,
        isLinux: false,
        runner: (exe, args) async => revealed.addAll(args),
      ),
    );

    await tester.tap(find.byTooltip(l10n.commandLogOpenFolder));
    await tester.pumpAndSettle();

    expect(revealed, [repo.directoryPath]);
    expect((await fs.stat(repo.directoryPath)).isDirectory, isTrue);
  });

  testWidgets('the close button dismisses the window', (tester) async {
    final l10n = await open(tester);
    await tester.tap(find.byTooltip(l10n.commandLogClose));
    await tester.pumpAndSettle();
    expect(find.byType(CommandLogDialog), findsNothing);
  });

  group('commandLogTimeLabel', () {
    test('renders local HH:mm:ss with zero padding', () {
      expect(commandLogTimeLabel(DateTime(2026, 7, 20, 9, 5, 3)), '09:05:03');
      expect(commandLogTimeLabel(DateTime(2026, 7, 20, 23, 59, 59)), '23:59:59');
    });
  });
}
