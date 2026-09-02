import 'package:path/path.dart' as p;

import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../io/versioned_json_store.dart';
import '../storage/app_storage.dart';

/// Persists per-root recently-opened file paths at
/// `{appDataRoot}/quick-open-mru.json` through a [VersionedJsonStore].
///
/// On-disk envelope: `{"version":1,"data":{"roots":{"<root>":[<path>...]}}}`,
/// most-recent first. [load] drops files that no longer exist on disk so the
/// empty-query list never offers dead entries. Never throws.
class QuickOpenMruRepository {
  QuickOpenMruRepository({Filesystem? fs, String? path})
    : _fsOverride = fs,
      _pathOverride = path;

  static const int cap = 50;
  static const int _version = 1;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? p.join(AppStorage.appDataRoot, 'quick-open-mru.json');

  VersionedJsonStore<Map<String, List<String>>> _store() {
    return VersionedJsonStore<Map<String, List<String>>>(
      fs: _fs,
      path: _path,
      currentVersion: _version,
      decode: (data) {
        final roots = data['roots'];
        if (roots is! Map) return {};
        return {
          for (final entry in roots.entries)
            if (entry.key is String && entry.value is List)
              entry.key as String: (entry.value as List)
                  .whereType<String>()
                  .toList(growable: false),
        };
      },
      encode: (value) => {
        'roots': {for (final e in value.entries) e.key: e.value},
      },
    );
  }

  Future<Map<String, List<String>>> _loadRaw() async {
    try {
      final result = await _store().read();
      return result.data ?? {};
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[quick-open-mru] load failed, resetting',
        error: error,
        stackTrace: stackTrace,
      );
      return {};
    }
  }

  /// Most-recent-first existing files for [root]; dead paths dropped.
  Future<List<String>> load(String root) async {
    final raw = await _loadRaw();
    final paths = raw[root];
    if (paths == null || paths.isEmpty) return const [];
    final fs = _fs;
    // WSL/SSH pay a process spawn (or round trip) per stat; batch the
    // existence check when the backend supports it.
    final batchFs = fs is FsBatchOps ? fs as FsBatchOps : null;
    Map<String, bool>? exists;
    if (batchFs != null) {
      try {
        exists = await batchFs.existsMany(paths);
      } on Object {
        exists = null; // Fall back to per-path stats.
      }
    }
    final existing = <String>[];
    for (final path in paths) {
      if (existing.length >= cap) break;
      if (exists != null) {
        if (exists[path] != true) continue;
      } else {
        final stat = await fs.stat(path);
        if (!stat.exists) continue;
      }
      if (existing.contains(path)) continue;
      existing.add(path);
    }
    return existing;
  }

  /// Records [path] as most-recent for [root], clamped to [cap].
  Future<void> touch(String root, String path) async {
    try {
      final raw = await _loadRaw();
      final current = raw[root] ?? const <String>[];
      final next = <String>[
        path,
        for (final existing in current)
          if (existing != path) existing,
      ];
      final clamped = next.length > cap ? next.sublist(0, cap) : next;
      await _store().write({...raw, root: clamped});
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[quick-open-mru] touch failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
