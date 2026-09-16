import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/settings/mono_font_size_setting.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('segments map to scale values and custom shows a % field', (
    tester,
  ) async {
    // TpSegmentedPicker switches to a compact select (SizedBox(width:
    // infinity)) below its 840px breakpoint, which cannot live inside the
    // setting's FittedBox — test at desktop width like the settings page.
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final changes = <double>[];
    await tester.pumpWidget(
      _wrap(
        MonoFontSizeSetting(scale: kDefaultMonoFontScale, onChanged: changes.add),
      ),
    );
    await tester.pump();

    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Large'));
    await tester.pump();
    expect(changes, [kMonoFontScaleLarge]);

    await tester.tap(find.text('Small'));
    await tester.pump();
    expect(changes, [kMonoFontScaleLarge, kMonoFontScaleSmall]);

    // Picking Custom reveals the percent input without changing the value.
    await tester.tap(find.text('Custom'));
    await tester.pump();
    expect(changes, [kMonoFontScaleLarge, kMonoFontScaleSmall]);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('custom percent input clamps and commits', (tester) async {
    // Desktop width — see note above.
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final changes = <double>[];
    await tester.pumpWidget(
      _wrap(MonoFontSizeSetting(scale: 1.2, onChanged: changes.add)),
    );
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '250');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    // done fires both onSubmitted and onEditingComplete (mirrors
    // TypographyScaleSetting) — assert the committed value, not call count.
    expect(changes.last, kMonoFontScaleMax);
    expect(changes.toSet(), {kMonoFontScaleMax});
    expect(find.widgetWithText(TextField, '160'), findsOneWidget);
  });
}
