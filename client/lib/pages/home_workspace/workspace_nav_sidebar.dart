import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/workspace_tab_ref.dart';
import '../../models/workspace_topology.dart';
import '../../repositories/session_repository.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/workspace/workspace_display_name.dart';
import 'home_new_workspace_dialog.dart';
import 'home_workspace_tab_scope.dart';
import 'home_workspace_title_bar.dart' show workspaceTabTopologyIconData;

/// Global workspace navigation sidebar (cmux-style): lists every workspace,
/// click to open/activate the matching keep-alive tab, with a home entry and a
/// create-workspace action. Replaces the title-bar tab strip.
class WorkspaceNavSidebar extends StatelessWidget {
  const WorkspaceNavSidebar({
    required this.location,
    required this.openTabs,
    required this.onHomeTap,
    required this.onCloseTab,
    super.key,
  });

  final String location;
  final List<WorkspaceTabRef> openTabs;
  final VoidCallback onHomeTap;
  final ValueChanged<String> onCloseTab;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final activeWorkspaceId =
        WorkspaceTabRef.fromLocation(location)?.workspaceId;
    final openIds = openTabs.map((t) => t.workspaceId).toSet();
    final workspaces = context.select<ChatCubit, List<Workspace>>(
      (c) => c.state.workspaces,
    );

    return Container(
      decoration: BoxDecoration(
        color: cs.workspaceCard,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _NavRow(
              icon: Icons.home_filled,
              label: l10n.homeWorkspaceMainWindow,
              active: activeWorkspaceId == null,
              onTap: onHomeTap,
            ),
          ),
          const SizedBox(height: 6),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: workspaces.length,
              itemBuilder: (context, index) {
                final workspace = workspaces[index];
                return _WorkspaceNavRow(
                  workspace: workspace,
                  active: workspace.workspaceId == activeWorkspaceId,
                  closable: openIds.contains(workspace.workspaceId),
                  onTap: () =>
                      HomeTabScope.openInTab(context, workspace.workspaceId),
                  onClose: () => onCloseTab(workspace.workspaceId),
                );
              },
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: _NavRow(
              icon: Icons.add_rounded,
              label: l10n.newWorkspace,
              onTap: () => showHomeNewWorkspaceDialog(
                context,
                chatCubit: context.read<ChatCubit>(),
                repository: context.read<SessionRepository>(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain hoverable nav row (home / create-workspace entries).
class _NavRow extends StatefulWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final active = widget.active;
    final Color fg = active ? cs.primary : cs.onSurface;
    final Color background = active
        ? cs.primary.withValues(alpha: 0.14)
        : _hovered
        ? cs.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: context.tpIconSizes.md,
                  color: active ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: active
                        ? styles.smSemiboldColored(fg)
                        : styles.smColored(fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One workspace entry: topology glyph + name, active highlight, hover close.
class _WorkspaceNavRow extends StatefulWidget {
  const _WorkspaceNavRow({
    required this.workspace,
    required this.active,
    required this.closable,
    required this.onTap,
    required this.onClose,
  });

  final Workspace workspace;
  final bool active;
  final bool closable;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_WorkspaceNavRow> createState() => _WorkspaceNavRowState();
}

class _WorkspaceNavRowState extends State<_WorkspaceNavRow> {
  bool _hovered = false;

  bool get _showClose =>
      widget.closable && (_hovered || widget.active || Platform.isAndroid);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    final active = widget.active;
    final topology = workspaceTopologyOf(widget.workspace.folders);
    final name = widget.workspace.localizedName(l10n);
    final Color fg = active ? cs.onSurface : cs.onSurfaceVariant;
    final Color background = active
        ? cs.surfaceContainerHigh
        : _hovered
        ? cs.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.only(
              left: 10,
              right: 6,
              top: 8,
              bottom: 8,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? cs.outlineVariant.withValues(alpha: 0.7)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  workspaceTabTopologyIconData(topology),
                  size: context.tpIconSizes.md,
                  color: active ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: active
                        ? styles.smSemiboldColored(fg)
                        : styles.smColored(fg),
                  ),
                ),
                if (_showClose)
                  TpIconButton(
                    icon: Icons.close,
                    tooltip: l10n.closeTab,
                    size: TpIconButton.kCompactSize,
                    compact: true,
                    color: cs.onSurfaceVariant,
                    backgroundColor: Colors.transparent,
                    onTap: widget.onClose,
                  )
                else
                  const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
