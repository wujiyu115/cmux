import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import 'pairing_block_button.dart';
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
  /// Collapsed on open, regardless of how many panes the workspace has.
  ///
  /// Auto-expanding every workspace with a live pane made the list unusable on a
  /// phone: a desktop with a handful of busy workspaces opened to screens of
  /// terminal rows, and the workspace the reader came for was scrolled off. The
  /// row's own liveness pill already says which ones have something running.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final workspace = widget.workspace;
    final liveCount = workspace.panes.where((n) => n.live).length;

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
          // Shown whether or not something is already running: with no panes it
          // is the only way to get a mirrorable terminal in a dormant workspace
          // from the phone, and with panes it is the only way to add a tab —
          // host-side `session.activate` with a null paneId opens a fresh
          // terminal rather than reusing one, the same call the desktop's "new
          // terminal tab" command makes.
          if (_expanded)
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.tpSpacing.xs,
                0,
                context.tpSpacing.xs,
                context.tpSpacing.md,
              ),
              child: PairingBlockButton(
                key: AppKeys.pairingOpenTerminalButton(workspace.workspaceId),
                variant: PairingButtonVariant.outlined,
                onPressed: () => widget.onOpenNode(
                  PairingSessionNode(
                    workspaceId: workspace.workspaceId,
                    title: workspace.title,
                    subtitle: '',
                    live: false,
                  ),
                ),
                // "Open" reads as "show me the one that is there" once rows
                // are listed above the button, so a workspace with panes gets
                // the additive label instead.
                child: Text(
                  workspace.panes.isEmpty
                      ? l10n.pairingOpenTerminalHere
                      : l10n.pairingNewTerminalHere,
                ),
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
    final spacing = context.tpSpacing;
    final total = workspace.panes.length;

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
                  size: context.tpIconSizes.md,
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
                      // Middle rank: below the group header, above a terminal
                      // row. The prototype's 21 / 700 does not survive the
                      // phone-wide 15% text boost, and bold at this size fought
                      // the group header above it for attention.
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
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
    // One flat list: everything mirrorable is a terminal, so a group header
    // would separate rows that are the same kind of thing.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final pane in workspace.panes)
          PairingNodeRow(
            node: pane,
            busy: activatingKey == pane.nodeKey,
            onTap: () => onOpenNode(pane),
          ),
        SizedBox(height: context.tpSpacing.sm),
      ],
    );
  }
}
