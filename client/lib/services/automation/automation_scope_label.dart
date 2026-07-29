import 'package:collection/collection.dart';

import '../../cubits/cli_presets_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/automation.dart';

/// Short subtitle for workspace sidebar rows and list grouping.
String automationScopeSubtitle(
  AppLocalizations l10n, {
  required Automation automation,
  required CliPresetsState presets,
}) {
  if (automation.isScheduledMessage) {
    final sessionId = automation.sessionId?.trim();
    if (sessionId != null && sessionId.isNotEmpty) {
      return l10n.automationsScopeScheduledMessage(sessionId);
    }
    return l10n.automationsFilterScheduledMessage;
  }

  return l10n.automationsScopePersonal(_presetLabel(automation, presets));
}

String _presetLabel(Automation automation, CliPresetsState presets) {
  final presetId = automation.presetId?.trim() ?? '';
  if (presetId.isEmpty) return '';
  final match = presets.presets.where((p) => p.id == presetId).firstOrNull;
  return match?.name.trim() ?? presetId;
}
