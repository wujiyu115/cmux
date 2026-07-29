import 'runtime_target.dart';
import 'workspace_folder.dart';
import '../utils/workspace/workspace_path_utils.dart';

/// Emergent workspace shape from [WorkspaceFolder.targetId] uniformity (§4).
enum WorkspaceTopology {
  /// Every folder is [WorkspaceFolder.localTargetId].
  local,

  /// All folders share one non-local target (ssh / wsl).
  remote,

  /// Folders span more than one target.
  mixed,
}

/// Classifies [folders] for UI badges and member-assignment hints.
WorkspaceTopology workspaceTopologyOf(List<WorkspaceFolder> folders) {
  if (folders.isEmpty) return WorkspaceTopology.local;
  final ids = {for (final f in folders) f.targetId};
  if (ids.length > 1) return WorkspaceTopology.mixed;
  final id = ids.single;
  if (id == WorkspaceFolder.localTargetId) return WorkspaceTopology.local;
  return WorkspaceTopology.remote;
}

bool workspaceFolderIsRemote(String targetId) =>
    runtimeKindOfId(targetId) == RuntimeKind.ssh;

List<String> workspaceTargetIds(List<WorkspaceFolder> folders) {
  final seen = <String>[];
  for (final f in folders) {
    if (!seen.contains(f.targetId)) seen.add(f.targetId);
  }
  return seen;
}

List<String> folderPathsForTarget(
  List<WorkspaceFolder> folders,
  String targetId,
) => [
  for (final f in folders)
    if (f.targetId == targetId) f.path,
];

/// Resolves which machine owns [paths] in [folders] (file-tree / git panels).
String? targetIdForFolderPaths(
  List<WorkspaceFolder> folders,
  List<String> paths, {
  bool matchSubpaths = false,
}) {
  if (paths.isEmpty) return null;
  for (final raw in paths) {
    final path = raw.trim();
    if (path.isEmpty) continue;
    for (final f in folders) {
      if (workspacePathsEqual(f.path, path)) return f.targetId;
    }
  }
  if (!matchSubpaths) return null;
  for (final raw in paths) {
    final normalized = normalizeWorkspacePath(raw.trim());
    if (normalized.isEmpty) continue;
    WorkspaceFolder? best;
    var bestRootLen = -1;
    for (final f in folders) {
      final root = normalizeWorkspacePath(f.path);
      if (root.isEmpty) continue;
      if (normalized == root || normalized.startsWith('$root/')) {
        if (root.length > bestRootLen) {
          best = f;
          bestRootLen = root.length;
        }
      }
    }
    if (best != null) return best.targetId;
  }
  return null;
}

/// Workspace folders win on path collisions; session-only paths are appended.
List<WorkspaceFolder> mergeWorkspaceFolderCatalog({
  required List<WorkspaceFolder> sessionFolders,
  required List<WorkspaceFolder> workspaceFolders,
}) {
  if (workspaceFolders.isEmpty) return sessionFolders;
  final merged = <WorkspaceFolder>[...workspaceFolders];
  for (final sf in sessionFolders) {
    if (workspaceFolders.any((wf) => workspacePathsEqual(wf.path, sf.path))) {
      continue;
    }
    merged.add(sf);
  }
  return merged;
}

/// Personal launch: [primaryPath] is cwd; add-dirs are other catalog folders on
/// the same target (cross-machine paths are not reachable from one PTY).
({String workingDirectory, List<String> addDirs}) personalWorkDirsForPrimaryPath(
  List<WorkspaceFolder> catalog,
  String primaryPath,
) {
  final normalizedPrimary = normalizeWorkspacePath(primaryPath.trim());
  if (catalog.isEmpty) {
    return (
      workingDirectory: normalizedPrimary,
      addDirs: const [],
    );
  }

  final targetId =
      targetIdForFolderPaths(
        catalog,
        [normalizedPrimary],
        matchSubpaths: true,
      ) ??
      catalog.first.targetId;

  var cwd = normalizedPrimary;
  for (final folder in catalog) {
    if (folder.targetId == targetId &&
        workspacePathsEqual(folder.path, normalizedPrimary)) {
      cwd = folder.path;
      break;
    }
  }
  if (cwd.isEmpty) {
    final onTarget = folderPathsForTarget(catalog, targetId);
    cwd = onTarget.isNotEmpty ? onTarget.first : catalog.first.path;
  }

  final addDirs = <String>[
    for (final folder in catalog)
      if (folder.targetId == targetId && !workspacePathsEqual(folder.path, cwd))
        folder.path,
  ];

  return (workingDirectory: cwd, addDirs: addDirs);
}
