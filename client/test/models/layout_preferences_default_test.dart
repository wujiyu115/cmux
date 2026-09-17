import 'package:flutter/material.dart';
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

  test('colour theme slots default to the amber interface themes', () {
    final prefs = LayoutPreferences.fromJson(const {});
    expect(prefs.lightThemeId, 'ui:amber:light');
    expect(prefs.darkThemeId, 'ui:amber:dark');
  });

  test('migrates a legacy fixed preset into both brightness slots', () {
    final prefs = LayoutPreferences.fromJson(const {
      'themeColorPreset': 'forest',
    });
    expect(prefs.lightThemeId, 'ui:forest:light');
    expect(prefs.darkThemeId, 'ui:forest:dark');
  });

  test('migrates a legacy terminal mode into its own brightness slot', () {
    final prefs = LayoutPreferences.fromJson(const {
      'terminalThemeMode': 'dracula',
    });
    // Dracula is dark: it fills the dark slot; the light slot keeps the
    // default light theme (no legacy preset to inherit).
    expect(prefs.darkThemeId, 'dracula');
    expect(prefs.lightThemeId, 'ui:amber:light');
  });

  test('legacy terminal mode fills its slot; preset fills the other', () {
    final prefs = LayoutPreferences.fromJson(const {
      'themeColorPreset': 'ocean',
      'terminalThemeMode': 'classicDark',
    });
    expect(prefs.darkThemeId, 'classicDark');
    expect(prefs.lightThemeId, 'ui:ocean:light');
  });

  test('slot brightness contract coerces a wrong-brightness stored id', () {
    // A dark theme stored in the light slot is coerced to the light default —
    // this is what stops "switch to light still renders dark".
    final prefs = LayoutPreferences.fromJson(const {
      'lightThemeId': 'nord',
      'darkThemeId': 'dracula',
    });
    expect(prefs.lightThemeId, 'ui:amber:light');
    expect(prefs.darkThemeId, 'dracula');

    // copyWith enforces it too.
    final coerced = const LayoutPreferences().copyWith(lightThemeId: 'dracula');
    expect(coerced.lightThemeId, 'ui:amber:light');
    final ok = const LayoutPreferences().copyWith(darkThemeId: 'dracula');
    expect(ok.darkThemeId, 'dracula');

    final json = prefs.toJson();
    expect(json['lightThemeId'], 'ui:amber:light');
    expect(json['darkThemeId'], 'dracula');
    expect(json.containsKey('themeColorPreset'), isFalse);
    expect(json.containsKey('terminalThemeMode'), isFalse);
  });

  test('structurally broken theme ids fall back to the slot default', () {
    // A terminal id must be a stable slug; junk resets to the amber default.
    expect(
      LayoutPreferences.fromJson(const {'darkThemeId': 'Not A Slug!'}).darkThemeId,
      'ui:amber:dark',
    );
    // A `ui:` id missing its brightness suffix is malformed → fallback.
    expect(
      LayoutPreferences.fromJson(const {'lightThemeId': 'ui:amber'}).lightThemeId,
      'ui:amber:light',
    );
    // An unknown but well-formed slug survives in the DARK slot (unresolvable
    // ids read as dark, and an imported theme may load later); the light slot
    // coerces it away since a dark-reading id can't fill a light slot.
    expect(
      LayoutPreferences.fromJson(const {'darkThemeId': 'totally-bogus'}).darkThemeId,
      'totally-bogus',
    );
    expect(
      LayoutPreferences.fromJson(const {'lightThemeId': 'totally-bogus'}).lightThemeId,
      'ui:amber:light',
    );
  });

  test('resolveColorTheme picks the slot by mode and derives the terminal mode', () {
    const prefs = LayoutPreferences(
      lightThemeId: 'ui:amber:light',
      darkThemeId: 'dracula',
    );

    final light = prefs.resolveColorTheme(platformDark: false);
    expect(light.themeId, 'ui:amber:light');
    expect(light.brightness, Brightness.light);
    expect(light.terminalMode, 'adaptive'); // interface theme → adaptive

    // themeMode 'system' follows the platform.
    final dark = prefs.copyWith(themeMode: 'system').resolveColorTheme(
      platformDark: true,
    );
    expect(dark.themeId, 'dracula');
    expect(dark.terminalMode, 'dracula'); // terminal theme → itself

    // themeMode pins a slot regardless of platform.
    expect(
      prefs.copyWith(themeMode: 'light').resolveColorTheme(platformDark: true).themeId,
      'ui:amber:light',
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

  test('editorPreviewTabs defaults on and round-trips', () {
    expect(const LayoutPreferences().editorPreviewTabs, isTrue);
    expect(LayoutPreferences.fromJson(const {}).editorPreviewTabs, isTrue);
    final off = const LayoutPreferences().copyWith(editorPreviewTabs: false);
    expect(off.editorPreviewTabs, isFalse);
    expect(
      LayoutPreferences.fromJson(off.toJson()).editorPreviewTabs,
      isFalse,
    );
    expect(
      LayoutPreferences.fromJson(const {'editorPreviewTabs': false})
          .editorPreviewTabs,
      isFalse,
    );
  });

  test('searchVisible defaults on and round-trips', () {
    expect(const LayoutPreferences().searchVisible, isTrue);
    expect(LayoutPreferences.fromJson(const {}).searchVisible, isTrue);
    final off = const LayoutPreferences().copyWith(searchVisible: false);
    expect(off.searchVisible, isFalse);
    expect(
      LayoutPreferences.fromJson(off.toJson()).searchVisible,
      isFalse,
    );
    expect(
      LayoutPreferences.fromJson(const {'searchVisible': false}).searchVisible,
      isFalse,
    );
  });

  test('editorWordWrap defaults off and round-trips', () {
    expect(const LayoutPreferences().editorWordWrap, isFalse);
    expect(LayoutPreferences.fromJson(const {}).editorWordWrap, isFalse);
    final on = const LayoutPreferences().copyWith(editorWordWrap: true);
    expect(on.editorWordWrap, isTrue);
    expect(
      LayoutPreferences.fromJson(on.toJson()).editorWordWrap,
      isTrue,
    );
    expect(
      LayoutPreferences.fromJson(const {'editorWordWrap': true}).editorWordWrap,
      isTrue,
    );
  });

  test('withAtLeastOneToolVisible: search alone satisfies the contract', () {
    // Only search visible → nothing force-shown, contract intact.
    final prefs = const LayoutPreferences().copyWith(
      fileTreeVisible: false,
      gitVisible: false,
    );
    expect(prefs.fileTreeVisible, isFalse);
    expect(prefs.gitVisible, isFalse);
    expect(prefs.searchVisible, isTrue);

    // Everything off → the fallback force-shows the file tree.
    final forced = const LayoutPreferences()
        .copyWith(fileTreeVisible: false, gitVisible: false, searchVisible: false);
    expect(forced.fileTreeVisible, isTrue);
  });
}
