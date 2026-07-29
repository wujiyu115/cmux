import '../../cubits/chat_cubit.dart';
import '../../models/app_session.dart';
import '../session/workspace_tab_session_scope.dart';

/// Resolved UI context for a workspace tab: the active session, if any.
class WorkspaceActiveContext {
  const WorkspaceActiveContext({
    required this.isPersonal,
    this.activeSessionId,
  });

  final bool isPersonal;
  final String? activeSessionId;

  static WorkspaceActiveContext resolve({
    required ChatCubit chat,
    required String tabScopeId,
  }) {
    final activeTab = scopedActiveChatTab(chat, tabScopeId);
    final sessionId = activeTab?.info.id;
    if (sessionId != null && sessionId.isNotEmpty) {
      final session = _sessionById(chat.state.sessions, sessionId);
      if (session != null) {
        return WorkspaceActiveContext(
          isPersonal: true,
          activeSessionId: sessionId,
        );
      }
    }
    return idle;
  }

  /// No active session.
  static const idle = WorkspaceActiveContext(isPersonal: true);

  static AppSession? _sessionById(List<AppSession> sessions, String sessionId) {
    for (final session in sessions) {
      if (session.sessionId == sessionId) return session;
    }
    return null;
  }
}
