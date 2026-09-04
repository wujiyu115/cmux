import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor_platform/editor_syntax_theme.dart';
import 'package:teampilot/theme/terminal/cmux_terminal_theme.dart';

void main() {
  test('falls back from keyword.control to keyword', () {
    final theme = EditorSyntaxTheme.atomOneDark();
    expect(theme.styleFor('keyword.control'), isNotNull);
    expect(theme.styleFor('keyword.control'), theme.styleFor('keyword'));
  });

  test('unknown scope resolves to null', () {
    final theme = EditorSyntaxTheme.atomOneDark();
    expect(theme.styleFor('totally.unknown.scope'), isNull);
  });

  test('exact match is preferred over a parent scope', () {
    final theme = EditorSyntaxTheme.atomOneDark();
    final stringStyle = theme.styleFor('string');
    final escapeStyle = theme.styleFor('string.escape');
    expect(escapeStyle, isNotNull);
    expect(escapeStyle, isNot(equals(stringStyle)));
  });

  test('atomOneDark and atomOneLight factories exist and differ', () {
    final dark = EditorSyntaxTheme.atomOneDark();
    final light = EditorSyntaxTheme.atomOneLight();
    expect(
      dark.styleFor('keyword')?.color,
      isNot(equals(light.styleFor('keyword')?.color)),
    );
  });

  test('forBrightness picks dark for Brightness.dark and light otherwise', () {
    final dark = EditorSyntaxTheme.forBrightness(Brightness.dark);
    final light = EditorSyntaxTheme.forBrightness(Brightness.light);
    expect(
      dark.styleFor('keyword')?.color,
      EditorSyntaxTheme.atomOneDark().styleFor('keyword')?.color,
    );
    expect(
      light.styleFor('keyword')?.color,
      EditorSyntaxTheme.atomOneLight().styleFor('keyword')?.color,
    );
  });

  test('asStyleMap exposes an unmodifiable snapshot of scope styles', () {
    final theme = EditorSyntaxTheme.atomOneDark();
    final map = theme.asStyleMap();
    expect(map['keyword'], theme.styleFor('keyword'));
    expect(() => map['keyword'] = const TextStyle(), throwsUnsupportedError);
  });

  test('nested fallback walks multiple dotted levels', () {
    final theme = EditorSyntaxTheme.atomOneDark();
    expect(
      theme.styleFor('variable.parameter.builtin'),
      theme.styleFor('variable.parameter'),
    );
  });

  group('fromTerminalTheme', () {
    const background = Color(0xFF101216);
    const foreground = Color(0xFFD0D4DC);

    List<Color> distinctAnsi() => [
      for (var i = 0; i < 16; i++)
        Color(0xFF000000 | (0x10 + i * 0x10) << 16 | i << 8 | 0x80),
    ];

    CmuxTerminalTheme terminalTheme({List<Color>? ansi}) {
      return CmuxTerminalTheme(
        name: 'Test theme',
        author: 'Test',
        isDark: true,
        background: background,
        foreground: foreground,
        cursor: foreground,
        selection: const Color(0xFF334455),
        searchHit: const Color(0xFF556677),
        searchHitCurrent: const Color(0xFF778899),
        searchHitFg: background,
        ansi: ansi ?? distinctAnsi(),
      );
    }

    Color blendColors(Color a, Color b) {
      int mix(int x, int y) => (x + (y - x) * 0.5).toInt();
      return Color(
        0xFF000000 |
            mix((a.toARGB32() >> 16) & 0xFF, (b.toARGB32() >> 16) & 0xFF) <<
                16 |
            mix((a.toARGB32() >> 8) & 0xFF, (b.toARGB32() >> 8) & 0xFF) << 8 |
            mix(a.toARGB32() & 0xFF, b.toARGB32() & 0xFF),
      );
    }

    test('maps scopes onto the ANSI palette', () {
      final ansi = distinctAnsi();
      final theme = EditorSyntaxTheme.fromTerminalTheme(terminalTheme());

      Color? colorOf(String scope) => theme.styleFor(scope)?.color;
      expect(colorOf('keyword'), ansi[5]);
      expect(colorOf('string'), ansi[2]);
      expect(colorOf('string.escape'), ansi[6]);
      expect(colorOf('number'), ansi[3]);
      expect(colorOf('constant'), ansi[6]);
      expect(colorOf('property'), ansi[3]);
      expect(colorOf('variable.builtin'), ansi[3]);
      expect(colorOf('function'), ansi[4]);
      expect(colorOf('function.builtin'), ansi[3]);
      expect(colorOf('constructor'), ansi[3]);
      expect(colorOf('type'), ansi[6]);
      expect(colorOf('type.builtin'), ansi[3]);
      expect(colorOf('tag'), ansi[1]);
      expect(colorOf('tag.attribute'), ansi[2]);
      expect(colorOf('attribute'), ansi[2]);
      expect(colorOf('label'), ansi[1]);
      expect(colorOf('operator'), foreground);
      expect(colorOf('variable'), foreground);
      expect(colorOf('variable.parameter'), foreground);
      expect(colorOf('punctuation'), foreground);
    });

    test('comment is the foreground dimmed toward the background, italic', () {
      final theme = EditorSyntaxTheme.fromTerminalTheme(terminalTheme());
      final comment = theme.styleFor('comment');
      expect(comment?.fontStyle, FontStyle.italic);
      expect(comment?.color, isNot(anyOf(foreground, background)));
    });

    test('emphasis and strong stay style-only', () {
      final theme = EditorSyntaxTheme.fromTerminalTheme(terminalTheme());
      expect(theme.styleFor('emphasis')?.color, isNull);
      expect(theme.styleFor('strong')?.color, isNull);
      expect(theme.styleFor('strong')?.fontWeight, FontWeight.bold);
    });

    test('covers exactly the atom-one scope set', () {
      final derived = EditorSyntaxTheme.fromTerminalTheme(
        terminalTheme(),
      ).asStyleMap();
      expect(
        derived.keys.toSet(),
        EditorSyntaxTheme.atomOneDark().asStyleMap().keys.toSet(),
      );
    });

    test('a slot equal to the background is nudged toward the foreground', () {
      // ansi2 == background: too close to read; the guard must move it.
      final ansi = distinctAnsi()..[2] = background;
      final theme = EditorSyntaxTheme.fromTerminalTheme(
        terminalTheme(ansi: ansi),
      );
      final string = theme.styleFor('string')!.color!;
      expect(string, isNot(background));
      expect(string, isNot(ansi[2]));
      // Half-blend of background toward foreground still clears the floor.
      expect(string, blendColors(background, foreground));
    });

    test(
      'a slot still unreadable after the nudge falls back to foreground',
      () {
        // Background and foreground nearly equal: even the nudged blend is
        // unreadable, so the scope must paint plain foreground.
        final ansi = distinctAnsi()..[2] = const Color(0xFF14161A);
        final theme = EditorSyntaxTheme.fromTerminalTheme(
          CmuxTerminalTheme(
            name: 'Low contrast',
            author: 'Test',
            isDark: true,
            background: const Color(0xFF101216),
            foreground: const Color(0xFF15181C),
            cursor: const Color(0xFF15181C),
            selection: const Color(0xFF334455),
            searchHit: const Color(0xFF556677),
            searchHitCurrent: const Color(0xFF778899),
            searchHitFg: const Color(0xFF101216),
            ansi: ansi,
          ),
        );
        expect(theme.styleFor('string')?.color, const Color(0xFF15181C));
      },
    );
  });
}
