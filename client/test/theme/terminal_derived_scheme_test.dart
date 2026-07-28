import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/theme/terminal/cmux_terminal_theme.dart';
import 'package:teampilot/theme/terminal/terminal_theme_catalog.g.dart';
import 'package:teampilot/theme/terminal_derived_scheme.dart';

/// Minimal theme builder so accent-pick cases can vary one slot at a time.
CmuxTerminalTheme _theme({
  Color background = const Color(0xFF101820),
  Color foreground = const Color(0xFFD0D4DC),
  Color cursor = const Color(0xFF9AA0A8),
  Color? accent,
}) => CmuxTerminalTheme(
  name: 'Fixture',
  author: '',
  isDark: true,
  background: background,
  foreground: foreground,
  cursor: cursor,
  selection: const Color(0xFF334455),
  searchHit: const Color(0xFFFFFF2B),
  searchHitCurrent: const Color(0xFF31FF26),
  searchHitFg: const Color(0xFF000000),
  accent: accent,
  ansi: const [
    Color(0xFF101820),
    Color(0xFFD04A62), // 1 error
    Color(0xFF52C07E), // 2 success
    Color(0xFFD4B85A), // 3 warning
    Color(0xFF5298D8), // 4 blue (accent fallback)
    Color(0xFFB87CD8), // 5 purple
    Color(0xFF4EB8C4), // 6 teal
    Color(0xFFD0D4DC),
    Color(0xFF5A5A5A),
    Color(0xFFE86A7E),
    Color(0xFF6CD898),
    Color(0xFFE8CC70),
    Color(0xFF72B0E8),
    Color(0xFFD098F0),
    Color(0xFF72D0DC),
    Color(0xFFE4E6EC),
  ],
);

