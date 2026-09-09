import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/runtime_target.dart';
import '../../services/cli/sessions/agent_cli_session_service.dart';
import '../../services/cli/sessions/agent_cli_sessions.dart';
import '../../utils/ui/coarse_relative_time.dart';

/// Marker value for the "all agents" back row of a family's session list.
class _AllAgentsBack {
  const _AllAgentsBack();
}

const _kAllAgentsBack = _AllAgentsBack();

/// Shows the resumable CLI sessions for [directory] at [globalPosition] as a
/// two-level menu: the first level lists the agent CLIs with sessions in the
/// directory, the second lists the chosen agent's sessions (with a back row).
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

  // Late-bound so the two levels can call each other (session list → back).
  late final Future<void> Function(AgentCliFamily family) showSessions;
  Future<void> showFamilies({bool instant = false}) async {
    final family = await showTpActionMenuFromSpecs<AgentCliFamily>(
      context: context,
      globalPosition: globalPosition,
      popUpAnimationStyle: instant
          ? const AnimationStyle(duration: Duration.zero)
          : null,
      specs: agentCliFamilyMenuSpecs(context, sessions),
    );
    if (family == null || !context.mounted) return;
    await showSessions(family);
  }

  showSessions = (family) async {
    final selected = await showTpActionMenuFromSpecs<Object>(
      context: context,
      globalPosition: globalPosition,
      popUpAnimationStyle: const AnimationStyle(duration: Duration.zero),
      // Session titles are long task summaries; the default 160/320 box
      // ellipsizes them into noise.
      minWidth: 320,
      specs: agentCliSessionMenuSpecs(context, family, sessions),
    );
    if (!context.mounted) return;
    if (identical(selected, _kAllAgentsBack)) {
      await showFamilies(instant: true);
      return;
    }
    if (selected is AgentCliSessionRecord) {
      onRun(service.resumeCommandFor(selected));
    }
  };

  await showFamilies();
}

/// First-level specs: one row per CLI family that has sessions, newest session
/// time as the subtitle. An empty scan collapses to one disabled row.
@visibleForTesting
List<TpActionMenuSpec> agentCliFamilyMenuSpecs(
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

  return [
    for (final family in AgentCliFamily.values)
      if (sessions.any((session) => session.family == family))
        TpActionMenuSpec.item(
          value: family,
          label: _familyLabel(l10n, family),
          icon: _familyIcon(family),
          subtitle: _newestSessionSubtitle(context, sessions, family),
          trailing: Icon(
            Icons.chevron_right,
            size: context.tpIconSizes.md,
            color: _mutedMenuColor(context),
          ),
        ),
  ];
}

/// Second-level specs: a back row, then [family]'s sessions newest first.
@visibleForTesting
List<TpActionMenuSpec> agentCliSessionMenuSpecs(
  BuildContext context,
  AgentCliFamily family,
  List<AgentCliSessionRecord> sessions,
) {
  final l10n = context.l10n;
  return [
    TpActionMenuSpec.item(
      value: _kAllAgentsBack,
      label: l10n.agentCliSessionsAllAgents,
      icon: Icons.arrow_back,
    ),
    for (final session in sessions.where((s) => s.family == family))
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
  ];
}

/// Relative time of [family]'s newest session (the input is newest-first).
Widget? _newestSessionSubtitle(
  BuildContext context,
  List<AgentCliSessionRecord> sessions,
  AgentCliFamily family,
) {
  final newest = sessions
      .where((session) => session.family == family)
      .firstOrNull;
  if (newest?.updatedAt == null) return null;
  return Text(
    formatCoarseRelativeTime(context.l10n, newest!.updatedAt!),
    style: TpTextStyles.of(context).sm,
  );
}

Color _mutedMenuColor(BuildContext context) =>
    (TpTextStyles.of(context).md.color ??
            Theme.of(context).colorScheme.onSurface)
        .withValues(alpha: 0.7);

String _familyLabel(AppLocalizations l10n, AgentCliFamily family) =>
    switch (family) {
      AgentCliFamily.claude => l10n.agentCliFamilyClaude,
      AgentCliFamily.qoder => l10n.agentCliFamilyQoder,
      AgentCliFamily.codex => l10n.agentCliFamilyCodex,
      AgentCliFamily.opencode => l10n.agentCliFamilyOpencode,
      AgentCliFamily.ohMyPi => l10n.agentCliFamilyOhMyPi,
    };

IconData _familyIcon(AgentCliFamily family) => switch (family) {
  AgentCliFamily.claude => Icons.auto_awesome,
  AgentCliFamily.qoder => Icons.bolt,
  AgentCliFamily.codex => Icons.memory,
  AgentCliFamily.opencode => Icons.code_rounded,
  AgentCliFamily.ohMyPi => Icons.functions,
};

String _sessionLabel(AgentCliSessionRecord session) {
  final title = session.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  final id = session.sessionId;
  return id.length > 16 ? '${id.substring(0, 8)}…' : id;
}
