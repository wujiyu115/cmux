import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/debug_log_page.dart';
import 'package:teampilot/services/app/debug_log_settings.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

void main() {
  late Directory temp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('tp_debug_log_page_');
  });

  tearDown(() async {
    try {
      if (await temp.exists()) await temp.delete(recursive: true);
    } on Object {
      // Windows may still hold the log file open.
    }
  });

  Future<void> pump(WidgetTester tester) async {
    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: theme,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            theme.colorScheme,
            scale: 1.0,
            controlScale: AppTypographyScale.standard.multiplier,
          ),
          child: DebugLogPage(appDataRoot: temp.path),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts with the switch off and says nothing was written',
      (t) async {
    await pump(t);

    final toggle = t.widget<Switch>(
      find.byKey(AppKeys.debugLogEnableSwitch),
    );
    expect(toggle.value, isFalse);
    // The empty state has to explain *why* it is empty, or an opt-in default
    // reads as a broken viewer.
    expect(find.textContaining('File logging is off'), findsOneWidget);
  });

  testWidgets('reflects an already-enabled preference', (t) async {
    SharedPreferences.setMockInitialValues({
      'teampilot.debug_file_logging.v1': true,
    });
    await pump(t);

    expect(
      t.widget<Switch>(find.byKey(AppKeys.debugLogEnableSwitch)).value,
      isTrue,
    );
  });

  testWidgets('persists the switch so the next launch honours it', (t) async {
    // main() reads this key before runApp; if the tap did not persist, the
    // setting would silently revert on restart.
    await pump(t);
    await t.tap(find.byKey(AppKeys.debugLogEnableSwitch));
    await t.pumpAndSettle();

    expect(
      DebugLogSettings.read(await SharedPreferences.getInstance()),
      isTrue,
    );
  });

  testWidgets('copy is disabled while there is nothing to copy', (t) async {
    // Copy-to-clipboard is the only way the log leaves an Android device, so an
    // enabled-looking button that copies an empty string would be a trap.
    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pump(t);
    await t.tap(find.byKey(AppKeys.debugLogCopyButton));
    await t.pumpAndSettle();

    expect(
      calls.where((c) => c.method == 'Clipboard.setData'),
      isEmpty,
    );
  });
}