void main() {
  group('accent pick (AppThemeService.PickAccent)', () {
    test('explicit accent wins', () {
      const accent = Color(0xFFFF8800);
      expect(pickTerminalAccent(_theme(accent: accent)), accent);
    });

    test('cursor is the accent when it is distinct from the foreground', () {
      const cursor = Color(0xFF9AA0A8);
      expect(pickTerminalAccent(_theme(cursor: cursor)), cursor);
    });

    test('cursor within distance 30 of the foreground falls back to ansi4', () {
      // #D0D4DC vs #D2D4DC -> distance 2, below the 30 threshold.
      final theme = _theme(cursor: const Color(0xFFD2D4DC));
      expect(pickTerminalAccent(theme), const Color(0xFF5298D8));
    });
  });

  group('colour maths', () {
    test('luminance uses cmux 8-bit perceived weights', () {
      expect(
        terminalPerceivedLuminance(const Color(0xFFFFFFFF)),
        closeTo(255, 0.001),
      );
      expect(terminalPerceivedLuminance(const Color(0xFF000000)), 0);
      // 0.587 * 255
      expect(
        terminalPerceivedLuminance(const Color(0xFF00FF00)),
        closeTo(149.685, 0.001),
      );
    });

    test('darken / lighten / blend match the WPF channel maths', () {
      expect(
        darkenTerminalColor(const Color(0xFF646464), 0.5),
        const Color(0xFF323232),
      );
      expect(
        lightenTerminalColor(const Color(0xFF000000), 0.5),
        const Color(0xFF7F7F7F),
      );
      expect(
        blendTerminalColor(
          const Color(0xFF000000),
          const Color(0xFFFFFFFF),
          0.25,
        ),
        const Color(0xFF3F3F3F),
      );
    });

    test('accent foreground flips at luminance 140', () {
      expect(terminalOnColor(const Color(0xFFFFFFFF)), const Color(0xFF1A1A1A));
      expect(terminalOnColor(const Color(0xFF101820)), const Color(0xFFFFFFFF));
    });
  });

  group('terminalDerivedColorScheme', () {
    test('dark theme keeps the terminal surfaces and text verbatim', () {
      final theme = _theme();
      final scheme = terminalDerivedColorScheme(theme);

      expect(scheme.brightness, Brightness.dark);
      expect(scheme.surface, theme.background);
      expect(scheme.onSurface, theme.foreground);
      // fgDim = Blend(fg, bg, 0.55)
      expect(
        scheme.onSurfaceVariant,
        blendTerminalColor(theme.foreground, theme.background, 0.55),
      );
    });

    test('semantic roles come from the ANSI palette', () {
      final theme = _theme();
      final scheme = terminalDerivedColorScheme(theme);

      expect(scheme.error, theme.ansi[1]);
      expect(scheme.secondary, theme.ansi[6]);
      expect(scheme.tertiary, theme.ansi[5]);
      expect(scheme.primary, pickTerminalAccent(theme));
      expect(scheme.onPrimary, terminalOnColor(pickTerminalAccent(theme)));
    });

    test('surface ladder steps away from the background in both modes', () {
      final dark = terminalDerivedColorScheme(_theme());
      expect(
        terminalPerceivedLuminance(dark.surfaceContainerHigh),
        greaterThan(terminalPerceivedLuminance(dark.surface)),
      );

      final light = terminalDerivedColorScheme(
        _theme(
          background: const Color(0xFFFDF6E3),
          foreground: const Color(0xFF073642),
          cursor: const Color(0xFF268BD2),
        ),
      );
      expect(light.brightness, Brightness.light);
      expect(
        terminalPerceivedLuminance(light.surfaceContainerHigh),
        lessThan(terminalPerceivedLuminance(light.surface)),
      );
    });

    test('brightness follows perceived luminance, not the isDark flag', () {
      // Light background but the catalog flag claims dark.
      final scheme = terminalDerivedColorScheme(
        _theme(background: const Color(0xFFFFFFFF)),
      );
      expect(scheme.brightness, Brightness.light);
    });
  });

  group('preset id and resolution', () {
    test('terminal preset is a persisted preset id', () {
      expect(kThemeColorPresetIds, contains(kTerminalDerivedPresetId));
      expect(normalizeThemeColorPreset(kTerminalDerivedPresetId),
          kTerminalDerivedPresetId);
    });

    test('catalog ids resolve; legacy modes do not', () {
      expect(cmuxTerminalThemeForMode('dracula')?.name, 'Dracula');
      // Tolerated display-name match.
      expect(cmuxTerminalThemeForMode('Solarized Light')?.id, 'solarized-light');
      expect(cmuxTerminalThemeForMode('adaptive'), isNull);
      expect(cmuxTerminalThemeForMode('classicDark'), isNull);
      expect(cmuxTerminalThemeForMode('highContrast'), isNull);
    });

    test('overrides only apply when custom colours are enabled', () {
      const overrides = {'background': 0xFF010203};
      expect(
        resolveUiTerminalTheme(mode: 'dracula', colorOverrides: overrides)
            ?.background,
        cmuxTerminalThemeById('dracula')!.background,
      );
      expect(
        resolveUiTerminalTheme(
          mode: 'dracula',
          useCustomColors: true,
          colorOverrides: overrides,
        )?.background,
        const Color(0xFF010203),
      );
    });

    test('cache key changes with mode and with override values only', () {
      int key(String mode, bool custom, Map<String, int> overrides) =>
          uiTerminalThemeCacheKey(
            mode: mode,
            useCustomColors: custom,
            colorOverrides: overrides,
          );

      expect(key('dracula', false, const {}), key('dracula', false, const {}));
      expect(key('dracula', false, const {}), isNot(key('nord', false, const {})));
      // Disabled custom colours ignore the map entirely.
      expect(
        key('dracula', false, const {'background': 1}),
        key('dracula', false, const {}),
      );
      // Same entries in a different insertion order hash the same.
      expect(
        key('dracula', true, const {'background': 1, 'foreground': 2}),
        key('dracula', true, const {'foreground': 2, 'background': 1}),
      );
      expect(
        key('dracula', true, const {'background': 1}),
        isNot(key('dracula', true, const {'background': 2})),
      );
    });
  });

  group('buildLightTheme / buildDarkTheme with the terminal preset', () {
    test('matching brightness uses the terminal surfaces exactly', () {
      final dracula = cmuxTerminalThemeById('dracula')!;
      final theme = buildDarkTheme(
        kTerminalDerivedPresetId,
        AppTypographyScale.standard,
        null,
        null,
        dracula,
      );

      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.colorScheme.surface, dracula.background);
      // Foreground is not softened on this path — it is already the terminal's.
      expect(theme.colorScheme.onSurface, dracula.foreground);
      expect(theme.scaffoldBackgroundColor, dracula.background);
      expect(theme.colorScheme.primary, pickTerminalAccent(dracula));
    });

    test('light theme derives from a light terminal theme', () {
      final light = cmuxTerminalThemeById('solarized-light')!;
      final theme = buildLightTheme(
        kTerminalDerivedPresetId,
        AppTypographyScale.standard,
        null,
        null,
        light,
      );

      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.colorScheme.surface, light.background);
    });

    test('brightness mismatch keeps a readable blended scheme', () {
      // A dark terminal theme must not paint the light [ThemeData] slot.
      final dracula = cmuxTerminalThemeById('dracula')!;
      final theme = buildLightTheme(
        kTerminalDerivedPresetId,
        AppTypographyScale.standard,
        null,
        null,
        dracula,
      );

      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.colorScheme.surface, isNot(dracula.background));
      expect(
        terminalPerceivedLuminance(theme.colorScheme.surface),
        greaterThan(128),
      );
    });

    test('legacy terminal modes fall back to the default palette', () {
      // `terminalTheme` is null for adaptive / classicDark / highContrast.
      final fallback = buildDarkTheme(kTerminalDerivedPresetId);
      final amber = buildDarkTheme(kDefaultThemeColorPreset);
      expect(fallback.colorScheme.primary, amber.colorScheme.primary);
    });

    test('the five fixed presets are unaffected by a terminal theme', () {
      final dracula = cmuxTerminalThemeById('dracula')!;
      final withTheme = buildDarkTheme(
        'ocean',
        AppTypographyScale.standard,
        null,
        null,
        dracula,
      );
      final without = buildDarkTheme('ocean');
      expect(withTheme.colorScheme.primary, without.colorScheme.primary);
      expect(withTheme.colorScheme.surface, without.colorScheme.surface);
    });

    test('swatches preview the terminal accent and background', () {
      final dracula = cmuxTerminalThemeById('dracula')!;
      expect(
        themePresetSwatchPrimary(kTerminalDerivedPresetId, dracula),
        pickTerminalAccent(dracula),
      );
      expect(
        themePresetSwatchSecondary(kTerminalDerivedPresetId, dracula),
        dracula.background,
      );
      // No terminal theme -> default palette, never a crash.
      expect(themePresetSwatchPrimary(kTerminalDerivedPresetId), isA<Color>());
    });
  });
}
