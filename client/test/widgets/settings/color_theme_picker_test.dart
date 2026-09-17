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

CmuxTerminalTheme _importedTheme({required bool light}) => CmuxTerminalTheme(
  name: light ? 'My Light' : 'My Dark',
  author: 'me',
  isDark: !light,
  background: light ? const Color(0xFFF0F0F0) : const Color(0xFF101010),
  foreground: light ? const Color(0xFF202020) : const Color(0xFFE0E0E0),
  cursor: light ? const Color(0xFF202020) : const Color(0xFFE0E0E0),
  selection: const Color(0xFF444444),
  searchHit: const Color(0xFFE0B000),
  searchHitCurrent: const Color(0xFF00B0E0),
  searchHitFg: const Color(0xFF101010),
  ansi: List<Color>.filled(16, const Color(0xFF808080)),
);

void main() {
  testWidgets('light slot offers one merged group of light themes only', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      _wrap(
        ColorThemePicker(
          selectedId: 'ui:amber:light',
          brightness: Brightness.light,
          importedThemes: [
            _importedTheme(light: true),
            _importedTheme(light: false),
          ],
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pump();

    // One merged group per brightness; the dark group is absent.
    expect(find.text(l10n.colorThemeGroupLight), findsOneWidget);
    expect(find.text(l10n.colorThemeGroupDark), findsNothing);
    // Dark catalog themes are filtered out.
    expect(find.text('Dracula'), findsNothing);
    expect(find.text('Solarized Light'), findsOneWidget);
    // Imported themes filtered by luminance.
    expect(find.text('My Light'), findsOneWidget);
    expect(find.text('My Dark'), findsNothing);
  });

  testWidgets('dark slot offers one merged group of dark themes only', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      _wrap(
        ColorThemePicker(
          selectedId: 'ui:amber:dark',
          brightness: Brightness.dark,
          importedThemes: [
            _importedTheme(light: true),
            _importedTheme(light: false),
          ],
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(l10n.colorThemeGroupDark), findsOneWidget);
    expect(find.text(l10n.colorThemeGroupLight), findsNothing);
    expect(find.text('Dracula'), findsOneWidget);
    expect(find.text('Solarized Light'), findsNothing);
    expect(find.text('My Dark'), findsOneWidget);
    expect(find.text('My Light'), findsNothing);
  });

  testWidgets('tapping a row emits its unified theme id', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(
      _wrap(
        ColorThemePicker(
          selectedId: 'ui:amber:dark',
          brightness: Brightness.dark,
          onSelect: selected.add,
        ),
      ),
    );
    await tester.pump();

    // Interface row in the dark slot carries the :dark-suffixed id.
    await tester.tap(find.text('Amber'));
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

  testWidgets('imported themes get a delete affordance', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final imported = _importedTheme(light: false);
    CmuxTerminalTheme? deleted;
    await tester.pumpWidget(
      _wrap(
        ColorThemePicker(
          selectedId: 'ui:amber:dark',
          brightness: Brightness.dark,
          importedThemes: [imported],
          onDeleteImported: (t) => deleted = t,
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(l10n.colorThemeGroupImported), findsNothing);
    await tester.ensureVisible(find.text('My Dark'));
    expect(find.text('My Dark'), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.terminalThemeDeleteTooltip));
    await tester.pump();
    expect(deleted, isNotNull);
    expect(deleted!.id, imported.id);
  });

  test('all fixed presets render both brightness ids', () {
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
