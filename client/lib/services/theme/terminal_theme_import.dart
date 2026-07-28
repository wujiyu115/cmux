import 'package:flutter/painting.dart' show Color;

import '../../theme/terminal/cmux_terminal_theme.dart';
import '../../theme/terminal/terminal_color_slots.dart';

/// External terminal-theme file formats this importer understands.
enum TerminalThemeFormat {
  /// Alacritty `alacritty.toml` colour tables (`[colors.*]`).
  alacrittyToml,

  /// Ghostty `key = value` config (`background = …`, `palette = N=…`).
  ghosttyKeyValue,
}

/// Outcome of [importTerminalTheme].
///
/// Exactly one of [theme] / [error] is meaningful: on success [theme] is set and
/// [error] is null; on failure [theme] is null and [error] holds a fatal code.
/// [warnings] is always present (possibly empty).
///
/// ## Code vocabulary (machine-readable, not prose)
///
/// The UI layer maps these to localized strings; they are intentionally stable
/// identifiers, never end-user text.
///
/// Fatal [error] codes:
/// - `unrecognized-format` — neither format could be detected and none was forced.
/// - `missing-background` — no parseable `background` colour.
/// - `missing-foreground` — no parseable `foreground` colour.
/// - `insufficient-ansi` — fewer than 8 of the normal ANSI colours (ansi0..7)
///   were present, so the file is not a usable palette.
///
/// [warnings] entries are the canonical slot names (see [kTerminalColorSlots])
/// of every slot that was **derived** rather than read from the file:
/// `cursor`, `selection`, `searchHit`, `searchHitCurrent`, `searchHitFg`, and
/// any of `ansi8`..`ansi15`. They are emitted in that canonical order.
class TerminalThemeImportResult {
  const TerminalThemeImportResult({this.theme, this.warnings = const [], this.error});

  const TerminalThemeImportResult.failure(String this.error)
    : theme = null,
      warnings = const [];

  /// Parsed theme, or null when [error] is set.
  final CmuxTerminalTheme? theme;

  /// Canonical slot names that were derived rather than parsed. Never null.
  final List<String> warnings;

  /// Fatal error code, or null on success.
  final String? error;

  bool get isSuccess => theme != null;
}

/// Sniffs which [TerminalThemeFormat] [source] is, or null if neither.
///
/// Rules (per the import spec):
/// - a `[colors.` (or `[colors]`) table present ⇒ [TerminalThemeFormat.alacrittyToml];
/// - a `palette =` line, or a `background =` line with no `[section]` header at
///   all ⇒ [TerminalThemeFormat.ghosttyKeyValue];
/// - otherwise null.
TerminalThemeFormat? detectTerminalThemeFormat(String source) {
  var hasColorsTable = false;
  var hasSectionHeader = false;
  var hasPalette = false;
  var hasBackgroundKv = false;

  for (final rawLine in source.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('[')) {
      hasSectionHeader = true;
      if (line.startsWith('[colors.') || line == '[colors]') {
        hasColorsTable = true;
      }
      continue;
    }
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final key = line.substring(0, eq).trim();
    if (key == 'palette') hasPalette = true;
    if (key == 'background') hasBackgroundKv = true;
  }

  if (hasColorsTable) return TerminalThemeFormat.alacrittyToml;
  if (hasPalette) return TerminalThemeFormat.ghosttyKeyValue;
  if (hasBackgroundKv && !hasSectionHeader) {
    return TerminalThemeFormat.ghosttyKeyValue;
  }
  return null;
}

/// Parses an external terminal theme file.
///
/// [nameHint] (typically the file stem) supplies the theme name; neither format
/// carries a name, so the fallback is the literal `'Imported theme'`. [format]
/// forces a parser; when omitted it is sniffed via [detectTerminalThemeFormat].
TerminalThemeImportResult importTerminalTheme(
  String source, {
  String? nameHint,
  TerminalThemeFormat? format,
}) {
  final resolved = format ?? detectTerminalThemeFormat(source);
  if (resolved == null) {
    return const TerminalThemeImportResult.failure('unrecognized-format');
  }
  final parsed = switch (resolved) {
    TerminalThemeFormat.alacrittyToml => _parseAlacritty(source),
    TerminalThemeFormat.ghosttyKeyValue => _parseGhostty(source),
  };
  return _buildTheme(parsed, nameHint: nameHint);
}

// ---------------------------------------------------------------------------
// Intermediate representation
// ---------------------------------------------------------------------------

/// Raw colours pulled from a file, before derivation. Each slot is a parsed
/// opaque ARGB int or null when absent/unparseable. [ansi] is length 16.
class _ParsedColors {
  _ParsedColors();

