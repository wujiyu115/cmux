import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/workspace_accent.dart';
import '../models/workspace_group.dart';
import '../services/home_workspace/workspace_groups_store.dart';

const _uuid = Uuid();

/// Reactive view of the workspace-group index. Wraps [WorkspaceGroupsStore]:
/// every mutation persists then emits, so the nav sidebar rebuilds on change.
class WorkspaceGroupsState {
  const WorkspaceGroupsState({this.groups = const [], this.loaded = false});

  final List<WorkspaceGroup> groups;
  final bool loaded;

  WorkspaceGroupsState copyWith({List<WorkspaceGroup>? groups, bool? loaded}) {
    return WorkspaceGroupsState(
      groups: groups ?? this.groups,
      loaded: loaded ?? this.loaded,
    );
  }
}

class WorkspaceGroupsCubit extends Cubit<WorkspaceGroupsState> {
  WorkspaceGroupsCubit({WorkspaceGroupsStore? store})
    : _store = store ?? WorkspaceGroupsStore(),
      super(const WorkspaceGroupsState());

  final WorkspaceGroupsStore _store;

  Future<void> load() async {
    final groups = await _store.load();
    emit(state.copyWith(groups: groups, loaded: true));
  }

  Future<void> _persist(List<WorkspaceGroup> groups) async {
    final sorted = [...groups]..sort((a, b) => a.order.compareTo(b.order));
    emit(state.copyWith(groups: sorted, loaded: true));
    await _store.save(sorted);
  }

  /// Creates a group named [name] appended after the current highest order.
  /// Returns its generated id.
  Future<String> addGroup(String name) async {
    final id = _uuid.v4();
    final nextOrder = state.groups.isEmpty
        ? 0
        : state.groups.map((g) => g.order).reduce((a, b) => a > b ? a : b) + 1;
    await _persist([
      ...state.groups,
      WorkspaceGroup(id: id, name: name.trim(), order: nextOrder),
    ]);
    return id;
  }

  Future<void> renameGroup(String id, String name) async {
    await _persist([
      for (final g in state.groups)
        if (g.id == id) g.copyWith(name: name.trim()) else g,
    ]);
  }

  Future<void> setGroupAccent(String id, WorkspaceAccentPreset? accent) async {
    await _persist([
      for (final g in state.groups)
        if (g.id == id)
          g.copyWith(accent: accent, clearAccent: accent == null)
        else
          g,
    ]);
  }

  Future<void> toggleCollapsed(String id) async {
    await _persist([
      for (final g in state.groups)
        if (g.id == id) g.copyWith(collapsed: !g.collapsed) else g,
    ]);
  }

  /// Removes the group; workspaces that referenced it fall back to ungrouped
  /// (their stale [Workspace.groupId] no longer matches any group).
  Future<void> removeGroup(String id) async {
    await _persist([
      for (final g in state.groups)
        if (g.id != id) g,
    ]);
  }

  /// Reorders [id] by [delta] steps (negative = up) and renumbers order.
  Future<void> move(String id, int delta) async {
    final ordered = [...state.groups]
      ..sort((a, b) => a.order.compareTo(b.order));
    final idx = ordered.indexWhere((g) => g.id == id);
    if (idx < 0) return;
    final target = (idx + delta).clamp(0, ordered.length - 1);
    if (target == idx) return;
    final moved = ordered.removeAt(idx);
    ordered.insert(target, moved);
    await _persist([
      for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(order: i),
    ]);
  }
}
