import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/model/session_open_status.dart';
import '../../models/app_session.dart';
import '../../models/workspace.dart';

/// Pre-flight checks before surfacing a session tab.
SessionOpenStatus? validateSessionOpenRequest({
  required SessionOpenRequest request,
  required AppSession session,
  required Workspace? Function(String workspaceId) workspaceById,
}) {
  final workspace = request.workspace ?? workspaceById(session.workspaceId);
  if (workspace == null) return SessionOpenStatus.missingWorkspace;
  return null;
}
