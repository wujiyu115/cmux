import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:teampilot/theme/terminal/cmux_terminal_theme.dart';
import 'package:teampilot/theme/terminal/terminal_theme_catalog.g.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';

int _packColor(Color color) => color.toARGB32() & 0xFFFFFF;

/// OSC 8 hyperlink highlight (rendered via [TerminalTheme.hintStart]).
({int bg, int fg}) _hyperlinkHintFromScheme(ColorScheme cs) =>
    (bg: _packColor(cs.primary), fg: _packColor(cs.onPrimary));

/// Maps [TerminalTheme] into engine [TerminalColors] (PTY palette + defaults).
TerminalColors terminalColorsFromTheme(TerminalTheme theme) {
  return TerminalColors(
    background: theme.background,
    foreground: theme.foreground,
    selection: theme.selection,
    ansi: List<int>.from(theme.ansi),
    searchMatchBg: theme.searchMatch.bg,
    searchMatchFg: theme.searchMatch.fg,
    searchFocusedBg: theme.searchFocused.bg,
    searchFocusedFg: theme.searchFocused.fg,
    hintStartFg: theme.hintStart.fg,
    hintStartBg: theme.hintStart.bg,
    cursorText: theme.cursorText,
    cursorBody: theme.cursorColor,
  );
}

/// TeamPilot terminal config: theme colors + scrollback, other fields from defaults.
TerminalConfig terminalConfigFromTheme(
  TerminalTheme theme, {
  int scrollbackLines = 10000,
}) {
  return TerminalConfig.defaults().copyWith(
    colors: terminalColorsFromTheme(theme),
    scrolling: TerminalConfig.defaults().scrolling.copyWith(
      history: scrollbackLines,
    ),
    cursor: CursorConfig(
      blinkInterval: 750,
      defaultShape: 0,
      defaultBlinking: true,
      blinkTimeout: 0,
    ),
  );
}

/// Fingerprint for skipping redundant [TerminalEngine.reconfigure] calls.
int terminalThemeFingerprint(TerminalTheme theme) => Object.hash(
  theme.background,
  theme.foreground,
  theme.selection,
  Object.hashAll(theme.ansi),
  theme.searchMatch.bg,
  theme.searchMatch.fg,
  theme.searchFocused.bg,
  theme.searchFocused.fg,
  theme.hintStart.bg,
  theme.hintStart.fg,
  theme.cursorText,
  theme.cursorColor,
  theme.bellOverlay,
);

/// Resolves a built-in catalog theme from a [teampilotTerminalTheme] `mode`
/// string: first by stable id, then (for tolerance) a case-insensitive
/// display-name match. Returns `null` for the legacy adaptive/classicDark/
/// highContrast modes so they fall through unchanged.
CmuxTerminalTheme? _catalogThemeForMode(String mode) {
  final byId = cmuxTerminalThemeById(mode);
  if (byId != null) return byId;
  final lower = mode.toLowerCase();
  for (final theme in kCmuxTerminalThemes) {
    if (theme.name.toLowerCase() == lower) return theme;
  }
  return null;
}

/// Applies per-slot custom colour overrides onto an already-packed
/// [TerminalTheme] (used for the legacy adaptive/classicDark/highContrast
/// branches, which have no [CmuxTerminalTheme]). The field mapping mirrors
/// [CmuxTerminalTheme.toTerminalTheme] so the effect matches the catalog path.
TerminalTheme _applyOverridesToTerminalTheme(
  TerminalTheme theme,
  Map<String, int> overrides,
) {
  int pick(String slot, int current) {
    final value = overrides[slot];
    return value == null ? current : (value & 0xFFFFFF);
  }

  final searchFg = pick('searchHitFg', theme.searchMatch.fg);
  final cursorOverride = overrides['cursor'];
  return TerminalTheme(
    background: pick('background', theme.background),
    foreground: pick('foreground', theme.foreground),
    selection: pick('selection', theme.selection),
    ansi: <int>[
      for (var i = 0; i < theme.ansi.length; i++) pick('ansi$i', theme.ansi[i]),
    ],
    searchMatch: (bg: pick('searchHit', theme.searchMatch.bg), fg: searchFg),
    searchFocused: (
      bg: pick('searchHitCurrent', theme.searchFocused.bg),
      fg: searchFg,
    ),
    hintStart: (bg: pick('accent', theme.hintStart.bg), fg: theme.hintStart.fg),
    cursorText: theme.cursorText,
    // Preserve the inverse-video sentinel (null) unless explicitly overridden.
    cursorColor: cursorOverride != null
        ? (cursorOverride & 0xFFFFFF)
        : theme.cursorColor,
    bellOverlay: theme.bellOverlay,
  );
}