  int? background;
  int? foreground;
  int? cursor;
  int? selection;
  int? searchHit;
  int? searchHitCurrent;
  int? searchHitFg;
  final List<int?> ansi = List<int?>.filled(16, null);
}

// ---------------------------------------------------------------------------
// Theme assembly + derivation
// ---------------------------------------------------------------------------

TerminalThemeImportResult _buildTheme(
  _ParsedColors parsed, {
  required String? nameHint,
}) {
  final bg = parsed.background;
  if (bg == null) {
    return const TerminalThemeImportResult.failure('missing-background');
  }
  final fg = parsed.foreground;
  if (fg == null) {
    return const TerminalThemeImportResult.failure('missing-foreground');
  }
  final normalPresent = parsed.ansi.take(8).where((c) => c != null).length;
  if (normalPresent < 8) {
    return const TerminalThemeImportResult.failure('insufficient-ansi');
  }

  final warnings = <String>[];
  final background = Color(bg);
  final foreground = Color(fg);

  // ansi0..7 are all present (guaranteed above). ansi8..15 that are missing are
  // derived from their normal counterpart lightened toward white.
  final ansi = <Color>[for (final c in parsed.ansi.take(8)) Color(c!)];
  for (var i = 8; i < 16; i++) {
    final present = parsed.ansi[i];
    if (present != null) {
      ansi.add(Color(present));
    } else {
      ansi.add(_lighten(ansi[i - 8], _brightLighten));
      warnings.add('ansi$i');
    }
  }

  // cursor ← foreground.
  Color cursor;
  if (parsed.cursor != null) {
    cursor = Color(parsed.cursor!);
  } else {
    cursor = foreground;
    warnings.add('cursor');
  }

  // selection ← midpoint blend of background and foreground.
  Color selection;
  if (parsed.selection != null) {
    selection = Color(parsed.selection!);
  } else {
    selection = _blend(background, foreground, 0.5);
    warnings.add('selection');
  }

  // searchHit ← ANSI yellow (ansi3).
  Color searchHit;
  if (parsed.searchHit != null) {
    searchHit = Color(parsed.searchHit!);
  } else {
    searchHit = ansi[3];
    warnings.add('searchHit');
  }

  // searchHitCurrent ← ANSI green (ansi2).
  Color searchHitCurrent;
  if (parsed.searchHitCurrent != null) {
    searchHitCurrent = Color(parsed.searchHitCurrent!);
  } else {
    searchHitCurrent = ansi[2];
    warnings.add('searchHitCurrent');
  }

  // searchHitFg ← background.
  Color searchHitFg;
  if (parsed.searchHitFg != null) {
    searchHitFg = Color(parsed.searchHitFg!);
  } else {
    searchHitFg = background;
    warnings.add('searchHitFg');
  }

  // Sort warnings into canonical slot order for a stable, testable list.
  warnings.sort((a, b) => _slotRank(a).compareTo(_slotRank(b)));

  final name = (nameHint != null && nameHint.trim().isNotEmpty)
      ? nameHint.trim()
      : 'Imported theme';

  // isDark is ALWAYS the luminance rule on the parsed background, never a value
  // from the file. Build a probe to reuse [CmuxTerminalTheme.isLightByLuminance]
  // verbatim, then rebuild with the resolved flag.
  final probe = CmuxTerminalTheme(
    name: name,
    author: '',
    isDark: false,
    background: background,
    foreground: foreground,
    cursor: cursor,
    selection: selection,
    searchHit: searchHit,
    searchHitCurrent: searchHitCurrent,
    searchHitFg: searchHitFg,
    ansi: ansi,
  );
  final theme = CmuxTerminalTheme(
    name: name,
    author: '',
    isDark: !probe.isLightByLuminance,
    background: background,
    foreground: foreground,
    cursor: cursor,
    selection: selection,
    searchHit: searchHit,
    searchHitCurrent: searchHitCurrent,
    searchHitFg: searchHitFg,
    ansi: ansi,
  );

  return TerminalThemeImportResult(theme: theme, warnings: warnings);
}

/// Fraction each missing bright ANSI colour is mixed toward white (`0..1`).
/// `ansi{n+8} = ansi{n} + (255 - ansi{n}) * _brightLighten` per channel.
const double _brightLighten = 0.3;

int _rank(String slot) => kTerminalColorSlots.indexOf(slot);

int _slotRank(String slot) {
  final index = _rank(slot);
  return index < 0 ? kTerminalColorSlots.length : index;
}

