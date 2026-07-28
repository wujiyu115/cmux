import 'package:path/path.dart' as p;

import '../services/io/filesystem.dart';
import '../services/io/versioned_json_store.dart';
import '../services/storage/app_storage.dart';
import '../theme/terminal/cmux_terminal_theme.dart';
import '../theme/terminal/terminal_theme_catalog.g.dart';
import '../utils/logging/logger.dart';

/// Persists user-imported terminal themes, one file per theme at
/// `{appDataRoot}/themes/{id}.json` through a [VersionedJsonStore] (version 1).
///
/// Ids are collision-free against both the built-in catalog
/// ([kCmuxTerminalThemes]) and existing user files: a clash gets a numeric
/// suffix (`dracula`, then `dracula-2`, `dracula-3`, …). A corrupt file is
/// skipped with an [appLogger] warning and never throws; a missing directory
/// yields `[]`.
class UserTerminalThemeRepository {
  UserTerminalThemeRepository({Filesystem? fs, String? directory})
    : _fsOverride = fs,
      _directoryOverride = directory;

  static const int _version = 1;

  final Filesystem? _fsOverride;
  final String? _directoryOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _directory =>
      _directoryOverride ?? p.join(AppStorage.appDataRoot, 'themes');

  String _pathFor(String id) => p.join(_directory, '$id.json');

  VersionedJsonStore<CmuxTerminalTheme> _store(String id) {
    return VersionedJsonStore<CmuxTerminalTheme>(
      fs: _fs,
      path: _pathFor(id),
      currentVersion: _version,
      decode: CmuxTerminalTheme.fromJson,
      encode: (theme) => theme.toJson(),
    );
  }

  /// Loads every user theme, sorted by display name (case-insensitive).
  /// Unreadable / corrupt files are logged and skipped; a missing directory
  /// yields `[]`.
  Future<List<CmuxTerminalTheme>> loadAll() async {
    final stat = await _fs.stat(_directory);
    if (!stat.exists) return const [];

    final entries = await _fs.listDir(_directory);
    final themes = <CmuxTerminalTheme>[];
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      if (!entry.name.endsWith('.json')) continue;
      final base = entry.name.substring(0, entry.name.length - '.json'.length);
      // Skip VersionedJsonStore siblings: `-previous` backups and quarantined
      // `.corrupt-<millis>` files.
      if (base.endsWith('-previous')) continue;
      if (base.contains('.corrupt-')) continue;

      try {
        final result = await _store(base).read();
        final theme = result.data;
        if (theme == null) {
          if (result.status != VersionedReadStatus.missing) {
            appLogger.w(
              '[user-themes] skipped unreadable theme "${entry.name}" '
              '(${result.status})',
              error: result.error,
            );
          }
          continue;
        }
        themes.add(theme);
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[user-themes] failed to load "${entry.name}", skipping',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    themes.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return themes;
  }

  /// Saves [theme], allocating a collision-free id, and returns the theme with
  /// that final id applied.
  Future<CmuxTerminalTheme> save(CmuxTerminalTheme theme) async {
    await _fs.ensureDir(_directory);
    final finalId = await _allocateId(theme.id);
    final stored = _withId(theme, finalId);
    await _store(finalId).write(stored);
    return stored;
  }

  /// Deletes the theme file (and its `-previous` backup) for [id]. A missing
  /// file is a no-op.
  Future<void> delete(String id) async {
    await _fs.removeRecursive(_pathFor(id));
    await _fs.removeRecursive(_store(id).previousPath);
  }

  /// Returns [baseId] if free, else the first `-<n>` (n≥2) suffix that collides
  /// with neither a built-in catalog id nor an existing user file.
  Future<String> _allocateId(String baseId) async {
    final builtInIds = {for (final t in kCmuxTerminalThemes) t.id};

    Future<bool> taken(String id) async {
      if (builtInIds.contains(id)) return true;
      return (await _fs.stat(_pathFor(id))).exists;
    }

    if (!await taken(baseId)) return baseId;
    for (var n = 2; ; n++) {
      final candidate = '$baseId-$n';
      if (!await taken(candidate)) return candidate;
    }
  }

  CmuxTerminalTheme _withId(CmuxTerminalTheme theme, String id) {
    return CmuxTerminalTheme(
      id: id,
      name: theme.name,
      author: theme.author,
      isDark: theme.isDark,
      background: theme.background,
      foreground: theme.foreground,
      cursor: theme.cursor,
      selection: theme.selection,
      searchHit: theme.searchHit,
      searchHitCurrent: theme.searchHitCurrent,
      searchHitFg: theme.searchHitFg,
      accent: theme.accent,
      ansi: theme.ansi,
    );
  }
}
