import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../models/layout_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/workspace_surface_layers.dart';
import 'terminal_session.dart';
import 'terminal_theme_mapper.dart';

/// Resolves the embedded terminal theme from layout prefs (no BuildContext).
///
/// Used at member PTY connect so background shells get the same COLORFGBG as
/// the foreground workbench terminal — Claude `theme: auto` reads that env at
/// startup.
TerminalTheme resolveTerminalThemeFromLayout({
  required LayoutPreferences preferences,
  required Brightness platformBrightness,
}) {
  final resolved = preferences.resolveColorTheme(
    platformDark: platformBrightness == Brightness.dark,
  );
  final isDark = resolved.brightness == Brightness.dark;
  final colorScheme = resolveThemeDataFor(resolved.themeId).colorScheme;
  return teampilotTerminalTheme(
    colorScheme,
    isDark: isDark,
    mode: resolved.terminalMode,
    chrome: WorkspacePageChrome.workspace,
    useCustomColors: preferences.useCustomTerminalColors,
    colorOverrides: preferences.terminalColorOverrides,
  );
}

/// Applies [theme] to [shell] before [TerminalSession.connect] so PTY spawn
/// advertises the correct COLORFGBG.
void applyShellTerminalThemeForLaunch(TerminalSession shell, TerminalTheme theme) {
  shell.applyTerminalTheme(theme);
}
