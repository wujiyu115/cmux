import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../repositories/session_repository.dart';
import '../storage/app_storage.dart';
import '../../utils/workspace/workspace_path_utils.dart';

/// First-launch bootstrap for the built-in workspace.
abstract final class DefaultWorkspaceService {
  DefaultWorkspaceService._();

  static const defaultDisplay = 'Default';

  /// Built-in personal workspace folder: `<Documents>/TeamPilot`.
  static Future<String> resolvePrimaryPath() =>
      DefaultWorkspaceDirectory.resolveDefaultWorkspacePath();

  /// Ensures the default workspace exists. Returns whether storage was mutated.
  /// Pass [knownWorkspaces] when the index was just loaded to avoid a second
  /// full scan.
  ///
  /// No starter session record is written: opening a workspace materialises its
  /// terminals through [WorkspaceTerminalRegistry], so a seeded `session.json`
  /// would only be an on-disk record nothing reads.
  static Future<bool> ensureDefault(
    SessionRepository repository, {
    List<Workspace>? knownWorkspaces,
  }) async {
    final workspaces = knownWorkspaces ?? await repository.loadWorkspaces();
    // Only seed on a truly empty first launch. Once the user owns any
    // workspace, never recreate "Default" — that made it undeletable.
    if (workspaces.isNotEmpty) return false;

    final primaryPath = await resolvePrimaryPath();
    await repository.createWorkspace([
      WorkspaceFolder(path: primaryPath),
    ], display: defaultDisplay);
    return true;
  }

  /// Idempotent — safe to call on every bootstrap.
  static Future<Workspace> seed(SessionRepository repository) async {
    final primaryPath = await resolvePrimaryPath();
    await ensureDefault(repository);
    final workspaces = await repository.loadWorkspaces();
    return workspaces
        .where((w) => workspacePathsEqual(w.firstFolderPath, primaryPath))
        .first;
  }
}
