/// Flutter-free parser for cmux's `docs/analysis/09-themes.md` theme reference.
///
/// This file deliberately imports nothing from `package:flutter` (no `Color`,
/// no `dart:ui`) so that `tool/gen_terminal_themes.dart` can `dart run` it
/// standalone. Colours are carried as packed `0xRRGGBB` ints; the generator
/// emits `Color(0xFF..)` literals into `terminal_theme_catalog.g.dart`, and the
/// runtime model (`CmuxTerminalTheme`) holds real [Color]s.
///
/// The parser is strict per theme: a theme that does not yield exactly 16 ANSI
/// colours, or contains an unparseable hex, throws a [FormatException] naming
/// the offending theme. The 23 / 12-dark / 11-light total is a separate
/// concern — see [validateCmuxThemeCatalog].
library;

/// Plain, Flutter-free description of one parsed theme.
class CmuxThemeSpec {
  const CmuxThemeSpec({
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
    required this.accent,
    required this.ansi,
  });

  final String name;
  final String author;
  final bool isDark;

  /// Packed `0xRRGGBB` colour slots.
  final int background;
  final int foreground;
  final int cursor;
  final int selection;
  final int searchHit;
  final int searchHitCurrent;
  final int searchHitFg;

  /// `null` when the source accent cell is `—`.
  final int? accent;

  /// Exactly 16 packed `0xRRGGBB` ANSI colours.
  final List<int> ansi;
}

final RegExp _themeHeader = RegExp(r'^###\s+(.+?)（作者：(.+?)；');
final RegExp _hexCell = RegExp(r'^#[0-9A-Fa-f]{6}$');

/// Parses the whole markdown document into per-theme specs, in document order.
///
/// Dark/light grouping is taken from the `## 三、深色组` / `## 四、浅色组`
/// section headers (an independent source from the luminance rule, so the two
/// can be cross-checked). Throws [FormatException] on any malformed theme.
List<CmuxThemeSpec> parseCmuxThemesMarkdown(String markdown) {
  final specs = <CmuxThemeSpec>[];
  final lines = markdown.split('\n');

  bool? sectionIsDark;
  String? pendingName;
  String? pendingAuthor;
  final pendingRows = <List<String>>[];

  void finalizePending() {
    if (pendingName == null) return;
    final name = pendingName!;
    if (sectionIsDark == null) {
      throw FormatException(
        'Theme "$name" appears before any 深色组/浅色组 section header.',
      );
    }
    specs.add(_buildSpec(name, pendingAuthor ?? '', sectionIsDark, pendingRows));
    pendingName = null;
    pendingAuthor = null;
    pendingRows.clear();
  }

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.startsWith('## ')) {
      finalizePending();
      if (line.contains('深色')) {
        sectionIsDark = true;
      } else if (line.contains('浅色')) {
        sectionIsDark = false;
      }
      continue;
    }
    final header = _themeHeader.firstMatch(line);
    if (header != null) {
      finalizePending();
      pendingName = header.group(1)!.trim();
      pendingAuthor = header.group(2)!.trim();
      continue;
    }
    if (pendingName != null && line.startsWith('|')) {
      final cells = _cells(line);
      // Data rows are the ones whose first cell is a hex colour; header and
      // separator rows (背景/black/**br.black**/---) are skipped.
      if (cells.isNotEmpty && _hexCell.hasMatch(cells.first)) {
        pendingRows.add(cells);
      }
    }
  }
  finalizePending();

  return specs;
}

/// Validates the catalog totals cmux ships: exactly 23 themes, 12 dark + 11
/// light, with unique names. Throws [FormatException] otherwise. Kept separate
/// from [parseCmuxThemesMarkdown] so a small fixture can exercise per-theme
/// strictness without tripping the 23-count check.
void validateCmuxThemeCatalog(List<CmuxThemeSpec> specs) {
  final dark = specs.where((s) => s.isDark).length;
  final light = specs.length - dark;
  if (specs.length != 23 || dark != 12 || light != 11) {
    throw FormatException(
      'Expected 23 themes (12 dark + 11 light) but parsed '
      '${specs.length} ($dark dark + $light light).',
    );
  }
  final names = <String>{};
  for (final spec in specs) {
    if (!names.add(spec.name)) {
      throw FormatException('Duplicate theme name "${spec.name}".');
    }
  }
}

List<String> _cells(String row) {
  var trimmed = row.trim();
  if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
  if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);
  return trimmed.split('|').map((c) => c.trim()).toList();
}

CmuxThemeSpec _buildSpec(
  String name,
  String author,
  bool isDark,
  List<List<String>> rows,
) {
  if (rows.length != 3) {
    throw FormatException(
      'Theme "$name": expected 3 data rows (slots, ANSI, bright ANSI) but '
      'found ${rows.length}.',
    );
  }
  final slots = rows[0];
  if (slots.length != 8) {
    throw FormatException(
      'Theme "$name": slot row must have 8 cells, found ${slots.length}.',
    );
  }
  final normal = rows[1];
  final bright = rows[2];
  if (normal.length != 8 || bright.length != 8) {
    throw FormatException(
      'Theme "$name": ANSI rows must have 8 cells each, found '
      '${normal.length}/${bright.length}.',
    );
  }
  final ansi = <int>[
    for (final cell in normal) _hex(name, cell),
    for (final cell in bright) _hex(name, cell),
  ];
  if (ansi.length != 16) {
    throw FormatException(
      'Theme "$name": expected 16 ANSI colours, got ${ansi.length}.',
    );
  }
  return CmuxThemeSpec(
    name: name,
    author: author,
    isDark: isDark,
    background: _hex(name, slots[0]),
    foreground: _hex(name, slots[1]),
    cursor: _hex(name, slots[2]),
    selection: _hex(name, slots[3]),
    searchHit: _hex(name, slots[4]),
    searchHitCurrent: _hex(name, slots[5]),
    searchHitFg: _hex(name, slots[6]),
    accent: _optionalHex(name, slots[7]),
    ansi: ansi,
  );
}

int _hex(String theme, String cell) {
  if (!_hexCell.hasMatch(cell)) {
    throw FormatException('Theme "$theme": invalid hex colour "$cell".');
  }
  return int.parse(cell.substring(1), radix: 16);
}

int? _optionalHex(String theme, String cell) {
  if (cell == '—' || cell == '-') return null;
  return _hex(theme, cell);
}