/// Maps TeamPilot layout theme modes to [TerminalTheme] (packed RGB).
///
/// [chrome] selects which workspace card surface seeds the adaptive background
/// (terminals always live on the workspace workbench card).
///
/// When [useCustomColors] is true, per-slot [colorOverrides] (keyed by
/// `kTerminalColorSlots`, ARGB ints) are applied on top of the resolved theme.
/// Catalog themes go through [applyTerminalColorOverrides]; legacy branches use
/// [_applyOverridesToTerminalTheme]. Overrides change the packed colours, so the
/// existing [terminalThemeFingerprint] naturally repaints live terminals — no
/// separate fingerprint field is needed.
TerminalTheme teampilotTerminalTheme(
  ColorScheme cs, {
  required bool isDark,
  required String mode,
  WorkspacePageChrome chrome = WorkspacePageChrome.workspace,
  Map<String, int> colorOverrides = const {},
  bool useCustomColors = false,
}) {
  final hasOverrides = useCustomColors && colorOverrides.isNotEmpty;

  final catalogTheme = _catalogThemeForMode(mode);
  if (catalogTheme != null) {
    final effective = hasOverrides
        ? applyTerminalColorOverrides(catalogTheme, colorOverrides)
        : catalogTheme;
    return effective.toTerminalTheme();
  }

  final base = _legacyTerminalTheme(cs, isDark: isDark, mode: mode, chrome: chrome);
  return hasOverrides ? _applyOverridesToTerminalTheme(base, colorOverrides) : base;
}

