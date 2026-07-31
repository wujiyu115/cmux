import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import 'pairing_node_row.dart';

/// One workspace and its nodes, as a collapsible group closed by a hairline.
///
/// Hand-rolled rather than [TpDisclosure] / [ExpansionTile]: the summary needs a
/// trailing liveness pill, and the children must stay mounted while collapsed so
/// the list doesn't rebuild every row on each expand.
class PairingWorkspaceGroup extends StatefulWidget {
  const PairingWorkspaceGroup({
    super.key,
    required this.workspace,
    required this.activatingKey,
    required this.onOpenNode,
  });

  final PairingWorkspaceNode workspace;
  final String? activatingKey;
  final ValueChanged<PairingSessionNode> onOpenNode;

  @override
  State<PairingWorkspaceGroup> createState() => _PairingWorkspaceGroupState();
}

class _PairingWorkspaceGroupState extends State<PairingWorkspaceGroup> {
  late bool _expanded = widget.workspace.panes.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final workspace = widget.workspace;
    final liveCount = [
      ...workspace.sessions,
      ...workspace.panes,
    ].where((n) => n.live).length;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Summary(
            workspace: workspace,
            expanded: _expanded,
            liveCount: liveCount,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          // Built only while open, matching the ExpansionTile behaviour this
          // replaced: a collapsed workspace costs nothing.
          if (_expanded)
            _Body(
              workspace: workspace,
              activatingKey: widget.activatingKey,
              onOpenNode: widget.onOpenNode,
            ),
          if (workspace.sessions.isEmpty && workspace.panes.isEmpty && _expanded)
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.tpSpacing.xs,
                0,
                context.tpSpacing.xs,
                context.tpSpacing.md,
              ),
              child: Text(
                l10n.pairingNoSessions,
                style: TpTextStyles.of(context).mutedSm,
              ),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.workspace,
    required this.expanded,
    required this.liveCount,
    required this.onTap,
  });

  final PairingWorkspaceNode workspace;
  final bool expanded;
  final int liveCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final total = workspace.sessions.length + workspace.panes.length;

    return InkWell(
      key: AppKeys.pairingWorkspaceHeader(workspace.workspaceId),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.xs,
            vertical: spacing.sm,
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      workspace.title.isEmpty
                          ? workspace.workspaceId
                          : workspace.title,
                      style: styles.mdSemibold,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: spacing.xxs),
                    Text(
                      '$total',
                      style: appMonoTextStyle(
                        context,
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              TpStatusBadge(
                label: liveCount > 0
                    ? l10n.pairingLiveBadge
                    : l10n.pairingOfflineBadge,
                tone: liveCount > 0
                    ? TpStatusBadgeTone.success
                    : TpStatusBadgeTone.neutral,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.workspace,
    required this.activatingKey,
    required this.onOpenNode,
  });

  final PairingWorkspaceNode workspace;
  final String? activatingKey;
  final ValueChanged<PairingSessionNode> onOpenNode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (workspace.sessions.isNotEmpty) ...[
          _GroupHeader(l10n.pairingPersistedSessions),
          for (final session in workspace.sessions)
            PairingNodeRow(
              node: session,
              busy: activatingKey == session.nodeKey,
              onTap: () => onOpenNode(session),
            ),
        ],
        if (workspace.panes.isNotEmpty) ...[
          _GroupHeader(l10n.pairingLiveTerminals),
          for (final pane in workspace.panes)
            PairingNodeRow(
              node: pane,
              busy: activatingKey == pane.nodeKey,
              onTap: () => onOpenNode(pane),
            ),
        ],
        SizedBox(height: context.tpSpacing.sm),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final spacing = context.tpSpacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.xs, spacing.sm, spacing.xs, spacing.xs),
      child: Text(
        label,
        style: TpTextStyles.of(
          context,
        ).xsColored(Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