int _channel(Color c, int shift) => (c.toARGB32() >> shift) & 0xFF;

Color _rgb(int r, int g, int b) =>
    Color(0xFF000000 | (r << 16) | (g << 8) | b);

/// Linear blend of [a] and [b] per RGB channel; [t]=0 is [a], [t]=1 is [b].
Color _blend(Color a, Color b, double t) {
  int mix(int shift) {
    final x = _channel(a, shift);
    final y = _channel(b, shift);
    return (x + (y - x) * t).round().clamp(0, 255);
  }

  return _rgb(mix(16), mix(8), mix(0));
}

/// Lightens [c] by moving each channel [amount] of the way toward 255.
Color _lighten(Color c, double amount) {
  int up(int shift) {
    final v = _channel(c, shift);
    return (v + (255 - v) * amount).round().clamp(0, 255);
  }

  return _rgb(up(16), up(8), up(0));
}

// ---------------------------------------------------------------------------
// Alacritty TOML (focused reader — not a general TOML parser)
// ---------------------------------------------------------------------------

const Map<String, int> _ansiKeyToIndex = <String, int>{
  'black': 0,
  'red': 1,
  'green': 2,
  'yellow': 3,
  'blue': 4,
  'magenta': 5,
  'cyan': 6,
  'white': 7,
};

_ParsedColors _parseAlacritty(String source) {
  final out = _ParsedColors();
  // section -> { key -> raw value string }
  final tables = <String, Map<String, String>>{};
  var section = '';

  for (final rawLine in source.split('\n')) {
    final line = _stripTomlComment(rawLine).trim();
    if (line.isEmpty) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      section = line.substring(1, line.length - 1).trim();
      continue;
    }
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final key = line.substring(0, eq).trim();
    final value = _unquote(line.substring(eq + 1).trim());
    (tables[section] ??= <String, String>{})[key] = value;
  }

  int? colour(String sectionName, String key) =>
      parseTerminalHexColor(tables[sectionName]?[key]);

  out.background = colour('colors.primary', 'background');
  out.foreground = colour('colors.primary', 'foreground');
  out.cursor = colour('colors.cursor', 'cursor');
  out.selection = colour('colors.selection', 'background');

  _ansiKeyToIndex.forEach((key, index) {
    out.ansi[index] = colour('colors.normal', key);
    out.ansi[index + 8] = colour('colors.bright', key);
  });

  out.searchHit = colour('colors.search.matches', 'background');
  out.searchHitCurrent = colour('colors.search.focused_match', 'background');
  out.searchHitFg = colour('colors.search.matches', 'foreground');

  return out;
}

/// Removes a trailing `#` comment from a TOML [line], honouring single and
/// double quotes so a `'#RRGGBB'` value survives.
String _stripTomlComment(String line) {
  var inSingle = false;
  var inDouble = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == "'" && !inDouble) {
      inSingle = !inSingle;
    } else if (ch == '"' && !inSingle) {
      inDouble = !inDouble;
    } else if (ch == '#' && !inSingle && !inDouble) {
      return line.substring(0, i);
    }
  }
  return line;
}

/// Strips one layer of matching single or double quotes from [value].
String _unquote(String value) {
  if (value.length >= 2) {
    final first = value[0];
    final last = value[value.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}

// ---------------------------------------------------------------------------
// Ghostty key = value
// ---------------------------------------------------------------------------

_ParsedColors _parseGhostty(String source) {
  final out = _ParsedColors();

  for (final rawLine in source.split('\n')) {
    final trimmed = rawLine.trim();
    // Ghostty treats `#` as a comment only at line start; an inline `#` (e.g.
    // `background = #1d1f21`) is part of the value.
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final eq = trimmed.indexOf('=');
    if (eq < 0) continue;
    final key = trimmed.substring(0, eq).trim();
    final value = trimmed.substring(eq + 1).trim();

    switch (key) {
      case 'background':
        out.background = parseTerminalHexColor(value);
      case 'foreground':
        out.foreground = parseTerminalHexColor(value);
      case 'cursor-color':
        out.cursor = parseTerminalHexColor(value);
      case 'selection-background':
        out.selection = parseTerminalHexColor(value);
      case 'selection-foreground':
        // Not a CmuxTerminalTheme slot; parsed for completeness, then ignored.
        break;
      case 'palette':
        final innerEq = value.indexOf('=');
        if (innerEq < 0) break;
        final index = int.tryParse(value.substring(0, innerEq).trim());
        if (index == null || index < 0 || index > 15) break;
        out.ansi[index] = parseTerminalHexColor(value.substring(innerEq + 1));
    }
  }

  return out;
}
