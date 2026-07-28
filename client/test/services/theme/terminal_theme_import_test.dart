import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/theme/terminal_theme_import.dart';

/// Alacritty theme with every slot present. Exercises a `'#RRGGBB'` quoted
/// value, a `"0xRRGGBB"` value, a bare `RRGGBB` value, and inline `#` comments.
const _alacritty = '''
# Sample Alacritty colours
[colors.primary]
background = '#1d1f21'
foreground = "0xc5c8c6"   # inline comment kept out of the value

[colors.cursor]
cursor = "#ffffff"
text   = "#1d1f21"

[colors.selection]
background = "373b41"

[colors.normal]
black   = '#282a2e'
red     = '#a54242'
green   = '#8c9440'
yellow  = '#de935f'
blue    = '#5f819d'
magenta = '#85678f'
cyan    = '#5e8d87'
white   = '#707880'

[colors.bright]
black   = '#373b41'
red     = '#cc6666'
green   = '#b5bd68'
yellow  = '#f0c674'
blue    = '#81a2be'
magenta = '#b294bb'
cyan    = '#8abeb7'
white   = '#c5c8c6'

[colors.search.matches]
background = '#f0c674'
foreground = '#1d1f21'

[colors.search.focused_match]
background = '#b5bd68'
''';

/// Ghostty theme with only background/foreground and the 8 normal palette
/// entries, so cursor/selection/search and all bright ANSI must be derived.
/// Includes a full-line `#` comment, an inline-`#` value, and a bare-hex
/// `palette = 2=RRGGBB` / `3=RRGGBB` line.
const _ghostty = '''
# Ghostty theme file
background = 1d1f21
foreground = #c5c8c6

palette = 0=#282a2e
palette = 1=#a54242
palette = 2=8c9440
palette = 3=de935f
palette = 4=#5f819d
palette = 5=#85678f
palette = 6=#5e8d87
palette = 7=#707880
''';

