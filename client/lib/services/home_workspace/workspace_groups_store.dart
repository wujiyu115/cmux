import '../../models/workspace_group.dart';
import '../io/filesystem.dart';
import '../io/versioned_json_store.dart';
import '../storage/app_storage.dart';
import '../../utils/logging/logger.dart';

/// Persists the workspace-group index at `ui/workspace-groups.json` through a
/// [VersionedJsonStore]. Missing / corrupt files load as an empty index.
class WorkspaceGroupsStore {
  WorkspaceGroupsStore({Filesystem? fs, String? path})
    : _fsOverride = fs,
      _pathOverride = path;

  static const int _version = 1;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.homeWorkspaceWorkspaceGroupsJson;

  VersionedJsonStore<WorkspaceGroupsIndex> _store() {
    return VersionedJsonStore<WorkspaceGroupsIndex>(
      fs: _fs,
      path: _path,
      currentVersion: _version,
      decode: WorkspaceGroupsIndex.fromJson,
      encode: (value) => value.toJson(),
    );
  }

  /// Loads persisted groups sorted by [WorkspaceGroup.order]. Never throws.
  Future<List<WorkspaceGroup>> load() async {
    try {
      final result = await _store().read();
      final groups = [...?result.data?.groups]
        ..sort((a, b) => a.order.compareTo(b.order));
      return List.unmodifiable(groups);
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[workspace-groups] load failed, resetting',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  /// Overwrites the group index with [groups].
  Future<void> save(List<WorkspaceGroup> groups) async {
    try {
      await _store().write(WorkspaceGroupsIndex(groups: groups));
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[workspace-groups] save failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
