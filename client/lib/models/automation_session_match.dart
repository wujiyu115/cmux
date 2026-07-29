import 'app_session.dart';
import 'automation.dart';

/// Whether [automation] belongs to [session] for list filtering / dispatch.
bool automationMatchesSession(Automation automation, AppSession session) {
  if (automation.workspaceId != session.workspaceId) return false;
  if (automation.isScheduledMessage) {
    return automation.sessionId == session.sessionId;
  }
  return automation.isPersonal;
}

/// Session-scoped automation list without loading the full [AppSession].
bool automationMatchesSessionId(Automation automation, String sessionId) {
  if (automation.isScheduledMessage) {
    return automation.sessionId == sessionId;
  }
  return automation.sessionId == sessionId;
}
