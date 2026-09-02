import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/workbench/code_find_panel.dart';

Widget _wrap(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return TpTheme(
    data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: theme,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  late CodeLineEditingController editor;
  late CodeFindController controller;

  setUp(() {
    editor = CodeLineEditingController();
    editor.text = 'foo\nbar\nfoo';
    controller = CodeFindController(editor);
  });

  tearDown(() {
    controller.dispose();
    editor.dispose();
  });

  Widget panel() => ListenableBuilder(
    listenable: controller,
    builder:
        (context, _) => CodeFindPanel(controller: controller, readOnly: false),
  );

  testWidgets('closed controller renders nothing', (tester) async {
    await tester.pumpWidget(_wrap(panel()));
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('find mode shows input, option chips, and actions', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(panel()));
    controller.findMode();
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Find'), findsOneWidget);
    expect(find.text('Aa'), findsOneWidget);
    expect(find.text('.*'), findsOneWidget);
    expect(find.byTooltip('Previous match'), findsOneWidget);
    expect(find.byTooltip('Next match'), findsOneWidget);
    expect(find.byTooltip('Close find'), findsOneWidget);

    // No replace row before toggling.
    expect(find.widgetWithText(TextField, 'Replace with'), findsNothing);
  });

  testWidgets('toggle replace reveals and hides the replace row', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(panel()));
    controller.findMode();
    await tester.pump();

    await tester.tap(find.byTooltip('Toggle replace'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Replace with'), findsOneWidget);
    expect(find.byTooltip('Replace'), findsOneWidget);
    expect(find.byTooltip('Replace all'), findsOneWidget);

    await tester.tap(find.byTooltip('Toggle replace'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Replace with'), findsNothing);
  });

  testWidgets('escape while the find input is focused closes the panel', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(panel()));
    controller.findMode();
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Find'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(controller.value, isNull);
    expect(find.byType(TextField), findsNothing);
  });
}
