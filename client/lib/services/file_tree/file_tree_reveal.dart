import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/file_tree_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../workspace/workspace_tools_scope.dart';
import 'workspace_file_tree_store.dart';

/// Reveals [filePath] in [workspaceId]'s file tree.
///
/// Ensures the right-tools panel is visible, resolves the workspace's
/// retained [FileTreeCubit] from [WorkspaceFileTreeStore], waits for its
/// roots when the tree has not been opened yet (the panel mounts them a few
/// frames after becoming visible), then expands the ancestors and asks the
/// mounted [FileTreePanel] to scroll to the file.
///
/// Returns `false` when the active tools scope is unresolved, the tree fails
/// to become ready, or the path lies outside the tree's roots.
Future<bool> revealFileInWorkspaceTree(
  BuildContext context, {
  required String workspaceId,
  required String filePath,
}) async {
  final scope = WorkspaceToolsScope.maybeOf(context);
  final tools = scope?.tools;
  if (scope == null || tools == null) return false;

  final store = context.read<WorkspaceFileTreeStore>();
  final cubit = store.cubitFor(
    workspaceId,
    targetId: scope.isMixed
        ? WorkspaceFileTreeStore.mixedTargetId
        : tools.targetId,
    fs: tools.context.filesystem,
  );

  final layout = context.read<LayoutCubit>();
  if (!layout.state.preferences.rightToolsVisible) {
    await layout.setRightToolsVisible(true);
  }

  // A freshly created cubit (tree never opened this session) only gets roots
  // after the panel mounts and the lifecycle sync runs — bounded wait so
  // [FileTreeCubit.revealPath]'s root-containment check does not race it.
  for (var attempt = 0; attempt < 75; attempt++) {
    if (cubit.isClosed) return false;
    if (cubit.state.rootPaths.isNotEmpty) break;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  if (cubit.isClosed || cubit.state.rootPaths.isEmpty) return false;

  return cubit.revealPath(filePath);
}
