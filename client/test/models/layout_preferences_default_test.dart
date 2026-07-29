import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';

void main() {
  test('fromJson ignores legacy tool layout keys', () {
    final prefs = LayoutPreferences.fromJson(const {
      'toolPlacement': 'bottom',
      'toolsArrangement': 'stacked',
      'bottomToolsHeight': 300,
      'membersSplit': 0.5,
    });
    expect(prefs.rightToolsWidth, LayoutPreferences.defaultRightToolsWidth);
    expect(prefs.fileTreeVisible, isTrue);
  });

  test('sidebarVisible defaults true and round-trips', () {
    expect(const LayoutPreferences().sidebarVisible, isTrue);
    final parsed = LayoutPreferences.fromJson(const {'sidebarVisible': false});
    expect(parsed.sidebarVisible, isFalse);
    expect(parsed.toJson()['sidebarVisible'], isFalse);
  });

  test('locale defaults to system (empty) and maps dropdown values', () {
    expect(const LayoutPreferences().locale, isEmpty);
    expect(languagePreferenceUiValue(''), 'system');
    expect(languagePreferenceUiValue('en'), 'en');
    expect(languagePreferenceUiValue('zh'), 'zh');
    expect(languagePreferenceUiValue('zh_CN'), 'zh');
    expect(languagePreferenceStoredLocale('system'), isEmpty);
    expect(languagePreferenceStoredLocale('en'), 'en');
    expect(languagePreferenceStoredLocale('zh'), 'zh');
  });

  test('workspace panes keep large sizes and only clamp mins', () {
    final prefs = LayoutPreferences.fromJson(const {
      'sidebarWidth': 900,
      'rightToolsWidth': 800,
      'workspaceTerminalHeight': 700,
    });
    expect(prefs.sidebarWidth, 900);
    expect(prefs.rightToolsWidth, 800);
    expect(prefs.workspaceTerminalHeight, 700);

    final clamped = const LayoutPreferences().copyWith(
      sidebarWidth: 10,
      rightToolsWidth: 10,
      workspaceTerminalHeight: 10,
    );
    expect(clamped.sidebarWidth, LayoutPreferences.minSidebarWidth);
    expect(clamped.rightToolsWidth, LayoutPreferences.minRightToolsWidth);
    expect(
      clamped.workspaceTerminalHeight,
      LayoutPreferences.minWorkspaceTerminalHeight,
    );
  });

  test('uiFontId and monoFontId default to bundled faces', () {
    expect(const LayoutPreferences().uiFontId, 'notoSansSc');
    expect(const LayoutPreferences().monoFontId, 'jetbrainsMono');
  });

  test('fromJson missing font keys → bundled; unknown → bundled', () {
    expect(LayoutPreferences.fromJson(const {}).uiFontId, 'notoSansSc');
    expect(LayoutPreferences.fromJson(const {}).monoFontId, 'jetbrainsMono');
    expect(
      LayoutPreferences.fromJson(const {'uiFontId': 'nope'}).uiFontId,
      'notoSansSc',
    );
    expect(
      LayoutPreferences.fromJson(const {'monoFontId': 'nope'}).monoFontId,
      'jetbrainsMono',
    );
  });

  test('font ids round-trip when known', () {
    final prefs = const LayoutPreferences().copyWith(
      uiFontId: 'notoSansSc',
      monoFontId: 'jetbrainsMono',
    );
    final json = prefs.toJson();
    final parsed = LayoutPreferences.fromJson(json);
    expect(parsed.uiFontId, 'notoSansSc');
    expect(parsed.monoFontId, 'jetbrainsMono');
  });

  test('installed font ids normalize and round-trip', () {
    expect(normalizeUiFontId('installed:Foo'), 'installed:Foo');
    expect(normalizeUiFontId('installed:'), 'notoSansSc');
    final prefs = const LayoutPreferences().copyWith(
      uiFontId: 'installed:NotoSansCJK-Regular',
      monoFontId: 'installed:JetBrainsMonoNL-Regular',
    );
    final parsed = LayoutPreferences.fromJson(prefs.toJson());
    expect(parsed.uiFontId, 'installed:NotoSansCJK-Regular');
    expect(parsed.monoFontId, 'installed:JetBrainsMonoNL-Regular');
  });

  test('homeSidebarWidth defaults, clamps min, keeps large', () {
    expect(
      const LayoutPreferences().homeSidebarWidth,
      LayoutPreferences.defaultHomeSidebarWidth,
    );
    expect(
      LayoutPreferences.fromJson(const {}).homeSidebarWidth,
      LayoutPreferences.defaultHomeSidebarWidth,
    );
    expect(
      LayoutPreferences.fromJson(const {
        'homeSidebarWidth': 'x',
      }).homeSidebarWidth,
      LayoutPreferences.defaultHomeSidebarWidth,
    );
    expect(
      LayoutPreferences.fromJson(const {
        'homeSidebarWidth': 10,
      }).homeSidebarWidth,
      LayoutPreferences.minHomeSidebarWidth,
    );
    expect(
      LayoutPreferences.fromJson(const {
        'homeSidebarWidth': 900,
      }).homeSidebarWidth,
      900,
    );
    final clamped = const LayoutPreferences().copyWith(homeSidebarWidth: 10);
    expect(clamped.homeSidebarWidth, LayoutPreferences.minHomeSidebarWidth);
    final roundTrip = LayoutPreferences.fromJson(
      const LayoutPreferences(homeSidebarWidth: 500).toJson(),
    );
    expect(roundTrip.homeSidebarWidth, 500);
  });

  test('cot expand prefs default false and round-trip', () {
    expect(const LayoutPreferences().cotExpandReasoningOnOpen, isFalse);
    expect(const LayoutPreferences().cotExpandToolsOnOpen, isFalse);
    expect(LayoutPreferences.fromJson(const {}).cotExpandReasoningOnOpen, isFalse);

    final parsed = LayoutPreferences.fromJson(const {
      'cotExpandReasoningOnOpen': true,
      'cotExpandToolsOnOpen': true,
    });
    expect(parsed.cotExpandReasoningOnOpen, isTrue);
    expect(parsed.cotExpandToolsOnOpen, isTrue);
    expect(parsed.toJson()['cotExpandReasoningOnOpen'], isTrue);
    expect(parsed.toJson()['cotExpandToolsOnOpen'], isTrue);
  });

  test('terminal custom colour fields default off/empty', () {
    const prefs = LayoutPreferences();
    expect(prefs.useCustomTerminalColors, isFalse);
    expect(prefs.terminalColorOverrides, isEmpty);
    final parsed = LayoutPreferences.fromJson(const {});
    expect(parsed.useCustomTerminalColors, isFalse);
    expect(parsed.terminalColorOverrides, isEmpty);
  });

  test('terminal custom colour fields round-trip through JSON', () {
    final prefs = const LayoutPreferences().copyWith(
      useCustomTerminalColors: true,
      terminalColorOverrides: const {
        'background': 0xFF102030,
        'ansi5': 0xFFAABBCC,
      },
    );
    final parsed = LayoutPreferences.fromJson(prefs.toJson());
    expect(parsed.useCustomTerminalColors, isTrue);
    expect(parsed.terminalColorOverrides['background'], 0xFF102030);
    expect(parsed.terminalColorOverrides['ansi5'], 0xFFAABBCC);
  });

  test('terminalColorOverrides drops unknown keys and forces opaque alpha', () {
    final parsed = LayoutPreferences.fromJson(const {
      'terminalColorOverrides': {
        'background': 0x00123456, // transparent → forced 0xFF
        'ansi16': 0xFF000000, // out of range → dropped
        'bogus': 0xFFFFFFFF, // unknown slot → dropped
      },
    });
    expect(parsed.terminalColorOverrides.keys, ['background']);
    expect(parsed.terminalColorOverrides['background'], 0xFF123456);
  });

  test('terminalColorOverrides tolerates non-map / num values', () {
    expect(
      LayoutPreferences.fromJson(const {
        'terminalColorOverrides': 'not-a-map',
      }).terminalColorOverrides,
      isEmpty,
    );
    // A JSON num decoded as double is coerced to int, then forced opaque.
    final parsed = LayoutPreferences.fromJson(const {
      'terminalColorOverrides': {'cursor': 0xFF445566},
    });
    expect(parsed.terminalColorOverrides['cursor'], 0xFF445566);
  });

  test('copyWith sanitizes overrides (unknown dropped, alpha forced)', () {
    final prefs = const LayoutPreferences().copyWith(
      terminalColorOverrides: const {
        'foreground': 0x11223344,
        'nope': 0xFFFFFFFF,
      },
    );
    expect(prefs.terminalColorOverrides.keys, ['foreground']);
    expect(prefs.terminalColorOverrides['foreground'], 0xFF223344);
  });

  test('terminalThemeMode widened to accept catalog ids', () {
    expect(
      LayoutPreferences.fromJson(const {
        'terminalThemeMode': 'dracula',
      }).terminalThemeMode,
      'dracula',
    );
    // Unknown *slugs* survive: user-imported theme ids load after preferences
    // at bootstrap, so rejecting them here would clobber a valid import.
    // `terminal_theme_mapper.dart` falls back when the id resolves to nothing.
    expect(
      LayoutPreferences.fromJson(const {
        'terminalThemeMode': 'totally-bogus',
      }).terminalThemeMode,
      'totally-bogus',
    );
    // Non-slug junk still falls back.
    for (final junk in const ['Totally Bogus!', '-dash', '', 'a/b']) {
      expect(
        LayoutPreferences.fromJson({
          'terminalThemeMode': junk,
        }).terminalThemeMode,
        'adaptive',
        reason: junk,
      );
    }
    expect(
      LayoutPreferences.fromJson(const {
        'terminalThemeMode': 'classicDark',
      }).terminalThemeMode,
      'classicDark',
    );
  });

  test('markdownOpenMode defaults to preview and round-trips', () {
    expect(
      const LayoutPreferences().markdownOpenMode,
      MarkdownOpenMode.preview,
    );
    expect(
      LayoutPreferences.fromJson(const {}).markdownOpenMode,
      MarkdownOpenMode.preview,
    );
    expect(
      LayoutPreferences.fromJson(const {
        'markdownOpenMode': 'source',
      }).markdownOpenMode,
      MarkdownOpenMode.source,
    );
    final remember = const LayoutPreferences().copyWith(
      markdownOpenMode: MarkdownOpenMode.remember,
    );
    expect(
      LayoutPreferences.fromJson(remember.toJson()).markdownOpenMode,
      MarkdownOpenMode.remember,
    );
    expect(
      LayoutPreferences.fromJson(const {
        'markdownOpenMode': 'nope',
      }).markdownOpenMode,
      MarkdownOpenMode.preview,
    );
  });
}
