import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:teampilot/services/editor/file_editor_theme.dart';
import 'package:teampilot/services/editor_platform/editor_syntax_theme.dart';
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
  // Readable slots (distance from the background well above the guard floor).
  ansi: [
    for (var i = 0; i < 16; i++)
      Color(0xFF000000 | (0x10 + i * 0x10) << 16 | i << 8 | 0x80),
  ],
);

Future<CodeEditorStyle> _pumpStyle(WidgetTester tester, ThemeData theme) async {
  late CodeEditorStyle style;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          style = codeEditorStyleFor(context, 'main.dart');
          return const SizedBox();
        },
      ),
    ),
  );
  return style;
}

void main() {
  testWidgets('terminal-derived theme paints syntax from the ANSI palette', (
    tester,
  ) async {
    final terminalTheme = _darkTheme();
    final style = await _pumpStyle(
      tester,
      buildDarkTheme(
        kTerminalDerivedPresetId,
        AppTypographyScale.standard,
        null,
        null,
        terminalTheme,
      ),
    );
    expect(style.syntaxTheme!['keyword']?.color, terminalTheme.ansi[5]);
    expect(style.syntaxTheme!['string']?.color, terminalTheme.ansi[2]);
    expect(style.syntaxTheme!['function']?.color, terminalTheme.ansi[4]);
    expect(style.textColor, const Color(0xFFD0D4DC));
  });

  testWidgets('fixed presets keep the atom-one palette', (tester) async {
    final style = await _pumpStyle(tester, buildDarkTheme('amber'));
    expect(
      style.syntaxTheme!['keyword']?.color,
      EditorSyntaxTheme.atomOneDark().asStyleMap()['keyword']?.color,
    );
  });
}
