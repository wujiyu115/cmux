import '../../cubits/chat/model/chat_tab.dart';
import '../../models/app_session.dart';
import '../../models/cli_tool.dart';

/// CLI brand shown on a workspace session tab.
CliTool resolveSessionTabCli({
  required ChatTab tab,
  required List<AppSession> sessions,
  CliTool? personalFallbackCli,
}) {
  final session = _sessionForTab(tab, sessions);
  return session?.cli ?? personalFallbackCli ?? CliTool.claude;
}

AppSession? _sessionForTab(ChatTab tab, List<AppSession> sessions) {
  final cached = tab.persistedSession;
  if (cached != null) return cached;
  final tabId = tab.info.id;
  if (tabId.startsWith('local-')) return null;
  for (final s in sessions) {
    if (s.sessionId == tabId) return s;
  }
  return null;
}