/// The legacy (non-catalog) adaptive / classicDark / highContrast theme bodies.
TerminalTheme _legacyTerminalTheme(
  ColorScheme cs, {
  required bool isDark,
  required String mode,
  required WorkspacePageChrome chrome,
}) {
  if (mode == 'classicDark') {
    return TerminalTheme(
      background: 0x0A0C10,
      foreground: 0xC8CCD4,
      selection: 0x9AA0A8,
      ansi: const [
        0x1A1A1A,
        0xD04A62,
        0x52C07E,
        0xD4B85A,
        0x5298D8,
        0xB87CD8,
        0x4EB8C4,
        0xD0D4DC,
        0x5A5A5A,
        0xE86A7E,
        0x6CD898,
        0xE8CC70,
        0x72B0E8,
        0xD098F0,
        0x72D0DC,
        0xE4E6EC,
      ],
      searchMatch: (bg: 0xFFFF2B, fg: 0x000000),
      searchFocused: (bg: 0x31FF26, fg: 0x000000),
      hintStart: (bg: 0x5298D8, fg: 0x0A0C10),
      cursorText: null,
      cursorColor: 0x9AA0A8,
      bellOverlay: 0xFFFFFF,
    );
  }

  if (mode == 'highContrast') {
    final bg = isDark ? 0x000000 : 0xFFFFFF;
    final fg = isDark ? 0xF5F7FA : 0x111111;
    final primary = isDark ? 0x69B3FF : 0x005FCC;
    final secondary = isDark ? 0x4EE2A8 : 0x007A4B;
    return TerminalTheme(
      background: bg,
      foreground: fg,
      selection: primary,
      ansi: [
        isDark ? 0x1A1A1A : 0x2A2A2A,
        isDark ? 0xFF6B7A : 0xB00020,
        secondary,
        isDark ? 0xFFD166 : 0x8A6D00,
        primary,
        isDark ? 0xD79BFF : 0x7A3DB8,
        isDark ? 0x63E6FF : 0x006A85,
        fg,
        isDark ? 0x8C8C8C : 0x666666,
        isDark ? 0xFF98A3 : 0xD32F2F,
        isDark ? 0x8AF0C6 : 0x0A8F5A,
        isDark ? 0xFFE08A : 0xA88700,
        isDark ? 0x9CCEFF : 0x1976D2,
        isDark ? 0xE7C0FF : 0x9C4DCC,
        isDark ? 0x9CEEFF : 0x008DB3,
        isDark ? 0xFFFFFF : 0x000000,
      ],
      searchMatch: (bg: 0xFFFF2B, fg: 0x000000),
      searchFocused: (bg: 0x31FF26, fg: 0x000000),
      hintStart: (bg: primary, fg: isDark ? 0x000000 : 0xFFFFFF),
      cursorText: null,
      cursorColor: primary,
      bellOverlay: 0xFFFFFF,
    );
  }

  final cardSurface = cs.workspaceCardChrome(chrome);
  final baseBackground = isDark
      ? Color.alphaBlend(cardSurface, const Color(0xFF06080C))
      : Color.alphaBlend(cardSurface, const Color(0xFFF7F9FC));
  // Light: follow softened [ColorScheme] body/muted text (see app_theme.dart).
  final foreground = isDark ? const Color(0xFFC8CCD4) : cs.onSurface;
  final weak = isDark ? const Color(0xFF59606A) : cs.onSurfaceVariant;
  final lightAnsiBlack = Color.lerp(foreground, cs.surface, 0.18)!;
  return TerminalTheme(
    background: _packColor(baseBackground),
    foreground: _packColor(foreground),
    selection: _packColor(cs.primary),
    ansi: [
      _packColor(isDark ? const Color(0xFF161A21) : lightAnsiBlack),
      _packColor(cs.error),
      _packColor(cs.secondary),
      _packColor(Color.lerp(cs.secondary, const Color(0xFFE5B95C), 0.5)!),
      _packColor(cs.primary),
      _packColor(Color.lerp(cs.primary, cs.secondary, 0.45)!),
      _packColor(Color.lerp(cs.secondary, const Color(0xFF58C8D7), 0.55)!),
      _packColor(isDark ? const Color(0xFFD8DCE5) : weak),
      _packColor(weak),
      _packColor(Color.lerp(cs.error, Colors.white, isDark ? 0.18 : 0.1)!),
      _packColor(Color.lerp(cs.secondary, Colors.white, isDark ? 0.16 : 0.08)!),
      _packColor(
        Color.lerp(
          Color.lerp(cs.secondary, const Color(0xFFE5B95C), 0.5)!,
          Colors.white,
          isDark ? 0.2 : 0.1,
        )!,
      ),
      _packColor(Color.lerp(cs.primary, Colors.white, isDark ? 0.16 : 0.08)!),
      _packColor(
        Color.lerp(
          Color.lerp(cs.primary, cs.secondary, 0.45)!,
          Colors.white,
          isDark ? 0.2 : 0.1,
        )!,
      ),
      _packColor(
        Color.lerp(
          Color.lerp(cs.secondary, const Color(0xFF58C8D7), 0.55)!,
          Colors.white,
          isDark ? 0.2 : 0.1,
        )!,
      ),
      _packColor(isDark ? const Color(0xFFF2F4F8) : foreground),
    ],
    searchMatch: (bg: 0xFFFF2B, fg: 0x000000),
    searchFocused: (bg: 0x31FF26, fg: 0x000000),
    hintStart: _hyperlinkHintFromScheme(cs),
    cursorText: null,
    cursorColor: _packColor(cs.primary),
    bellOverlay: 0xFFFFFF,
  );
}
