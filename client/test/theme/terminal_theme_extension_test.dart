import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/theme/terminal/cmux_terminal_theme.dart';
import 'package:teampilot/theme/terminal_derived_scheme.dart';

CmuxTerminalTheme _darkTheme() => CmuxTerminalTheme(
  name: 'Test dark',
  author: 'Test',
  isDark: true,
  background: const Color(0xFF101216),
  foreground: const Color(0xFFD0D4DC),
  cursor: const Color(0xFFD0D4DC),
  selection: const Color(0xFF334455),
  searchHit: const Color(0xFF556677),
  searchHitCurrent: const Color(0xFF778899),
  searchHitFg: const Color(0xFF101216),
  ansi: [for (var i = 0; i < 16; i++) Color(0xFF000000 | i << 8 | 0x80)],
);

void main() {
  test('terminal-derived theme carries the TerminalThemeExtension', () {
    final theme = _darkTheme();
    final dark = buildDarkTheme(
      kTerminalDerivedPresetId,
      AppTypographyScale.standard,
      null,
      null,
      theme,
    );
    expect(dark.extension<TerminalThemeExtension>()?.theme, same(theme));
  });

  test('luminance mismatch falls back and carries no extension', () {
    final theme = _darkTheme();
    // Dark terminal theme in the light slot: only accents are borrowed.
    final light = buildLightTheme(
      kTerminalDerivedPresetId,
      AppTypographyScale.standard,
      null,
      null,
      theme,
    );
    expect(light.extension<TerminalThemeExtension>(), isNull);
  });

  test('fixed presets never carry the extension', () {
    final theme = _darkTheme();
    final amber = buildDarkTheme(
      'amber',
      AppTypographyScale.standard,
      null,
      null,
      theme,
    );
    expect(amber.extension<TerminalThemeExtension>(), isNull);
  });

  test('extension copyWith and lerp keep the type contract', () {
    final theme = _darkTheme();
    final ext = TerminalThemeExtension(theme);
    expect(ext.copyWith().theme, same(theme));
    expect(ext.lerp(null, 0.9), same(ext));
  });
}
