import 'package:flutter/painting.dart' show Color;
import 'package:flutter_alacritty/flutter_alacritty.dart';

/// A single built-in terminal theme ported from cmux's `TerminalThemes.cs`.
///
/// Colours are Flutter [Color]s (fully opaque). The generated catalog
/// (`terminal_theme_catalog.g.dart`) is a `const List<CmuxTerminalTheme>` so
/// there is zero runtime parse/load cost — see `tool/gen_terminal_themes.dart`.
///
/// Docs: `D:/git/cmux-windows/docs/analysis/09-themes.md` (§一 documents the
/// colour slots and the light/dark luminance rule).
class CmuxTerminalTheme {
  const CmuxTerminalTheme({
    required this.name,
    required this.author,
    required this.isDark,
    required this.background,
    required this.foreground,
    required this.cursor,
    required this.selection,
    required this.searchHit,
    required this.searchHitCurrent,
    required this.searchHitFg,
    this.accent,
    required this.ansi,
  });

  /// Display name, e.g. `'Dracula'`.
  final String name;

  /// Attribution string from the source theme, e.g. `'Zeno Rocha'`.
  final String author;

  /// Whether the theme is in cmux's dark group (12 themes) vs light (11).
  ///
  /// Must always agree with [isLightByLuminance] (asserted in tests) — a later
  /// task derives the whole UI scheme from the luminance rule.
  final bool isDark;

  final Color background;
  final Color foreground;
  final Color cursor;
  final Color selection;
  final Color searchHit;
  final Color searchHitCurrent;
  final Color searchHitFg;

  /// Optional accent (`—`/null in the source means "no explicit accent").
  final Color? accent;

  /// Exactly 16 ANSI palette colours: 0..7 normal, 8..15 bright.
  final List<Color> ansi;

  /// Stable kebab-case slug of [name] (`'Solarized Dark'` → `'solarized-dark'`).
  ///
  /// This is the persisted identifier (`LayoutPreferences.terminalThemeMode`),
  /// so it must stay stable across regenerations.
  String get id => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// cmux's light/dark rule (`AppThemeService.cs:222`): perceived luminance of
  /// the background `0.299R + 0.587G + 0.114B > 128` ⇒ light.
  bool get isLightByLuminance {
    final argb = background.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return (0.299 * r + 0.587 * g + 0.114 * b) > 128;
  }

  /// Maps this catalog theme onto the engine's [TerminalTheme].
  ///
  /// cmux has no `hintStart` / `bellOverlay` / `cursorText` slots, so — like the
  /// fixed-palette branches in `terminal_theme_mapper.dart` — the hint start is
  /// derived from the theme's accent (falling back to the cursor colour) painted
  /// over the background, `cursorText` stays inverse (`null`), and `bellOverlay`
  /// is the shared `0xFFFFFF`.
  TerminalTheme toTerminalTheme() {
    final hintBg = accent ?? cursor;
    return TerminalTheme(
      background: _pack(background),
      foreground: _pack(foreground),
      selection: _pack(selection),
      ansi: <int>[for (final color in ansi) _pack(color)],
      searchMatch: (bg: _pack(searchHit), fg: _pack(searchHitFg)),
      searchFocused: (bg: _pack(searchHitCurrent), fg: _pack(searchHitFg)),
      hintStart: (bg: _pack(hintBg), fg: _pack(background)),
      cursorText: null,
      cursorColor: _pack(cursor),
      bellOverlay: 0xFFFFFF,
    );
  }

  static int _pack(Color color) => color.toARGB32() & 0xFFFFFF;
}

/// Returns a copy of [base] with per-slot custom colours from [overrides] applied.
///
/// Keys are the canonical slot names (`kTerminalColorSlots`): the 8 semantic
/// slots plus `ansi0..ansi15`. Values are ARGB ints; the alpha is ignored and
/// forced opaque so a stray transparent value can't blank the terminal. Unknown
/// keys are ignored and an empty map is the identity (returns [base] unchanged).
///
/// Pure — no I/O, safe to unit test. Wired into `terminal_theme_mapper.dart` so
/// that when custom colours are enabled the effective theme carries the tweaks.
CmuxTerminalTheme applyTerminalColorOverrides(
  CmuxTerminalTheme base,
  Map<String, int> overrides,
) {
  if (overrides.isEmpty) return base;

  Color pick(String slot, Color current) {
    final value = overrides[slot];
    return value == null ? current : Color(0xFF000000 | (value & 0xFFFFFF));
  }

  final ansi = <Color>[
    for (var i = 0; i < base.ansi.length; i++) pick('ansi$i', base.ansi[i]),
  ];

  final accent = overrides.containsKey('accent')
      ? Color(0xFF000000 | (overrides['accent']! & 0xFFFFFF))
      : base.accent;

  return CmuxTerminalTheme(
    name: base.name,
    author: base.author,
    isDark: base.isDark,
    background: pick('background', base.background),
    foreground: pick('foreground', base.foreground),
    cursor: pick('cursor', base.cursor),
    selection: pick('selection', base.selection),
    searchHit: pick('searchHit', base.searchHit),
    searchHitCurrent: pick('searchHitCurrent', base.searchHitCurrent),
    searchHitFg: pick('searchHitFg', base.searchHitFg),
    accent: accent,
    ansi: ansi,
  );
}
