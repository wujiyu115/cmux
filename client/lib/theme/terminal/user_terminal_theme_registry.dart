import 'package:flutter/foundation.dart';

import 'cmux_terminal_theme.dart';

/// Process-wide, synchronous lookup table for user-imported terminal themes.
///
/// Exists because [teampilotTerminalTheme] is a synchronous pure function called
/// from `build()` on every terminal repaint — it cannot await a repository read.
/// So the themes are loaded once at bootstrap (and again after an import or
/// delete) and cached here.
///
/// Also a [ChangeNotifier] so the settings picker rebuilds its "Imported" group
/// when the set changes.
class UserTerminalThemeRegistry extends ChangeNotifier {
  UserTerminalThemeRegistry();

  /// The instance the theme mapper reads. Bootstrap replaces its contents; tests
  /// may call [replaceAll] directly (and [clear] in teardown).
  static final UserTerminalThemeRegistry instance = UserTerminalThemeRegistry();

  List<CmuxTerminalTheme> _themes = const [];
  Map<String, CmuxTerminalTheme> _byId = const {};

  /// Loaded user themes, in the repository's display-name order.
  List<CmuxTerminalTheme> get themes => _themes;

  /// The user theme with [id], or null. Built-in catalog ids never reach here
  /// (the mapper checks the catalog first).
  CmuxTerminalTheme? byId(String id) => _byId[id];

  /// Replaces the cached set and notifies listeners.
  void replaceAll(List<CmuxTerminalTheme> themes) {
    _themes = List<CmuxTerminalTheme>.unmodifiable(themes);
    _byId = <String, CmuxTerminalTheme>{
      for (final theme in _themes) theme.id: theme,
    };
    notifyListeners();
  }

  /// Empties the cache (test teardown; also the safe state if a load fails).
  void clear() => replaceAll(const []);
}
