import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/runtime_target.dart';
import '../../services/cli/sessions/agent_cli_session_service.dart';
import '../../services/cli/sessions/agent_cli_sessions.dart';
import '../../utils/ui/coarse_relative_time.dart';

/// Shows the resumable CLI sessions for [directory] at [globalPosition].
///
/// The scan runs before the menu opens (same shape as
/// `showWorkspaceTerminalLaunchMenu`); picking a session runs
/// [service.resumeCommandFor] through [onRun], which types it into the pane.
Future<void> showWorkspaceTerminalResumeMenu({
  required BuildContext context,
  required Offset globalPosition,
  required AgentCliSessionService service,
  required RuntimeTarget target,
  required String directory,
  required void Function(String command) onRun,
}) async {
  final sessions = await service.listSessions(
    target: target,
    directory: directory,
  );
  if (!context.mounted) return;

  final selected = await showTpActionMenuFromSpecs<AgentCliSessionRecord>(
    context: context,
    globalPosition: globalPosition,
    specs: agentCliResumeMenuSpecs(context, sessions),
  );
  if (selected == null) return;
  onRun(service.resumeCommandFor(selected));
}

/// Menu specs grouped by CLI family, newest first inside each group.
@visibleForTesting
List<TpActionMenuSpec> agentCliResumeMenuSpecs(
  BuildContext context,
  List<AgentCliSessionRecord> sessions,
) {
  final l10n = context.l10n;
  if (sessions.isEmpty) {
    return [
      TpActionMenuSpec.item(
        value: null,
        label: l10n.workspaceTerminalResumeSessionsEmpty,
        icon: Icons.history,
        enabled: false,
      ),
    ];
  }

  final specs = <TpActionMenuSpec>[];
  var firstGroup = true;
  for (final family in AgentCliFamily.values) {
    final familySessions = sessions
        .where((session) => session.family == family)
        .toList();
    if (familySessions.isEmpty) continue;
    if (!firstGroup) specs.add(const TpActionMenuSpec.divider());
    firstGroup = false;
    specs.add(
      TpActionMenuSpec.item(
        value: null,
        label: _familyLabel(l10n, family),
        icon: _familyIcon(family),
        enabled: false,
      ),
    );
    for (final session in familySessions) {
      specs.add(
        TpActionMenuSpec.item(
          value: session,
          label: _sessionLabel(session),
          subtitle: session.updatedAt == null
              ? null
              : Text(
                  formatCoarseRelativeTime(l10n, session.updatedAt!),
                  style: TpTextStyles.of(context).sm,
                ),
          icon: _familyIcon(family),
        ),
      );
    }
  }
  return specs;
}

String _familyLabel(AppLocalizations l10n, AgentCliFamily family) =>
    switch (family) {
      AgentCliFamily.claude => l10n.agentCliFamilyClaude,
      AgentCliFamily.qoder => l10n.agentCliFamilyQoder,
      AgentCliFamily.codex => l10n.agentCliFamilyCodex,
      AgentCliFamily.opencode => l10n.agentCliFamilyOpencode,
    };

IconData _familyIcon(AgentCliFamily family) => switch (family) {
  AgentCliFamily.claude => Icons.auto_awesome,
  AgentCliFamily.qoder => Icons.bolt,
  AgentCliFamily.codex => Icons.memory,
  AgentCliFamily.opencode => Icons.code_rounded,
};

String _sessionLabel(AgentCliSessionRecord session) {
  final title = session.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  final id = session.sessionId;
  return id.length > 16 ? '${id.substring(0, 8)}…' : id;
}
