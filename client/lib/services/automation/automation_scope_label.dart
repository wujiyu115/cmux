
import '../../l10n/app_localizations.dart';
import '../../models/automation.dart';

/// Short subtitle for workspace sidebar rows and list grouping.
String automationScopeSubtitle(
  AppLocalizations l10n, {
  required Automation automation,
}) {
  if (automation.isScheduledMessage) {
    final sessionId = automation.sessionId?.trim();
    if (sessionId != null && sessionId.isNotEmpty) {
      return l10n.automationsScopeScheduledMessage(sessionId);
    }
    return l10n.automationsFilterScheduledMessage;
  }

  return l10n.automationsScopePersonal('');
}
