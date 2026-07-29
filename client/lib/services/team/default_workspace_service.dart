import 'package:collection/collection.dart';

import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../repositories/session_repository.dart';
import '../../services/storage/app_storage.dart';
import '../../utils/workspace/workspace_path_utils.dart';

/// First-launch bootstrap for the built-in workspace and its starter session.
abstract final class DefaultWorkspaceService {
  DefaultWorkspaceService._();

  static const defaultDisplay = 'Default';

  /// Built-in personal workspace folder: `<Documents>/TeamPilot`.
  static Future<String> resolvePrimaryPath() =>
      DefaultWorkspaceDirectory.resolveDefaultWorkspacePath();

  /// Ensures the default workspace exists with one starter session. Returns
  /// whether storage was mutated. Pass [knownWorkspaces] when the index was
  /// just loaded to avoid a second full scan.
  static Future<bool> ensureDefault(
    SessionRepository repository, {
    List<Workspace>? knownWorkspaces,
  }) async {
    final primaryPath = await resolvePrimaryPath();
    final workspaces = knownWorkspaces ?? await repository.loadWorkspaces();
    var workspace = workspaces
        .where((w) => workspacePathsEqual(w.firstFolderPath, primaryPath))
        .firstOrNull;

    var mutated = false;
    if (workspace == null) {
      workspace = await repository.createWorkspace([
        WorkspaceFolder(path: primaryPath),
      ], display: defaultDisplay);
      mutated = true;
    }

    final workspaceSessions = await repository.loadSessionsForWorkspace(
      workspace.workspaceId,
    );

    final hasSimple = workspaceSessions.any((s) => s.sessionTeam.isEmpty);
    if (!hasSimple) {
      await repository.createSession(workspace.workspaceId);
      mutated = true;
    }

    return mutated;
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
