import 'package:flutter/painting.dart' show Color;
import 'package:flutter_alacritty/flutter_alacritty.dart';

import 'terminal_color_slots.dart';

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
    String? id,
  }) : _idOverride = id;

  /// Explicit persisted id, used by user-imported themes whose on-disk filename
  /// (and hence id) may carry a collision-avoidance suffix (`dracula-2`) that no
  /// longer matches the [name] slug. `null` for the built-in catalog, where [id]
  /// is derived from [name].
  final String? _idOverride;

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

  /// Stable kebab-case slug of [name] (`'Solarized Dark'` → `'solarized-dark'`),
  /// unless an explicit [_idOverride] was supplied (user-imported themes).
  ///
  /// This is the persisted identifier (`LayoutPreferences.terminalThemeMode`),
  /// so it must stay stable across regenerations.
  String get id => _idOverride ?? slugForName(name);

  /// Derives the stable kebab-case id from a display [name]. Exposed so
  /// repositories can compute a base id before a theme instance exists.
  static String slugForName(String name) => name
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

  /// Serializes to a JSON map for the user-theme repository. Colours are stored
  /// as `#RRGGBB` strings (see [formatTerminalHexColor]); [id] is persisted so a
  /// collision-suffixed id survives a round-trip even though it no longer
  /// matches the [name] slug.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'author': author,
    'isDark': isDark,
    'background': formatTerminalHexColor(background.toARGB32()),
    'foreground': formatTerminalHexColor(foreground.toARGB32()),
    'cursor': formatTerminalHexColor(cursor.toARGB32()),
    'selection': formatTerminalHexColor(selection.toARGB32()),
    'searchHit': formatTerminalHexColor(searchHit.toARGB32()),
    'searchHitCurrent': formatTerminalHexColor(searchHitCurrent.toARGB32()),
    'searchHitFg': formatTerminalHexColor(searchHitFg.toARGB32()),
    if (accent != null) 'accent': formatTerminalHexColor(accent!.toARGB32()),
    'ansi': <String>[
      for (final color in ansi) formatTerminalHexColor(color.toARGB32()),
    ],
  };

  /// Reconstructs a theme from [toJson]. Throws [FormatException] when a
  /// required colour is missing or malformed, or when [ansi] is not 16 entries,
  /// so the [VersionedJsonStore] can quarantine the offending file rather than
  /// surface a half-decoded theme.
  factory CmuxTerminalTheme.fromJson(Map<String, dynamic> json) {
    Color colour(String key) {
      final parsed = parseTerminalHexColor(json[key] as String?);
      if (parsed == null) {
        throw FormatException('missing or malformed colour "$key"');
      }
      return Color(parsed);
    }

    final rawAnsi = json['ansi'];
    if (rawAnsi is! List || rawAnsi.length != 16) {
      throw const FormatException('ansi must be a 16-entry list');
    }
    final ansi = <Color>[
      for (final entry in rawAnsi)
        Color(
          parseTerminalHexColor(entry is String ? entry : null) ??
              (throw const FormatException('malformed ansi colour')),
        ),
    ];

    final accentRaw = parseTerminalHexColor(json['accent'] as String?);
    final idRaw = json['id'];
    return CmuxTerminalTheme(
      id: idRaw is String && idRaw.isNotEmpty ? idRaw : null,
      name: (json['name'] as String?) ?? 'Imported theme',
      author: (json['author'] as String?) ?? '',
      isDark: json['isDark'] as bool? ?? false,
      background: colour('background'),
      foreground: colour('foreground'),
      cursor: colour('cursor'),
      selection: colour('selection'),
      searchHit: colour('searchHit'),
      searchHitCurrent: colour('searchHitCurrent'),
      searchHitFg: colour('searchHitFg'),
      accent: accentRaw == null ? null : Color(accentRaw),
      ansi: ansi,
    );
  }
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
