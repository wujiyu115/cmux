import 'package:path/path.dart' as p;

import '../services/commands/command_catalog.dart';
import '../services/io/filesystem.dart';
import '../services/io/versioned_json_store.dart';
import '../services/storage/app_storage.dart';
import '../utils/logging/logger.dart';

/// Ordered list of recently-invoked command ids, most-recent first.
class CommandMruList {
  const CommandMruList(this.ids);

  final List<String> ids;
}

/// Persists the command-palette "most recently used" order at
/// `{appDataRoot}/command-mru.json` through a [VersionedJsonStore].
///
/// On-disk envelope: `{ "version": 1, "data": { "ids": [<commandId>...] } }`,
/// most-recent first. Unknown ids (not in [CommandCatalog.v1]) are dropped on
/// load, mirroring `KeybindingRepository.load`'s defensive pruning, so a stale
/// or hand-edited file never surfaces dead entries.
class CommandMruRepository {
  CommandMruRepository({Filesystem? fs, String? path})
    : _fsOverride = fs,
      _pathOverride = path;

  /// Maximum number of ids retained; older entries fall off the tail.
  static const int cap = 30;
  static const int _version = 1;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? p.join(AppStorage.appDataRoot, 'command-mru.json');

  VersionedJsonStore<CommandMruList> _store() {
    return VersionedJsonStore<CommandMruList>(
      fs: _fs,
      path: _path,
      currentVersion: _version,
      decode: (data) {
        final raw = data['ids'];
        final ids = raw is List
            ? raw.whereType<String>().toList(growable: false)
            : const <String>[];
        return CommandMruList(ids);
      },
      encode: (value) => {'ids': value.ids},
    );
  }

  /// Loads the persisted order, pruning unknown ids and duplicates and
  /// clamping to [cap]. Never throws; a missing or corrupt file yields `[]`.
  Future<List<String>> load() async {
    try {
      final result = await _store().read();
      final ids = result.data?.ids;
      if (ids == null || ids.isEmpty) return const [];

      final known = {for (final def in CommandCatalog.v1) def.id};
      final seen = <String>{};
      final pruned = <String>[];
      for (final id in ids) {
        if (!known.contains(id)) continue;
        if (!seen.add(id)) continue;
        pruned.add(id);
        if (pruned.length >= cap) break;
      }
      return pruned;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[command-mru] load failed, resetting',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  /// Records [commandId] as the most-recently-used: moves it to the front,
  /// removing any earlier occurrence, and clamps the list to [cap].
  Future<void> touch(String commandId) async {
    try {
      final current = await load();
      final next = <String>[
        commandId,
        for (final id in current)
          if (id != commandId) id,
      ];
      final clamped = next.length > cap ? next.sublist(0, cap) : next;
      await _store().write(CommandMruList(clamped));
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[command-mru] touch failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
