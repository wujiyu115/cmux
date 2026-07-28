import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/terminal/cmux_terminal_theme.dart';
import 'package:teampilot/theme/terminal/terminal_color_slots.dart';
import 'package:teampilot/theme/terminal/terminal_theme_catalog.g.dart';

CmuxTerminalTheme _dracula() => cmuxTerminalThemeById('dracula')!;

void main() {
  group('applyTerminalColorOverrides', () {
    test('empty map is the identity', () {
      final base = _dracula();
      expect(identical(applyTerminalColorOverrides(base, const {}), base), true);
    });

    test('overrides each semantic slot (alpha forced opaque)', () {
      final base = _dracula();
      final out = applyTerminalColorOverrides(base, const {
        'background': 0x00112233,
        'foreground': 0xFF445566,
        'cursor': 0xFF778899,
        'selection': 0xFFAABBCC,
        'searchHit': 0xFFDDEEFF,
        'searchHitCurrent': 0xFF010203,
        'searchHitFg': 0xFF040506,
      });
      expect(out.background, const Color(0xFF112233));
      expect(out.foreground, const Color(0xFF445566));
      expect(out.cursor, const Color(0xFF778899));
      expect(out.selection, const Color(0xFFAABBCC));
      expect(out.searchHit, const Color(0xFFDDEEFF));
      expect(out.searchHitCurrent, const Color(0xFF010203));
      expect(out.searchHitFg, const Color(0xFF040506));
      // Untouched fields are preserved.
      expect(out.name, base.name);
      expect(out.ansi, base.ansi);
    });

    test('overrides individual ansi slots', () {
      final base = _dracula();
      final out = applyTerminalColorOverrides(base, const {
        'ansi0': 0xFF000001,
        'ansi15': 0xFF0000FF,
      });
      expect(out.ansi[0], const Color(0xFF000001));
      expect(out.ansi[15], const Color(0xFF0000FF));
      expect(out.ansi[1], base.ansi[1]);
    });

    test('accent override sets accent; removing key restores base (null)', () {
      final base = _dracula();
      expect(base.accent, isNull);
      final withAccent = applyTerminalColorOverrides(base, const {
        'accent': 0xFF123456,
      });
      expect(withAccent.accent, const Color(0xFF123456));
      // No accent key → base accent (null) unchanged.
      final backToBase = applyTerminalColorOverrides(base, const {
        'background': 0xFF000000,
      });
      expect(backToBase.accent, isNull);
    });

    test('unknown keys are ignored', () {
      final base = _dracula();
      final out = applyTerminalColorOverrides(base, const {
        'bogus': 0xFFFFFFFF,
        'ansi99': 0xFFFFFFFF,
      });
      expect(out.background, base.background);
      expect(out.ansi, base.ansi);
    });
  });

  group('parseTerminalHexColor', () {
    test('#RRGGBB', () {
      expect(parseTerminalHexColor('#123456'), 0xFF123456);
    });
    test('missing # is tolerated', () {
      expect(parseTerminalHexColor('123456'), 0xFF123456);
    });
    test('#AARRGGBB drops alpha, forces opaque', () {
      expect(parseTerminalHexColor('#8012ABEF'), 0xFF12ABEF);
      expect(parseTerminalHexColor('AABBCCDD'), 0xFFBBCCDD);
    });
    test('wrong length → null', () {
      expect(parseTerminalHexColor('#12345'), isNull);
      expect(parseTerminalHexColor('#1234567'), isNull);
    });
    test('non-hex → null', () {
      expect(parseTerminalHexColor('#12345G'), isNull);
      expect(parseTerminalHexColor('#-01234'), isNull);
      expect(parseTerminalHexColor('nothex!'), isNull);
    });
    test('empty / whitespace / null → null', () {
      expect(parseTerminalHexColor(''), isNull);
      expect(parseTerminalHexColor('   '), isNull);
      expect(parseTerminalHexColor(null), isNull);
    });
    test('case-insensitive and trimmed', () {
      expect(parseTerminalHexColor('  #abCDef '), 0xFFABCDEF);
    });
  });

  group('formatTerminalHexColor', () {
    test('drops alpha and uppercases with padding', () {
      expect(formatTerminalHexColor(0xFF0A0B0C), '#0A0B0C');
      expect(formatTerminalHexColor(0x00000001), '#000001');
    });
  });
}
