import '../../cubits/search_cubit.dart';

/// App-level registry of long-lived [SearchCubit]s, one per open workspace
/// (mirrors [WorkspaceFileTreeStore]): switching workspace tabs must not
/// drop the query/results of a tab the user returns to. Closed tabs call
/// [removeWorkspace].
class WorkspaceSearchStore {
  WorkspaceSearchStore({required SearchCubit Function() cubitFactory})
    : _cubitFactory = cubitFactory;

  final SearchCubit Function() _cubitFactory;

  final Map<String, SearchCubit> _cubits = <String, SearchCubit>{};

  static String _key(String workspaceId) => workspaceId.trim();

  SearchCubit cubitFor(String workspaceId) {
    final key = _key(workspaceId);
    if (key.isEmpty) {
      throw ArgumentError.value(workspaceId, 'workspaceId', 'must not be empty');
    }
    return _cubits.putIfAbsent(key, _cubitFactory);
  }

  void removeWorkspace(String workspaceId) {
    _cubits.remove(_key(workspaceId))?.close();
  }

  void dispose() {
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    _cubits.clear();
  }
}
