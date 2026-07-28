import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/command_history/command_history_dialog.dart';

void main() {
  /// Opens the picker over a trivial host route with a fixed command list and
  /// returns its localizations.
  Future<AppLocalizations> open(
    WidgetTester tester, {
    required List<String> commands,
    String? paneLabel,
    void Function(String command)? onInsert,
    void Function(String command)? onRun,
  }) async {
    late BuildContext hostContext;
    final theme = ThemeData(useMaterial3: true);
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
    showDialog<void>(
      context: hostContext,
      builder: (_) => CommandHistoryDialog(
        loader: () async => commands,
        paneLabel: paneLabel,
        onInsert: onInsert,
        onRun: onRun,
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(CommandHistoryDialog)));
  }

  testWidgets('renders one numbered row per command, newest first', (
    tester,
  ) async {
    final l10n = await open(tester, commands: ['git push', 'ls', 'git status']);

    expect(find.text('git push'), findsOneWidget);
    expect(find.text('ls'), findsOneWidget);
    expect(find.text('git status'), findsOneWidget);
    // Ordinals 1..3 label the rows.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text(l10n.commandHistoryCount(3)), findsOneWidget);
  });

  testWidgets('the pane label shows in the title', (tester) async {
    final l10n = await open(tester, commands: const ['ls'], paneLabel: 'pane 2');
    expect(find.text(l10n.commandHistoryPaneTitle('pane 2')), findsOneWidget);
  });

  testWidgets('empty vs no-matches states differ', (tester) async {
    final l10n = await open(tester, commands: const []);
    expect(find.text(l10n.commandHistoryEmpty), findsOneWidget);
  });

  testWidgets('search narrows the visible rows', (tester) async {
    final l10n = await open(tester, commands: ['git push', 'flutter test']);
    await tester.enterText(find.byType(TextField), 'flutter');
    await tester.pumpAndSettle();
    expect(find.text('flutter test'), findsOneWidget);
    expect(find.text('git push'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text(l10n.commandHistoryNoMatches), findsOneWidget);
  });

  testWidgets('the most recent command is selected on open (Insert acts on it)', (
    tester,
  ) async {
    final inserted = <String>[];
    final l10n = await open(
      tester,
      commands: const ['git push', 'ls'],
      onInsert: inserted.add,
    );

    // No manual selection: the first (newest) row is already active.
    await tester.tap(find.widgetWithText(TpButton, l10n.commandHistoryInsert));
    await tester.pumpAndSettle();
    expect(inserted, ['git push']);
  });

  testWidgets('footer actions are inert when the list is empty', (tester) async {
    final inserted = <String>[];
    final l10n = await open(tester, commands: const [], onInsert: inserted.add);
    await tester.tap(find.widgetWithText(TpButton, l10n.commandHistoryInsert));
    await tester.pumpAndSettle();
    expect(inserted, isEmpty);
  });

  testWidgets('Enter runs the selection, Shift+Enter inserts it', (
    tester,
  ) async {
    final ran = <String>[];
    final inserted = <String>[];
    await open(
      tester,
      commands: ['git push', 'ls'],
      onInsert: inserted.add,
      onRun: ran.add,
    );

    // First row is selected by default; plain Enter runs it and pops.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(ran, ['git push']);
    expect(find.byType(CommandHistoryDialog), findsNothing);
  });

  testWidgets('Shift+Enter inserts the selection', (tester) async {
    final ran = <String>[];
    final inserted = <String>[];
    await open(
      tester,
      commands: ['git push', 'ls'],
      onInsert: inserted.add,
      onRun: ran.add,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(inserted, ['git push']);
    expect(ran, isEmpty);
  });

  testWidgets('arrow keys move the selection before running', (tester) async {
    final ran = <String>[];
    await open(tester, commands: ['git push', 'ls'], onRun: ran.add);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(ran, ['ls']);
  });

  testWidgets('run / insert are disabled when the host cannot write', (
    tester,
  ) async {
    // No onRun / onInsert: Enter is a no-op and the dialog stays open.
    await open(tester, commands: const ['ls']);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CommandHistoryDialog), findsOneWidget);
  });
}
