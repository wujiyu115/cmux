import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/color_theme.dart';
import 'package:teampilot/theme/terminal/cmux_terminal_theme.dart';
import 'package:teampilot/theme/terminal_derived_scheme.dart';
import 'package:teampilot/widgets/settings/color_theme_picker.dart';

Widget _wrap(ColorThemePicker picker) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: TpTheme(
        data: TpThemeData.fromColorScheme(
          ColorScheme.fromSeed(seedColor: const Color(0xFFD4A06A)),
          scale: 1.0,
        ),
        child: SingleChildScrollView(child: picker),
      ),
    ),
  );
}

void main() {
  testWidgets('lists interface themes per brightness and terminal groups', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      _wrap(
        ColorThemePicker(selectedId: 'ui:amber:light', onSelect: (_) {}),
      ),
    );
    await tester.pump();

    expect(find.text(l10n.colorThemeGroupUiLight), findsOneWidget);
    expect(find.text(l10n.colorThemeGroupUiDark), findsOneWidget);
    expect(find.text(l10n.colorThemeGroupTerminalDark), findsOneWidget);
    expect(find.text(l10n.colorThemeGroupTerminalLight), findsOneWidget);
    // Every fixed palette appears once per brightness group (5 × 2).
    expect(find.text('Amber'), findsNWidgets(2));
    expect(find.text('Forest'), findsNWidgets(2));
    // Terminal catalog themes are listed.
    expect(find.text('Dracula'), findsOneWidget);
  });

  testWidgets('tapping a row emits its unified theme id', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(
      _wrap(
        ColorThemePicker(
          selectedId: 'ui:amber:light',
          onSelect: selected.add,
        ),
      ),
    );
    await tester.pump();

    // Interface row: the dark Amber row carries the :dark-suffixed id.
    final amberRows = find.text('Amber');
    await tester.tap(amberRows.last);
    await tester.pump();
    expect(selected, ['ui:amber:dark']);
    expect(uiColorThemeBrightness(selected.single), Brightness.dark);

    // Terminal row: id is the catalog slug, no ui: prefix.
    await tester.ensureVisible(find.text('Dracula'));
    await tester.tap(find.text('Dracula'));
    await tester.pump();
    expect(selected, ['ui:amber:dark', 'dracula']);
    expect(isUiColorTheme(selected.last), isFalse);
    expect(terminalModeForColorTheme(selected.last), 'dracula');
  });

  testWidgets('imported themes get their own group and delete affordance', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final imported = CmuxTerminalTheme(
      name: 'My Theme',
      author: 'me',
      isDark: true,
      background: const Color(0xFF101010),
      foreground: const Color(0xFFE0E0E0),
      cursor: const Color(0xFFE0E0E0),
      selection: const Color(0xFF444444),
      searchHit: const Color(0xFFE0B000),
      searchHitCurrent: const Color(0xFF00B0E0),
      searchHitFg: const Color(0xFF101010),
      ansi: List<Color>.filled(16, const Color(0xFF808080)),
    );
    CmuxTerminalTheme? deleted;
    await tester.pumpWidget(
      _wrap(
        ColorThemePicker(
          selectedId: 'ui:amber:light',
          importedThemes: [imported],
          onDeleteImported: (t) => deleted = t,
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(l10n.colorThemeGroupImported), findsOneWidget);
    await tester.ensureVisible(find.text('My Theme'));
    expect(find.text('My Theme'), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.terminalThemeDeleteTooltip));
    await tester.pump();
    expect(deleted, isNotNull);
    expect(deleted!.id, imported.id);
  });

  testWidgets('all fixed presets render both brightness ids', (tester) async {
    // Guard the id scheme the prefs migration writes: every preset id in
    // kThemeColorPresetIds (minus `terminal`) must produce parseable ui ids.
    for (final preset in kThemeColorPresetIds) {
      if (preset == kTerminalDerivedPresetId) continue;
      for (final brightness in Brightness.values) {
        final id = uiColorThemeId(preset, brightness);
        expect(isUiColorTheme(id), isTrue, reason: id);
        expect(uiColorThemePreset(id), preset);
        expect(uiColorThemeBrightness(id), brightness);
        expect(terminalModeForColorTheme(id), 'adaptive');
      }
    }
  });
}
