import '../../models/app_session.dart';
import '../../models/workspace_folder.dart';

class WorkspaceTargetRemapResult {
  const WorkspaceTargetRemapResult({
    required this.folders,
    required this.sessions,
  });

  final List<WorkspaceFolder> folders;
  final List<AppSession> sessions;
}

abstract final class WorkspaceTargetRemap {
  static bool usesTarget({
    required List<WorkspaceFolder> folders,
    required List<AppSession> sessions,
    required String targetId,
  }) {
    final id = targetId.trim();
    if (id.isEmpty) return false;
    if (folders.any((f) => f.targetId == id)) return true;
    for (final s in sessions) {
      if (s.folders.any((f) => f.targetId == id)) return true;
    }
    return false;
  }

  static WorkspaceTargetRemapResult apply({
    required List<WorkspaceFolder> folders,
    required List<AppSession> sessions,
    required String fromTargetId,
    required String toTargetId,
  }) {
    final from = fromTargetId.trim();
    final to = toTargetId.trim();
    if (from.isEmpty || to.isEmpty) {
      throw ArgumentError('fromTargetId and toTargetId must be non-empty');
    }
    if (from == to) {
      return WorkspaceTargetRemapResult(folders: folders, sessions: const []);
    }

    final nextFolders = [
      for (final f in folders)
        f.targetId == from ? f.copyWith(targetId: to) : f,
    ];

    final changedSessions = <AppSession>[];
    for (final s in sessions) {
      if (!s.folders.any((f) => f.targetId == from)) continue;
      changedSessions.add(
        s.copyWith(
          folders: [
            for (final f in s.folders)
              f.targetId == from ? f.copyWith(targetId: to) : f,
          ],
        ),
      );
    }

    return WorkspaceTargetRemapResult(
      folders: nextFolders,
      sessions: changedSessions,
    );
  }
}
