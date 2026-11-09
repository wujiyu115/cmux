import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import 'mobile_chrome.dart';
import 'pairing_node_row.dart';

/// One workspace and its terminals, as a collapsible row in the desktop detail
/// list: chevron, folder, name, and the terminal count at the trailing edge
/// (with a liveness dot), following the reference's tree.
///
/// Hand-rolled rather than [TpDisclosure] / [ExpansionTile]: the children must
/// stay unmounted while collapsed so a busy desktop does not build every pane on
/// each expand toggle.
class PairingWorkspaceGroup extends StatefulWidget {
  const PairingWorkspaceGroup({
    super.key,
    required this.workspace,
    required this.activatingKey,
    required this.onOpenNode,
    required this.onDeleteWorkspace,
    required this.onDeleteNode,
    this.selectedCatalogId,
  });

  final PairingWorkspaceNode workspace;
  final String? activatingKey;

  /// Catalog id of the terminal the tablet sidebar's right pane is mirroring, if
  /// it belongs to this workspace. Only ever set in the two-pane layout.
  final String? selectedCatalogId;
  final ValueChanged<PairingSessionNode> onOpenNode;

  /// Long-press on the workspace header — opens the delete-workspace sheet.
  final ValueChanged<PairingWorkspaceNode> onDeleteWorkspace;

  /// Long-press on a terminal row — opens the close-pane sheet.
  final ValueChanged<PairingSessionNode> onDeleteNode;

  @override
  State<PairingWorkspaceGroup> createState() => _PairingWorkspaceGroupState();
}

class _PairingWorkspaceGroupState extends State<PairingWorkspaceGroup> {
  /// Collapsed on open, regardless of how many panes the workspace has.
  ///
  /// Auto-expanding every workspace with a live pane made the list unusable on a
  /// phone: a desktop with a handful of busy workspaces opened to screens of
  /// terminal rows, and the workspace the reader came for was scrolled off.
  bool _expanded = false;

  /// A mirror opened from *outside* the tree — a forwarded agent notice, a
  /// reconnect that resumed a pane — must not leave its row hidden in a
  /// collapsed workspace: the sidebar is the only place that says what the right
  /// pane is showing. Expanding on a selection change (rather than deriving
  /// `expanded` from the selection) keeps a manual collapse while mirroring.
  @override
  void didUpdateWidget(PairingWorkspaceGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = widget.selectedCatalogId;
    if (selected == null || selected == oldWidget.selectedCatalogId) return;
    if (widget.workspace.panes.any((pane) => pane.catalogId == selected)) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    final liveCount = workspace.panes.where((n) => n.live).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Summary(
          workspace: workspace,
          expanded: _expanded,
          liveCount: liveCount,
          onTap: () => setState(() => _expanded = !_expanded),
          onLongPress: () => widget.onDeleteWorkspace(workspace),
        ),
        if (_expanded)
          _Body(
            workspace: workspace,
            activatingKey: widget.activatingKey,
            selectedCatalogId: widget.selectedCatalogId,
            onOpenNode: widget.onOpenNode,
            onDeleteNode: widget.onDeleteNode,
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.workspace,
    required this.expanded,
    required this.liveCount,
    required this.onTap,
    required this.onLongPress,
  });

  final PairingWorkspaceNode workspace;
  final bool expanded;
  final int liveCount;
  final VoidCallback onTap;

  /// Long-press opens the delete-workspace sheet; tap stays expand/collapse.
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = workspace.panes.length;

    return InkWell(
      key: AppKeys.pairingWorkspaceHeader(workspace.workspaceId),
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  Icons.chevron_right,
                  size: 17,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.folder_outlined, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  workspace.title.isEmpty
                      ? workspace.workspaceId
                      : workspace.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (liveCount > 0) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: mobileOnlineColor(context),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
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
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.workspace,
    required this.activatingKey,
    required this.onOpenNode,
    required this.onDeleteNode,
    required this.selectedCatalogId,
  });

  final PairingWorkspaceNode workspace;
  final String? activatingKey;
  final String? selectedCatalogId;
  final ValueChanged<PairingSessionNode> onOpenNode;
  final ValueChanged<PairingSessionNode> onDeleteNode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final pane in workspace.panes)
          PairingNodeRow(
            node: pane,
            busy: activatingKey == pane.nodeKey,
            selected:
                selectedCatalogId != null &&
                selectedCatalogId == pane.catalogId,
            onTap: () => onOpenNode(pane),
            onLongPress: () => onDeleteNode(pane),
          ),
        // Shown whether or not something is already running: with no panes it
        // is the only way to get a mirrorable terminal in a dormant workspace
        // from the phone, and with panes it is the only way to add a tab —
        // host-side `session.activate` with a null paneId opens a fresh
        // terminal rather than reusing one, the same call the desktop's "new
        // terminal tab" command makes.
        InkWell(
          key: AppKeys.pairingOpenTerminalButton(workspace.workspaceId),
          onTap: () => onOpenNode(
            PairingSessionNode(
              workspaceId: workspace.workspaceId,
              title: workspace.title,
              subtitle: '',
              live: false,
            ),
          ),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 10, 4, 14),
            child: Row(
              children: [
                Icon(Icons.add, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  workspace.panes.isEmpty
                      ? l10n.pairingOpenTerminalHere
                      : l10n.pairingNewTerminalHere,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
