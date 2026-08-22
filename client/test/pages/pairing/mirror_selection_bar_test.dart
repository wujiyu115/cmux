import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/mirror_selection_bar.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

void main() {
  Future<void> pump(WidgetTester tester, VoidCallback onCopy) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: MirrorSelectionBar(onCopy: onCopy))),
      ),
    );
  }

  testWidgets('shows the localized copy label', (tester) async {
    await pump(tester, () {});
    expect(find.text('Copy'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
  });

  testWidgets('tapping invokes the copy callback', (tester) async {
    var taps = 0;
    await pump(tester, () => taps++);
    await tester.tap(find.byKey(AppKeys.pairingMirrorCopyButton));
    await tester.pump();
    expect(taps, 1);
  });
}
