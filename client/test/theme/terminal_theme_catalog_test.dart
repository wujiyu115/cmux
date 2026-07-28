import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/terminal/terminal_theme_catalog.g.dart';

void main() {
  test('catalog has exactly 23 themes, 12 dark + 11 light', () {
    expect(kCmuxTerminalThemes.length, 23);
    expect(kCmuxTerminalThemes.where((t) => t.isDark).length, 12);
    expect(kCmuxTerminalThemes.where((t) => !t.isDark).length, 11);
  });

  test('every theme has exactly 16 fully-opaque ANSI colours', () {
    for (final theme in kCmuxTerminalThemes) {
      expect(theme.ansi.length, 16, reason: theme.name);
      for (final color in theme.ansi) {
        expect(color.toARGB32() >> 24 & 0xFF, 0xFF, reason: theme.name);
      }
    }
  });

  test('every colour slot is fully opaque (alpha 0xFF)', () {
    for (final theme in kCmuxTerminalThemes) {
      final slots = <int>[
        theme.background.toARGB32(),
        theme.foreground.toARGB32(),
        theme.cursor.toARGB32(),
        theme.selection.toARGB32(),
        theme.searchHit.toARGB32(),
        theme.searchHitCurrent.toARGB32(),
        theme.searchHitFg.toARGB32(),
        if (theme.accent != null) theme.accent!.toARGB32(),
      ];
      for (final argb in slots) {
        expect((argb >> 24) & 0xFF, 0xFF, reason: theme.name);
      }
    }
  });

  test('ids are unique and stable kebab-case', () {
    final ids = <String>{};
    final kebab = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
    for (final theme in kCmuxTerminalThemes) {
      expect(kebab.hasMatch(theme.id), isTrue, reason: '${theme.name} -> ${theme.id}');
      expect(ids.add(theme.id), isTrue, reason: 'duplicate id ${theme.id}');
    }
    // Spot-check the exact slugs a persisted preference would store.
    expect(cmuxTerminalThemeById('solarized-dark')?.name, 'Solarized Dark');
    expect(cmuxTerminalThemeById('catppuccin-mocha')?.name, 'Catppuccin Mocha');
    expect(cmuxTerminalThemeById('default-dark')?.name, 'Default Dark');
  });

  test('isDark agrees with the luminance rule for all 23 themes', () {
    for (final theme in kCmuxTerminalThemes) {
      expect(
        theme.isDark,
        !theme.isLightByLuminance,
        reason: '${theme.name} isDark/luminance disagree',
      );
    }
  });

  test('cmuxTerminalThemeById round-trips every id and rejects junk', () {
    for (final theme in kCmuxTerminalThemes) {
      expect(cmuxTerminalThemeById(theme.id), same(theme), reason: theme.id);
    }
    expect(cmuxTerminalThemeById('not-a-real-theme'), isNull);
    expect(cmuxTerminalThemeById(''), isNull);
  });

  test('spot-checked hex values match the source doc', () {
    final dracula = cmuxTerminalThemeById('dracula')!;
    expect(dracula.author, 'Zeno Rocha');
    expect(dracula.isDark, isTrue);
    expect(dracula.background.toARGB32(), 0xFF282A36);
    expect(dracula.foreground.toARGB32(), 0xFFF8F8F2);
    expect(dracula.ansi[0].toARGB32(), 0xFF21222C); // black
    expect(dracula.ansi[15].toARGB32(), 0xFFFFFFFF); // br.white
    expect(dracula.accent, isNull);

    final solarizedLight = cmuxTerminalThemeById('solarized-light')!;
    expect(solarizedLight.isDark, isFalse);
    expect(solarizedLight.background.toARGB32(), 0xFFB1AC9F);
    expect(solarizedLight.foreground.toARGB32(), 0xFF657B83);
    expect(solarizedLight.ansi[4].toARGB32(), 0xFF268BD2); // blue

    final nord = cmuxTerminalThemeById('nord')!;
    expect(nord.accent?.toARGB32(), 0xFF88C0D0); // explicit accent
  });

  test('toTerminalTheme maps cmux slots onto the engine theme', () {
    final dracula = cmuxTerminalThemeById('dracula')!;
    final engine = dracula.toTerminalTheme();
    expect(engine.background, 0x282A36);
    expect(engine.foreground, 0xF8F8F2);
    expect(engine.cursorColor, 0xF8F8F2);
    expect(engine.selection, 0x645484);
    expect(engine.ansi.length, 16);
    expect(engine.ansi[1], 0xFF5555);
    // searchMatch = SearchHitBg + SearchHitFg; searchFocused = SearchHitBgCurrent.
    expect(engine.searchMatch, (bg: 0xF1FA8C, fg: 0x282A36));
    expect(engine.searchFocused, (bg: 0x50FA7B, fg: 0x282A36));
    expect(engine.cursorText, isNull);
    expect(engine.bellOverlay, 0xFFFFFF);
    // No cmux accent -> hint bg falls back to cursor, fg = background.
    expect(engine.hintStart, (bg: 0xF8F8F2, fg: 0x282A36));
  });
}
