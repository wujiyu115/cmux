import 'package:flutter_alacritty/flutter_alacritty.dart';

/// Canonical vocabulary of terminal colour override slot keys.
///
/// This is the single source of truth for [LayoutPreferences.terminalColorOverrides]
/// keys, the per-slot editor grid, and the JSON sanitizer. Values persisted under
/// unknown keys are dropped on load (see `layout_preferences.dart`).
///
/// The 8 semantic slots mirror [CmuxTerminalTheme]'s fields; `ansi0..ansi15` map
/// to the 16-entry ANSI palette (0..7 normal, 8..15 bright).
const List<String> kTerminalColorSlots = <String>[
  'background',
  'foreground',
  'cursor',
  'selection',
  'searchHit',
  'searchHitCurrent',
  'searchHitFg',
  'accent',
  'ansi0',
  'ansi1',
  'ansi2',
  'ansi3',
  'ansi4',
  'ansi5',
  'ansi6',
  'ansi7',
  'ansi8',
  'ansi9',
  'ansi10',
  'ansi11',
  'ansi12',
  'ansi13',
  'ansi14',
  'ansi15',
];

/// The 8 non-ANSI (semantic) override slots.
const List<String> kTerminalSemanticColorSlots = <String>[
  'background',
  'foreground',
  'cursor',
  'selection',
  'searchHit',
  'searchHitCurrent',
  'searchHitFg',
  'accent',
];

/// Whether [slot] is a known override key.
bool isTerminalColorSlot(String slot) => kTerminalColorSlots.contains(slot);

/// Forces an override value to an opaque ARGB int (alpha `0xFF`), keeping only
/// the low 24 RGB bits. Mirrors the model sanitizer so a hand-edited prefs file
/// can never poison rendering with a transparent slot.
int normalizeTerminalColorValue(int argb) => 0xFF000000 | (argb & 0xFFFFFF);

/// Base (pre-override) slot values for the currently-resolved terminal theme.
///
/// Returned as opaque ARGB ints so the per-slot editor can seed swatches from
/// any mode (catalog theme or the legacy adaptive/classicDark/highContrast
/// branches) uniformly: effective = `overrides[slot] ?? base[slot]`.
Map<String, int> terminalThemeSlotValues(TerminalTheme theme) {
  final values = <String, int>{
    'background': 0xFF000000 | theme.background,
    'foreground': 0xFF000000 | theme.foreground,
    // cursorColor null == inverse video; show the foreground as its swatch.
    'cursor': 0xFF000000 | (theme.cursorColor ?? theme.foreground),
    'selection': 0xFF000000 | theme.selection,
    'searchHit': 0xFF000000 | theme.searchMatch.bg,
    'searchHitCurrent': 0xFF000000 | theme.searchFocused.bg,
    'searchHitFg': 0xFF000000 | theme.searchMatch.fg,
    'accent': 0xFF000000 | theme.hintStart.bg,
  };
  for (var i = 0; i < theme.ansi.length; i++) {
    values['ansi$i'] = 0xFF000000 | theme.ansi[i];
  }
  return values;
}

/// Parses a hex colour string, mirroring cmux `TerminalThemes.TryParseHexColor`
/// (`TerminalThemes.cs:59`). Accepts `#RRGGBB` / `RRGGBB` and `#AARRGGBB` /
/// `AARRGGBB` (a missing leading `#` is tolerated); the alpha component is
/// ignored and the result is always opaque (alpha forced `0xFF`).
///
/// Returns `null` for empty / wrong-length / non-hex input.
int? parseTerminalHexColor(String? value) {
  if (value == null) return null;
  var text = value.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('#')) text = text.substring(1);
  final String rgbHex;
  if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(text)) {
    rgbHex = text;
  } else if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(text)) {
    rgbHex = text.substring(2); // drop the AA (alpha) component
  } else {
    return null;
  }
  return 0xFF000000 | int.parse(rgbHex, radix: 16);
}

/// Formats an ARGB [value] as an uppercase `#RRGGBB` string (alpha dropped).
String formatTerminalHexColor(int value) {
  final rgb = (value & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0');
  return '#$rgb';
}
