import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workbench/editor_goto_line_dialog.dart';

const _kSampleText = 'alpha\nbeta\ngamma\ndelta';

Widget _host(CodeLineEditingController controller) {
  final theme = ThemeData(useMaterial3: true);
  return TpTheme(
    data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showEditorGotoLineDialog(context, controller: controller),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(
  WidgetTester tester,
  CodeLineEditingController controller,
) async {
  await tester.pumpWidget(_host(controller));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

TextField _textField() =>
    find.byType(TextField).evaluate().single.widget as TextField;

int _cursorLine(CodeLineEditingController controller) =>
    controller.index2lineIndex(controller.selection.extentIndex) + 1;

void main() {
  late CodeLineEditingController controller;

  setUp(() {
    controller = CodeLineEditingController.fromText(_kSampleText);
    addTearDown(controller.dispose);
  });

  testWidgets('pre-fills the current line and jumps to the entered one', (
    tester,
  ) async {
    controller.selection = const CodeLineSelection.collapsed(index: 1, offset: 0);
    await _openDialog(tester, controller);

    expect(find.text('Go to Line'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(_textField().controller!.text, '2');

    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(_cursorLine(controller), 3);
    expect(controller.selection.isCollapsed, isTrue);
  });

  testWidgets('Enter submits and out-of-range input clamps to lineCount', (
    tester,
  ) async {
    await _openDialog(tester, controller);

    await tester.enterText(find.byType(TextField), '999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(_cursorLine(controller), 4);
  });

  testWidgets('Escape closes without moving the cursor', (tester) async {
    controller.selection = const CodeLineSelection.collapsed(index: 2, offset: 0);
    await _openDialog(tester, controller);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(_cursorLine(controller), 3);
  });

  testWidgets('empty input closes without moving the cursor', (tester) async {
    controller.selection = const CodeLineSelection.collapsed(index: 2, offset: 0);
    await _openDialog(tester, controller);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(_cursorLine(controller), 3);
  });

  testWidgets('non-digits are rejected by the input formatter', (
    tester,
  ) async {
    await _openDialog(tester, controller);

    await tester.enterText(find.byType(TextField), '2a');
    await tester.pump();

    expect(_textField().controller!.text, '2');
  });
}
