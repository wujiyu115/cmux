import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'terminal/cmux_terminal_theme.dart';
import 'terminal/terminal_theme_catalog.g.dart';
import 'terminal/user_terminal_theme_registry.dart';

/// Colour-preset id meaning "derive the whole UI scheme from the active terminal
/// theme" (the 6th entry in `kThemeColorPresetIds`).
///
/// cmux has a single theme list that drives both the terminal and the app
/// chrome; this preset reproduces that behaviour while leaving the five
/// hand-tuned presets untouched.
const String kTerminalDerivedPresetId = 'terminal';

/// Perceived luminance on a 0..255 scale — cmux `AppThemeService.cs:222`
/// (`0.299R + 0.587G + 0.114B`). Kept in 8-bit space (not Flutter's
/// [Color.computeLuminance], which is linearized 0..1) so the ported
/// thresholds (`> 128` light, `> 140` accent text) match cmux exactly.
double terminalPerceivedLuminance(Color color) {
  final argb = color.toARGB32();
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

/// Euclidean RGB distance (`AppThemeService.cs:214`).
double terminalColorDistance(Color a, Color b) {
  final x = a.toARGB32();
  final y = b.toARGB32();
  final dr = (((x >> 16) & 0xFF) - ((y >> 16) & 0xFF)).toDouble();
  final dg = (((x >> 8) & 0xFF) - ((y >> 8) & 0xFF)).toDouble();
  final db = ((x & 0xFF) - (y & 0xFF)).toDouble();
  return math.sqrt(dr * dr + dg * dg + db * db);
}

Color _rgb(int r, int g, int b) =>
    Color(0xFF000000 | (r & 0xFF) << 16 | (g & 0xFF) << 8 | (b & 0xFF));

/// Scales each channel toward black by [amount] (`Darken`, `:189`).
Color darkenTerminalColor(Color color, double amount) {
  final argb = color.toARGB32();
  final factor = 1.0 - amount;
  return _rgb(
    (((argb >> 16) & 0xFF) * factor).toInt(),
    (((argb >> 8) & 0xFF) * factor).toInt(),
    ((argb & 0xFF) * factor).toInt(),
  );
}

/// Pulls each channel toward white by [amount] (`Lighten`, `:198`).
Color lightenTerminalColor(Color color, double amount) {
  final argb = color.toARGB32();
  int up(int channel) =>
      math.min(255, (channel + (255 - channel) * amount).toInt());
  return _rgb(
    up((argb >> 16) & 0xFF),
    up((argb >> 8) & 0xFF),
    up(argb & 0xFF),
  );
}

/// Linear channel mix, `t` = how far from [a] toward [b] (`Blend`, `:206`).
Color blendTerminalColor(Color a, Color b, double t) {
  final x = a.toARGB32();
  final y = b.toARGB32();
  int mix(int shift) {
    final from = (x >> shift) & 0xFF;
    final to = (y >> shift) & 0xFF;
    return (from + (to - from) * t).toInt();
  }

  return _rgb(mix(16), mix(8), mix(0));
}

/// cmux `PickAccent` (`AppThemeService.cs:176`): the explicit accent when the
/// theme declares one, else the cursor colour — unless the cursor is nearly the
/// foreground (a common "cursor == text" theme), in which case ANSI 4 (blue) is
/// used so the accent stays visible against text.
Color pickTerminalAccent(CmuxTerminalTheme theme) {
  final accent = theme.accent;
  if (accent != null) return accent;
  final cursor = theme.cursor;
  if (terminalColorDistance(cursor, theme.foreground) < 30 &&
      theme.ansi.length > 4) {
    return theme.ansi[4];
  }
  return cursor;
}

/// Text colour that reads on [background] — cmux's `accentFg` rule
/// (`AppThemeService.cs:47`): near-black on bright fills, white otherwise.
Color terminalOnColor(Color background) => terminalPerceivedLuminance(background) > 140
    ? const Color(0xFF1A1A1A)
    : const Color(0xFFFFFFFF);

/// The chrome colours cmux derives from a terminal theme
/// (`AppThemeService.BuildColorDictionary`, `:23-58`).
///
/// Only the slots the Flutter UI actually consumes are kept; the WPF-only
/// brushes (gradients, drop shadows, `SystemColors` overrides) have no
/// counterpart here.
class TerminalDerivedPalette {
  const TerminalDerivedPalette({
    required this.isLight,
    required this.background,
    required this.sidebarBackground,
    required this.hover,
    required this.selected,
    required this.foreground,
    required this.foregroundDim,
    required this.accent,
    required this.accentForeground,
    required this.border,
    required this.divider,
    required this.tabBackground,
    required this.tabSelected,
    required this.surface,
    required this.surfaceHigh,
    required this.inputBackground,
    required this.error,
    required this.success,
    required this.warning,
    required this.purple,
    required this.teal,
  });

  factory TerminalDerivedPalette.fromTheme(CmuxTerminalTheme theme) {
    final bg = theme.background;
    final fg = theme.foreground;
    final accent = pickTerminalAccent(theme);
    final isLight = theme.isLightByLuminance;
    Color step(double lightAmount, double darkAmount) => isLight
        ? darkenTerminalColor(bg, lightAmount)
        : lightenTerminalColor(bg, darkAmount);

    return TerminalDerivedPalette(
      isLight: isLight,
      background: bg,
      // cmux darkens the sidebar in both modes (`:30`).
      sidebarBackground: darkenTerminalColor(bg, 0.03),
      hover: blendTerminalColor(bg, accent, 0.12),
      selected: blendTerminalColor(bg, accent, 0.20),
      foreground: fg,
      foregroundDim: blendTerminalColor(fg, bg, 0.55),
      accent: accent,
      accentForeground: terminalOnColor(accent),
      border: step(0.12, 0.10),
      divider: step(0.14, 0.12),
      tabBackground: step(0.04, 0.04),
      tabSelected: step(0.08, 0.08),
      surface: step(0.04, 0.03),
      surfaceHigh: step(0.08, 0.07),
      inputBackground: step(0.06, 0.05),
      error: theme.ansi[1],
      success: theme.ansi[2],
      warning: theme.ansi[3],
      purple: theme.ansi[5],
      teal: theme.ansi[6],
    );
  }

  /// Light by perceived background luminance (not the catalog's `isDark` flag).
  final bool isLight;

  final Color background;
  final Color sidebarBackground;
  final Color hover;
  final Color selected;
  final Color foreground;
  final Color foregroundDim;
  final Color accent;
  final Color accentForeground;
  final Color border;
  final Color divider;
  final Color tabBackground;
  final Color tabSelected;
  final Color surface;
  final Color surfaceHigh;
  final Color inputBackground;
  final Color error;
  final Color success;
  final Color warning;
  final Color purple;
  final Color teal;
}

/// Builds a Material [ColorScheme] out of a terminal theme.
///
/// [ColorScheme.brightness] follows the perceived-luminance rule, so a light
/// terminal theme always yields a light scheme regardless of which slot
/// (`theme` vs `darkTheme`) it is installed in — `app_theme.dart` only uses this
/// path when the requested brightness agrees.
///
/// Surface ladder ↔ cmux mapping (see `workspace_surface_layers.dart` for how
/// the app nests them):
/// `surface` = terminal background, `surfaceContainerLow` = sidebar,
/// `surfaceContainer` = surface, `surfaceContainerHigh` = surfaceHigh,
/// `surfaceContainerHighest` = one step beyond, `secondaryContainer` = the
/// selected-row fill.
ColorScheme terminalDerivedColorScheme(CmuxTerminalTheme theme) {
  final p = TerminalDerivedPalette.fromTheme(theme);
  Color step(double amount) => p.isLight
      ? darkenTerminalColor(p.background, amount)
      : lightenTerminalColor(p.background, amount);

  return ColorScheme(
    brightness: p.isLight ? Brightness.light : Brightness.dark,
    primary: p.accent,
    onPrimary: p.accentForeground,
    primaryContainer: p.accent,
    onPrimaryContainer: p.accentForeground,
    secondary: p.teal,
    onSecondary: terminalOnColor(p.teal),
    secondaryContainer: p.selected,
    onSecondaryContainer: p.foreground,
    tertiary: p.purple,
    onTertiary: terminalOnColor(p.purple),
    tertiaryContainer: p.purple,
    onTertiaryContainer: terminalOnColor(p.purple),
    error: p.error,
    onError: terminalOnColor(p.error),
    errorContainer: blendTerminalColor(p.background, p.error, 0.22),
    onErrorContainer: p.foreground,
    surface: p.background,
    onSurface: p.foreground,
    onSurfaceVariant: p.foregroundDim,
    surfaceDim: darkenTerminalColor(p.background, 0.06),
    surfaceBright: lightenTerminalColor(p.background, 0.06),
    surfaceContainerLowest: p.isLight
        ? lightenTerminalColor(p.background, 0.02)
        : darkenTerminalColor(p.background, 0.05),
    surfaceContainerLow: p.sidebarBackground,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceHigh,
    surfaceContainerHighest: step(0.11),
    inverseSurface: p.foreground,
    onInverseSurface: p.background,
    inversePrimary: p.accentForeground,
    outline: p.border,
    outlineVariant: p.divider,
    surfaceTint: p.accent,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
  );
}

/// Resolves a [CmuxTerminalTheme] from a `LayoutPreferences.terminalThemeMode`
/// value.
///
/// Order: built-in catalog by stable id, then a user-imported theme by id
/// ([UserTerminalThemeRegistry]), then (for tolerance) a case-insensitive
/// display-name match against the catalog. Built-ins win on id collision, which
/// is why the user-theme repository suffixes clashing ids on save.
///
/// Returns `null` for the legacy `adaptive` / `classicDark` / `highContrast`
/// modes — and for a user theme whose file was deleted — so those fall through
/// to the scheme-driven terminal palette (and, for the UI, to the default
/// colour preset).
CmuxTerminalTheme? cmuxTerminalThemeForMode(String mode) {
  final byId = cmuxTerminalThemeById(mode);
  if (byId != null) return byId;
  final userTheme = UserTerminalThemeRegistry.instance.byId(mode);
  if (userTheme != null) return userTheme;
  final lower = mode.toLowerCase();
  for (final theme in kCmuxTerminalThemes) {
    if (theme.name.toLowerCase() == lower) return theme;
  }
  return null;
}

/// The terminal theme the UI scheme should be derived from, with the user's
/// per-slot overrides already applied, so the chrome tracks what the terminal
/// actually paints.
CmuxTerminalTheme? resolveUiTerminalTheme({
  required String mode,
  bool useCustomColors = false,
  Map<String, int> colorOverrides = const {},
}) {
  final base = cmuxTerminalThemeForMode(mode);
  if (base == null) return null;
  if (!useCustomColors || colorOverrides.isEmpty) return base;
  return applyTerminalColorOverrides(base, colorOverrides);
}

/// Cheap cache key for "would [resolveUiTerminalTheme] return a different
/// theme?" — [CmuxTerminalTheme] has no value equality, and applying overrides
/// allocates a fresh instance every call.
int uiTerminalThemeCacheKey({
  required String mode,
  required bool useCustomColors,
  required Map<String, int> colorOverrides,
}) {
  if (!useCustomColors || colorOverrides.isEmpty) {
    return Object.hash(mode, false);
  }
  final keys = colorOverrides.keys.toList()..sort();
  return Object.hash(
    mode,
    true,
    Object.hashAll(<Object>[
      for (final key in keys) ...<Object>[key, colorOverrides[key]!],
    ]),
  );
}