void main() {
  group('detectTerminalThemeFormat', () {
    test('detects Alacritty via [colors.*] tables', () {
      expect(
        detectTerminalThemeFormat(_alacritty),
        TerminalThemeFormat.alacrittyToml,
      );
    });

    test('detects Ghostty via palette / bare background', () {
      expect(
        detectTerminalThemeFormat(_ghostty),
        TerminalThemeFormat.ghosttyKeyValue,
      );
      expect(
        detectTerminalThemeFormat('background = 111111\nforeground = eeeeee'),
        TerminalThemeFormat.ghosttyKeyValue,
      );
    });

    test('returns null for junk', () {
      expect(detectTerminalThemeFormat('hello world\nnot a theme'), isNull);
      expect(detectTerminalThemeFormat(''), isNull);
    });
  });

  group('importTerminalTheme — Alacritty', () {
    test('parses every slot with no derivation warnings', () {
      final result = importTerminalTheme(_alacritty, nameHint: 'my-theme');
      expect(result.error, isNull);
      expect(result.warnings, isEmpty);

      final theme = result.theme!;
      expect(theme.name, 'my-theme');
      expect(theme.background.toARGB32(), 0xFF1D1F21);
      // "0xc5c8c6" -> 0x prefix stripped, inline comment dropped.
      expect(theme.foreground.toARGB32(), 0xFFC5C8C6);
      expect(theme.cursor.toARGB32(), 0xFFFFFFFF);
      // bare RRGGBB.
      expect(theme.selection.toARGB32(), 0xFF373B41);
      expect(theme.searchHit.toARGB32(), 0xFFF0C674);
      expect(theme.searchHitCurrent.toARGB32(), 0xFFB5BD68);
      expect(theme.searchHitFg.toARGB32(), 0xFF1D1F21);

      // All 16 ANSI parsed exactly (0..7 normal, 8..15 bright).
      const expectedAnsi = <int>[
        0xFF282A2E, 0xFFA54242, 0xFF8C9440, 0xFFDE935F,
        0xFF5F819D, 0xFF85678F, 0xFF5E8D87, 0xFF707880,
        0xFF373B41, 0xFFCC6666, 0xFFB5BD68, 0xFFF0C674,
        0xFF81A2BE, 0xFFB294BB, 0xFF8ABEB7, 0xFFC5C8C6,
      ];
      expect(theme.ansi.map((c) => c.toARGB32()).toList(), expectedAnsi);
    });

    test('isDark follows background luminance (dark background)', () {
      final theme = importTerminalTheme(_alacritty).theme!;
      expect(theme.isDark, isTrue);
      expect(theme.isDark, !theme.isLightByLuminance);
    });

    test('light background yields a light theme regardless of the file', () {
      const lightSrc = '''
[colors.primary]
background = "#f5f5f5"
foreground = "#000000"
[colors.normal]
black   = "#000000"
red     = "#800000"
green   = "#008000"
yellow  = "#808000"
blue    = "#000080"
magenta = "#800080"
cyan    = "#008080"
white   = "#c0c0c0"
''';
      final theme = importTerminalTheme(lightSrc).theme!;
      expect(theme.isDark, isFalse);
      expect(theme.isDark, !theme.isLightByLuminance);
    });
  });

  group('importTerminalTheme — Ghostty', () {
    test('derives missing slots and lists them as warnings', () {
      final result = importTerminalTheme(_ghostty, nameHint: 'ghost');
      expect(result.error, isNull);

      // Canonical-ordered warnings: semantic slots then ansi8..15.
      expect(result.warnings, <String>[
        'cursor',
        'selection',
        'searchHit',
        'searchHitCurrent',
        'searchHitFg',
        'ansi8',
        'ansi9',
        'ansi10',
        'ansi11',
        'ansi12',
        'ansi13',
        'ansi14',
        'ansi15',
      ]);

      final theme = result.theme!;
      expect(theme.name, 'ghost');
      // Non-arithmetic derivations assert exactly.
      expect(theme.cursor.toARGB32(), 0xFFC5C8C6); // <- foreground
      expect(theme.searchHit.toARGB32(), 0xFFDE935F); // <- ansi3 (yellow)
      expect(theme.searchHitCurrent.toARGB32(), 0xFF8C9440); // <- ansi2 (green)
      expect(theme.searchHitFg.toARGB32(), 0xFF1D1F21); // <- background

      // ansi2 / ansi3 came from bare-hex palette lines.
      expect(theme.ansi[2].toARGB32(), 0xFF8C9440);
      expect(theme.ansi[3].toARGB32(), 0xFFDE935F);

      // selection is a blend of bg and fg: each channel lies between them.
      final sel = theme.selection.toARGB32();
      for (final shift in <int>[16, 8, 0]) {
        final s = (sel >> shift) & 0xFF;
        final bg = (0x1D1F21 >> shift) & 0xFF;
        final fg = (0xC5C8C6 >> shift) & 0xFF;
        expect(s, greaterThanOrEqualTo(bg));
        expect(s, lessThanOrEqualTo(fg));
      }

      // Derived bright ANSI are lightened: never darker than the normal one.
      for (var i = 8; i < 16; i++) {
        final bright = theme.ansi[i].toARGB32();
        final normal = theme.ansi[i - 8].toARGB32();
        for (final shift in <int>[16, 8, 0]) {
          expect((bright >> shift) & 0xFF,
              greaterThanOrEqualTo((normal >> shift) & 0xFF));
        }
      }
    });

    test('falls back to the literal name when no hint is given', () {
      final theme = importTerminalTheme(_ghostty).theme!;
      expect(theme.name, 'Imported theme');
    });
  });

  group('importTerminalTheme — fatal errors', () {
    test('unrecognized format', () {
      final result = importTerminalTheme('total garbage\n123');
      expect(result.theme, isNull);
      expect(result.error, 'unrecognized-format');
    });

    test('missing background is fatal', () {
      const src = '''
foreground = #c5c8c6
palette = 0=#282a2e
palette = 1=#a54242
palette = 2=#8c9440
palette = 3=#de935f
palette = 4=#5f819d
palette = 5=#85678f
palette = 6=#5e8d87
palette = 7=#707880
''';
      final result = importTerminalTheme(src);
      expect(result.error, 'missing-background');
    });

    test('fewer than 8 normal ANSI is fatal', () {
      const src = '''
background = 1d1f21
foreground = #c5c8c6
palette = 0=#282a2e
palette = 1=#a54242
palette = 2=#8c9440
palette = 3=#de935f
palette = 4=#5f819d
palette = 5=#85678f
palette = 6=#5e8d87
''';
      final result = importTerminalTheme(src);
      expect(result.error, 'insufficient-ansi');
    });
  });
}
