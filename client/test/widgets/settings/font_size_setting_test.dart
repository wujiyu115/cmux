import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/widgets/settings/font_size_setting.dart';

void main() {
  testWidgets('stepper digits vertically centered against px label (regression: 7px sag)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: Center(child: FontSizeSetting(size: 15, minSize: 12, maxSize: 24, onChanged: _noop)),
      ),
    ));
    final digitRect = tester.getRect(
      find.descendant(of: find.byType(TextField), matching: find.byType(EditableText)),
    );
    final pxRect = tester.getRect(find.text('px'));
    expect((digitRect.center.dy - pxRect.center.dy).abs(), lessThan(0.5));
  });
}

void _noop(double _) {}
