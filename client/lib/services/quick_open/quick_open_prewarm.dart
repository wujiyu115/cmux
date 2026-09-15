import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../utils/logging/logger_utils.dart';
import '../git/git_command_runner.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_context.dart';
import '../workspace/workspace_tools_scope.dart';
import 'quick_open_index.dart';

/// Process-lifetime index cache shared by the Ctrl+P dialog host and the
/// tools-scope prewarm below, so a prewarmed root serves the next dialog
/// instantly (stale-while-revalidate).
final QuickOpenIndexRegistry sharedQuickOpenIndexRegistry =
    QuickOpenIndexRegistry();

/// The work plane quick open targets: which machine's filesystem to list and
/// which roots to index.
typedef QuickOpenPlane = ({
  String activeTargetId,
  RuntimeContext? targetContext,
  Filesystem filesystem,
  List<String> indexRoots,
});

/// Resolves the active tools plane for quick open — the same target and roots
/// the file tree mounts; a worktree session's cwd rides in [scopeState.roots].
QuickOpenPlane resolveQuickOpenPlane({
  required Workspace workspace,
  required WorkspaceToolsScopeState scopeState,
}) {
  final activeTargetId =
      scopeState.tools?.targetId ??
      (workspace.folders.isEmpty
          ? WorkspaceFolder.localTargetId
          : workspace.folders.first.targetId);
  final targetContext = scopeState.runtimeContextForTarget(activeTargetId);
  final fs = targetContext?.filesystem ?? AppStorage.fs;
  final roots = [
    for (final folder in workspace.folders)
      if (folder.targetId == activeTargetId) folder.path,
    ...scopeState.roots,
  ].where((path) => path.trim().isNotEmpty).toList();
  // Mirrors the dialog's empty-roots fallback to the workspace's first folder.
  final indexRoots = normalizeQuickOpenRoots(
    roots.isEmpty ? [workspace.firstFolderPath] : roots,
    fs.pathContext,
  );
  return (
    activeTargetId: activeTargetId,
    targetContext: targetContext,
    filesystem: fs,
    indexRoots: indexRoots,
  );
}

/// Fills the shared registry's cold entries for [workspace]'s active plane as
/// soon as the tools scope resolves, so the first Ctrl+P of the session serves
/// a warm index instead of awaiting the full remote listing. Warm entries are
/// left untouched (no revalidation kick); failures are logged and swallowed.
Future<void> prewarmQuickOpenIndex({
  required Workspace workspace,
  required WorkspaceToolsScopeState scopeState,
  QuickOpenIndexRegistry? registry,
}) async {
  if (scopeState.tools == null) return;
  final plane = resolveQuickOpenPlane(
    workspace: workspace,
    scopeState: scopeState,
  );
  final target = registry ?? sharedQuickOpenIndexRegistry;
  if (plane.targetContext case final RuntimeContext targetContext) {
    // In-place update like the dialog host: the registry keeps its (fs, root)
    // cache across dialogs, so the runner follows the active plane.
    target.gitRunner = gitCommandRunnerForContext(targetContext);
  }
  if (plane.indexRoots.isEmpty) return;
  for (final root in plane.indexRoots) {
    try {
      await target.prewarm(
        plane.filesystem,
        root,
        dirs: workspace.indexDirRules,
      );
    } on Object catch (error) {
      AppLogger.instance.d('quick-open prewarm failed for $root: $error');
    }
  }
}
