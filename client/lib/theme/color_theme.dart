import 'package:flutter/material.dart';

import 'terminal/cmux_terminal_theme.dart';
import 'terminal_derived_scheme.dart';

/// The unified colour-theme id space (VS Code `workbench.colorTheme` model).
///
/// One id names a whole-app look — UI chrome, terminal palette, and the file
/// browser surface all follow it. Two kinds:
///
/// - **Interface themes** (`ui:{preset}:{light|dark}`): one of the five fixed
///   palettes pinned to a brightness. The terminal renders *adaptively* (derived
///   from the UI [ColorScheme]), so chrome and terminal stay in one family.
/// - **Terminal themes** (a catalog / imported / legacy id such as `dracula`,
///   `classicDark`): the terminal paints that palette and the whole UI is
///   derived from it pixel-for-pixel (the `terminalDerivedColorScheme` port of
///   cmux). Brightness is the theme's own, not a slot choice.
///
/// The persisted light/dark slots ([LayoutPreferences.lightThemeId] /
/// [darkThemeId]) each hold one id; `themeMode` (light/dark/system) picks which
/// slot is active — VS Code's `preferredLight/DarkColorTheme` +
/// `autoDetectColorScheme`.

/// Prefix marking an interface-palette theme id.
const String kUiColorThemePrefix = 'ui:';

const String kDefaultLightColorThemeId = 'ui:amber:light';
const String kDefaultDarkColorThemeId = 'ui:amber:dark';

/// Builds the interface-theme id for a fixed [preset] at [brightness].
String uiColorThemeId(String preset, Brightness brightness) =>
    '$kUiColorThemePrefix$preset:'
    '${brightness == Brightness.light ? 'light' : 'dark'}';

/// True when [id] is an interface-palette theme (`ui:…`).
bool isUiColorTheme(String id) => id.startsWith(kUiColorThemePrefix);

/// The fixed-preset slug of a `ui:` id, or null for terminal themes. Not
/// normalized here — [normalizeThemeColorPreset] runs at palette lookup, so a
/// hand-edited bad slug falls back to the default rather than throwing.
String? uiColorThemePreset(String id) {
  if (!isUiColorTheme(id)) return null;
  final parts = id.split(':');
  return parts.length >= 2 && parts[1].isNotEmpty ? parts[1] : null;
}

/// Brightness encoded in a `ui:` id (`:light` → light, anything else → dark).
Brightness uiColorThemeBrightness(String id) {
  final parts = id.split(':');
  return parts.length == 3 && parts[2] == 'light'
      ? Brightness.light
      : Brightness.dark;
}

/// The catalog / imported theme behind a terminal-theme id, or null for `ui:`
/// ids and for legacy modes (`classicDark` / `highContrast`, which have no
/// [CmuxTerminalTheme] and are painted by the legacy mapper path).
CmuxTerminalTheme? colorThemeTerminalTheme(String id) {
  if (isUiColorTheme(id)) return null;
  return cmuxTerminalThemeForMode(id);
}

/// The brightness a theme id renders at. `ui:` ids carry it in the suffix;
/// catalog / imported themes derive it from perceived luminance; legacy modes
/// and unresolvable ids are dark.
Brightness colorThemeBrightness(String id) {
  if (isUiColorTheme(id)) return uiColorThemeBrightness(id);
  final theme = colorThemeTerminalTheme(id);
  if (theme != null) {
    return theme.isLightByLuminance ? Brightness.light : Brightness.dark;
  }
  return Brightness.dark;
}

/// The terminal mode the theme mapper consumes for [id]: an interface theme
/// renders the terminal adaptively; any terminal-theme id *is* the terminal
/// theme. This is what replaces the old standalone `terminalThemeMode` field.
String terminalModeForColorTheme(String id) =>
    isUiColorTheme(id) ? 'adaptive' : id;

/// Clamps an arbitrary stored id to a renderable one. An interface id keeps its
/// shape; a terminal id survives verbatim (catalog / imported ids load after
/// preferences, and legacy modes are valid), so — like the old
/// `_terminalThemeModeValue` — only structurally broken values fall back.
/// [fallback] is the brightness-appropriate default.
String normalizeColorThemeId(String? raw, String fallback) {
  if (raw == null || raw.isEmpty) return fallback;
  if (isUiColorTheme(raw)) {
    // Require the full `ui:{preset}:{light|dark}` shape.
    final parts = raw.split(':');
    if (parts.length == 3 &&
        parts[1].isNotEmpty &&
        (parts[2] == 'light' || parts[2] == 'dark')) {
      return raw;
    }
    return fallback;
  }
  // Legacy terminal-only modes are camelCase and carry no catalog palette.
  if (raw == 'classicDark' || raw == 'highContrast') return raw;
  // Terminal ids: accept a stable slug (catalog or imported). Non-slug junk
  // falls back so a corrupted prefs file can't poison the whole theme.
  return _colorThemeSlugPattern.hasMatch(raw) ? raw : fallback;
}

final RegExp _colorThemeSlugPattern = RegExp(
  r'^[a-z0-9]+(?:[-_][a-z0-9]+)*$',
);
