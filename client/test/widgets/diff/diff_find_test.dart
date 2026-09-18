import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/diff/diff_engine.dart';
import 'package:teampilot/widgets/diff/side_by_side_diff_view.dart';
import 'package:teampilot/widgets/diff/unified_diff_view.dart';

import '../../support/post_frame_test_harness.dart';

/// Regression: diff tabs opened from Source Control had no find wiring, so
/// Ctrl+F did nothing inside them. Both diff views now mount a find controller
/// and a find-bar overlay; the re-editor desktop shortcut layer turns that
/// into Ctrl+F.
///
/// Uses [TargetPlatformVariant.only] with windows: vendored re-editor caches
/// `kIsAndroid`/`kIsIOS` as library-level finals at first load, so the
/// desktop-vs-mobile branch is decided when the library first loads in the
/// isolate — the platform variant runs this file's tests with that platform
/// from the start.
void main() {
  setUpAll(setUpTestAppStorage);
  tearDownAll(tearDownTestAppStorage);

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SizedBox(width: 800, height: 400, child: child),
        ),
      ),
    );
    // Settle the async DocumentSession open + viewport colorize.
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Ctrl+F opens and Esc closes find in unified view',
    (tester) async {
      await pump(
        tester,
        UnifiedDiffView(
          result: computeLineDiff(
            'final a = 1;\nfinal b = 2;',
            'final a = 1;\nfinal b = 22;',
          ),
          filePath: 'sample.dart',
        ),
      );

      // Closed controller renders a zero-size placeholder; the find input only
      // exists once the panel opens.
      expect(find.byType(TextField), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'final');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('Ctrl+F opens find in side-by-side view', (tester) async {
    await pump(
      tester,
      SideBySideDiffView(
        result: computeLineDiff('final a = 1;', 'final a = 11;'),
        filePath: 'sample.dart',
      ),
    );

    expect(find.byType(TextField), findsNothing);
    // Focus the right (new) pane — the side-by-side view only wires find
    // there; tapping the right half of the 800px body lands in it.
    await tester.tapAt(const Offset(600, 200));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
