import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/terminal/cmux_theme_markdown_parser.dart';

/// A minimal 1-dark + 1-light fixture with the exact table shape the real doc
/// uses, so the strict parser can be exercised without the external file.
const _fixture = '''
## 三、深色组

### Fixture Dark（作者：Tester；第 1–2 行）

| 背景 | 前景 | 光标 | 选区 | 搜索命中 | 当前命中 | 命中前景 | 强调色 |
|---|---|---|---|---|---|---|---|
| #101010 | #E0E0E0 | #818CF8 | #333355 | #FBBF24 | #34D399 | #101010 | — |

| black | red | green | yellow | blue | magenta | cyan | white |
|---|---|---|---|---|---|---|---|
| #1E1E1E | #EF4444 | #10B981 | #FBBF24 | #6366F1 | #A78BFA | #2DD4BF | #E0E0E0 |
| **br.black** | **br.red** | **br.green** | **br.yellow** | **br.blue** | **br.magenta** | **br.cyan** | **br.white** |
| #6B7280 | #FB923C | #34D399 | #FBBF24 | #818CF8 | #C4B5FD | #5EEAD4 | #FFFFFF |

## 四、浅色组

### Fixture Light（作者：Tester；第 3–4 行）

| 背景 | 前景 | 光标 | 选区 | 搜索命中 | 当前命中 | 命中前景 | 强调色 |
|---|---|---|---|---|---|---|---|
| #B1AC9F | #657B83 | #586E75 | #A7CBDC | #B58900 | #859900 | #002B36 | #88C0D0 |

| black | red | green | yellow | blue | magenta | cyan | white |
|---|---|---|---|---|---|---|---|
| #073642 | #DC322F | #859900 | #B58900 | #268BD2 | #D33682 | #2AA198 | #EEE8D5 |
| **br.black** | **br.red** | **br.green** | **br.yellow** | **br.blue** | **br.magenta** | **br.cyan** | **br.white** |
| #002B36 | #CB4B16 | #586E75 | #657B83 | #839496 | #6C71C4 | #93A1A1 | #FDF6E3 |
''';

void main() {
  test('parses a 1-dark + 1-light fixture', () {
    final specs = parseCmuxThemesMarkdown(_fixture);
    expect(specs.length, 2);

    final dark = specs[0];
    expect(dark.name, 'Fixture Dark');
    expect(dark.author, 'Tester');
    expect(dark.isDark, isTrue);
    expect(dark.background, 0x101010);
    expect(dark.accent, isNull); // — cell
    expect(dark.ansi.length, 16);
    expect(dark.ansi.first, 0x1E1E1E);
    expect(dark.ansi.last, 0xFFFFFF);

    final light = specs[1];
    expect(light.name, 'Fixture Light');
    expect(light.isDark, isFalse);
    expect(light.background, 0xB1AC9F);
    expect(light.accent, 0x88C0D0); // explicit accent
    expect(light.ansi.length, 16);
  });

  test('rejects a theme with the wrong number of ANSI colours', () {
    // Drop one bright-ANSI cell from the dark theme.
    final broken = _fixture.replaceFirst(
      '| #6B7280 | #FB923C | #34D399 | #FBBF24 | #818CF8 | #C4B5FD | #5EEAD4 | #FFFFFF |',
      '| #6B7280 | #FB923C | #34D399 | #FBBF24 | #818CF8 | #C4B5FD | #5EEAD4 |',
    );
    expect(
      () => parseCmuxThemesMarkdown(broken),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Fixture Dark'),
        ),
      ),
    );
  });

  test('rejects an unparseable hex, naming the theme', () {
    final broken = _fixture.replaceFirst('#101010', '#XYZ123');
    expect(
      () => parseCmuxThemesMarkdown(broken),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Fixture Dark'),
        ),
      ),
    );
  });

  test('validateCmuxThemeCatalog rejects a non-23 catalog', () {
    final specs = parseCmuxThemesMarkdown(_fixture);
    expect(
      () => validateCmuxThemeCatalog(specs),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Expected 23'),
        ),
      ),
    );
  });
}
