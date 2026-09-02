import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/workspace_groups_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/workspace_accent.dart';
import '../../models/workspace_group.dart';
import '../../models/workspace_tab_ref.dart';
import '../../repositories/session_repository.dart';
import '../../services/terminal/workspace_shell_connector.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../theme/workspace_accent_palette.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/workspace/workspace_display_name.dart';
import '../../widgets/workspace_agent_status_indicator.dart';
import '../../widgets/workspace_icon.dart';
import 'home_new_workspace_dialog.dart';
import 'home_workspace_tab_scope.dart';
import 'workspace_accent_picker.dart';
import 'workspace_nav_context_menu.dart';

/// Global workspace navigation sidebar (cmux-style): lists every workspace,
/// grouped by [WorkspaceGroup], click to open/activate the matching keep-alive
/// tab. Replaces the title-bar tab strip.
class WorkspaceNavSidebar extends StatefulWidget {
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
  State<WorkspaceNavSidebar> createState() => _WorkspaceNavSidebarState();
}

class _WorkspaceNavSidebarState extends State<WorkspaceNavSidebar> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final activeWorkspaceId =
        WorkspaceTabRef.fromLocation(widget.location)?.workspaceId;
    final openIds = widget.openTabs.map((t) => t.workspaceId).toSet();
    final workspaces = context.select<ChatCubit, List<Workspace>>(
      (c) => c.state.workspaces,
    );
    final groups = context.select<WorkspaceGroupsCubit, List<WorkspaceGroup>>(
      (c) => c.state.groups,
    );

    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? workspaces
        : [
            for (final w in workspaces)
              if (w.localizedName(l10n).toLowerCase().contains(query)) w,
          ];

    // While searching, groups collapse into a flat matching-rows list — group
    // headers only make sense against the full roster.
    final sections = query.isEmpty
        ? _buildSections(
            context: context,
            workspaces: filtered,
            groups: groups,
            activeWorkspaceId: activeWorkspaceId,
            openIds: openIds,
          )
        : [for (final w in filtered) _row(context, w, activeWorkspaceId, openIds)];

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
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: TpInput(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: l10n.workspaceNavSearchHint,
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: context.tpIconSizes.sm,
                        color: cs.onSurfaceVariant,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                TpIconButton(
                  icon: Icons.add_rounded,
                  tooltip: l10n.newWorkspace,
                  onTap: () => showHomeNewWorkspaceDialog(
                    context,
                    chatCubit: context.read<ChatCubit>(),
                    repository: context.read<SessionRepository>(),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _NavRow(
              icon: Icons.home_filled,
              label: l10n.homeWorkspaceMainWindow,
              active: activeWorkspaceId == null,
              onTap: widget.onHomeTap,
            ),
          ),
          const SizedBox(height: 6),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: sections,
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: _NavRow(
              icon: Icons.create_new_folder_outlined,
              label: l10n.workspaceNavNewGroup,
              onTap: () => _createGroup(context),
            ),
          ),
        ],
      ),
    );
  }

  _WorkspaceNavRow _row(
    BuildContext context,
    Workspace workspace,
    String? activeWorkspaceId,
    Set<String> openIds,
  ) => _WorkspaceNavRow(
    workspace: workspace,
    active: workspace.workspaceId == activeWorkspaceId,
    closable: openIds.contains(workspace.workspaceId),
    onTap: () => HomeTabScope.openInTab(context, workspace.workspaceId),
    onClose: () => widget.onCloseTab(workspace.workspaceId),
  );

  List<Widget> _buildSections({
    required BuildContext context,
    required List<Workspace> workspaces,
    required List<WorkspaceGroup> groups,
    required String? activeWorkspaceId,
    required Set<String> openIds,
  }) {
    final groupIds = groups.map((g) => g.id).toSet();
    final byGroup = <String, List<Workspace>>{};
    final ungrouped = <Workspace>[];
    for (final workspace in workspaces) {
      if (workspace.groupId.isNotEmpty && groupIds.contains(workspace.groupId)) {
        byGroup.putIfAbsent(workspace.groupId, () => []).add(workspace);
      } else {
        ungrouped.add(workspace);
      }
    }

    Widget row(Workspace workspace) =>
        _row(context, workspace, activeWorkspaceId, openIds);

    final sections = <Widget>[];
    for (final group in groups) {
      final members = byGroup[group.id] ?? const [];
      sections.add(
        _GroupHeader(group: group, count: members.length, isFirst: group == groups.first),
      );
      if (!group.collapsed) {
        sections.addAll(members.map(row));
      }
    }
    if (ungrouped.isNotEmpty) {
      if (groups.isNotEmpty) {
        sections.add(_UngroupedHeader(count: ungrouped.length));
      }
      sections.addAll(ungrouped.map(row));
    }
    return sections;
  }

  Future<void> _createGroup(BuildContext context) async {
    final l10n = context.l10n;
    final name = await showTpTextPromptDialog(
      context,
      title: l10n.workspaceNavNewGroup,
      hintText: l10n.workspaceNavGroupNameHint,
      confirmLabel: l10n.save,
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await context.read<WorkspaceGroupsCubit>().addGroup(name);
  }
}

/// Agent-status indicator for one workspace row: aggregates the seat map over
/// this workspace's sessions (ChatCubit) and its shell-terminal panes
/// (registered as `ws:<paneId>` seats), painting the matching glyph.
/// Collapsed to zero width when idle so the row layout is unchanged.
class _WorkspaceAgentStatusBadge extends StatefulWidget {
  const _WorkspaceAgentStatusBadge({required this.workspaceId});

  final String workspaceId;

  @override
  State<_WorkspaceAgentStatusBadge> createState() =>
      _WorkspaceAgentStatusBadgeState();
}

class _WorkspaceAgentStatusBadgeState
    extends State<_WorkspaceAgentStatusBadge> {
  WorkspaceTerminalRegistry? _terminals;
  VoidCallback? _terminalsSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WorkspaceTerminalRegistry? terminals;
    try {
      terminals = context.read<WorkspaceTerminalRegistry>();
    } on ProviderNotFoundException {
      terminals = null; // Harnesses may mount the sidebar without one.
    }
    if (identical(terminals, _terminals)) return;
    _detachTerminals();
    _terminals = terminals;
    // Registry notifications can fire synchronously during another widget's
    // build (e.g. groupFor creating a group); defer the rebuild to frame end.
    final sub = _terminalsSub = terminals == null
        ? null
        : () {
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          };
    if (terminals != null && sub != null) {
      terminals.changes.addListener(sub);
    }
  }

  @override
  void dispose() {
    _detachTerminals();
    super.dispose();
  }

  void _detachTerminals() {
    final terminals = _terminals;
    final sub = _terminalsSub;
    if (terminals != null && sub != null) {
      terminals.changes.removeListener(sub);
    }
    _terminals = null;
    _terminalsSub = null;
  }

  @override
  Widget build(BuildContext context) {
    final sessionIds = context.select<ChatCubit, Set<String>>(
      (cubit) => {
        for (final s in cubit.state.sessions)
          if (s.workspaceId == widget.workspaceId) s.sessionId,
      },
    );
    // Shell-terminal panes report agent status as `ws:<paneId>` seats; fold
    // them in so an agent running in a workspace shell terminal (rather than
    // a session tab) also lights the row.
    final terminals = _terminals;
    final group = terminals?.groupOf(widget.workspaceId);
    if (group != null) {
      sessionIds.addAll(
        group.entries.map((e) => WorkspaceShellConnector.seatIdFor(e.id)),
      );
    }
    final status = context.select<AgentAttentionCubit, WorkspaceAgentStatus>(
      (cubit) => cubit.state.workspaceAgentStatus(sessionIds),
    );
    if (status == WorkspaceAgentStatus.none) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: switch (status) {
          WorkspaceAgentStatus.waiting => context.l10n.workspaceNavAgentWaiting,
          WorkspaceAgentStatus.working => context.l10n.workspaceNavAgentWorking,
          WorkspaceAgentStatus.interrupted =>
            context.l10n.workspaceNavAgentInterrupted,
          WorkspaceAgentStatus.done => context.l10n.workspaceNavAgentDone,
          WorkspaceAgentStatus.none => '',
        },
        child: WorkspaceAgentStatusIndicator(status: status),
      ),
    );
  }
}

/// Plain hoverable nav row (home / new-group / create-workspace entries).
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

/// Collapsible section header for a [WorkspaceGroup]: chevron + accent dot +
/// name + count, with a hover/right-click menu for group ops.
class _GroupHeader extends StatefulWidget {
  const _GroupHeader({
    required this.group,
    required this.count,
    required this.isFirst,
  });

  final WorkspaceGroup group;
  final int count;
  final bool isFirst;

  @override
  State<_GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<_GroupHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final group = widget.group;
    final accent = workspaceAccentColor(
      context,
      group.accent,
      fallback: cs.onSurfaceVariant,
    );
    // Footprint of the trailing slot below. Derived from the icon scale, not a
    // literal: `sm` grows with the UI scale setting, and a fixed box would clip
    // the glyph at large scales.
    final actionSize = context.tpIconSizes.sm + 4;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            context.read<WorkspaceGroupsCubit>().toggleCollapsed(group.id),
        onSecondaryTapUp: (d) => _showMenu(context, d.globalPosition),
        onLongPressStart: (d) => _showMenu(context, d.globalPosition),
        child: Padding(
          padding: EdgeInsets.only(top: widget.isFirst ? 2 : 10, bottom: 2),
          child: Row(
            children: [
              Icon(
                group.collapsed
                    ? Icons.chevron_right_rounded
                    : Icons.expand_more_rounded,
                size: context.tpIconSizes.sm,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 2),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.name.isEmpty
                      ? context.l10n.workspaceNavUngrouped
                      : group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.smSemiboldColored(cs.onSurfaceVariant),
                ),
              ),
              // Constant-size trailing slot, as in [_WorkspaceNavRow]: the
              // hovered menu button is taller than the count it replaces, so
              // swapping them unconstrained grew the header and every row below
              // it shifted under the cursor. Sized to the header's own line
              // height rather than [TpIconButton.kCompactSize] (28) — a group
              // header is deliberately tighter than a workspace row, and
              // reserving 28 here would pad every header out by ~10px.
              SizedBox(
                width: actionSize,
                height: actionSize,
                child: Center(
                  child: _hovered
                      ? TpIconButton(
                          icon: Icons.more_horiz_rounded,
                          tooltip: group.name,
                          size: actionSize,
                          compact: true,
                          color: cs.onSurfaceVariant,
                          backgroundColor: Colors.transparent,
                          onTap: () {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            final pos = box == null
                                ? Offset.zero
                                : box.localToGlobal(
                                    box.size.centerRight(Offset.zero),
                                  );
                            _showMenu(context, pos);
                          },
                        )
                      : Text(
                          '${widget.count}',
                          style: styles.xsColored(
                            cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final l10n = context.l10n;
    final groupsCubit = context.read<WorkspaceGroupsCubit>();
    final group = widget.group;
    final selected = await showTpActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: TapDownDetails(globalPosition: position),
      specs: [
        TpActionMenuSpec.item(
          value: 'rename',
          icon: Icons.edit_outlined,
          label: l10n.workspaceGroupRename,
        ),
        TpActionMenuSpec.item(
          value: 'accent',
          icon: Icons.palette_outlined,
          label: l10n.workspaceGroupAccentColor,
        ),
        const TpActionMenuSpec.divider(),
        TpActionMenuSpec.item(
          value: 'up',
          icon: Icons.arrow_upward_rounded,
          label: l10n.workspaceMoveUp,
        ),
        TpActionMenuSpec.item(
          value: 'down',
          icon: Icons.arrow_downward_rounded,
          label: l10n.workspaceMoveDown,
        ),
        const TpActionMenuSpec.divider(),
        TpActionMenuSpec.item(
          value: 'delete',
          icon: Icons.delete_outline_rounded,
          label: l10n.workspaceGroupDelete,
          destructive: true,
        ),
      ],
    );
    if (selected == null || !context.mounted) return;
    switch (selected) {
      case 'rename':
        final name = await showTpTextPromptDialog(
          context,
          title: l10n.workspaceGroupRename,
          initialText: group.name,
          hintText: l10n.workspaceNavGroupNameHint,
          confirmLabel: l10n.save,
        );
        if (name != null && name.trim().isNotEmpty) {
          await groupsCubit.renameGroup(group.id, name);
        }
      case 'accent':
        final pick = await showWorkspaceAccentPickerDialog(
          context,
          current: group.accent,
        );
        if (pick != null) await groupsCubit.setGroupAccent(group.id, pick.accent);
      case 'up':
        await groupsCubit.move(group.id, -1);
      case 'down':
        await groupsCubit.move(group.id, 1);
      case 'delete':
        await groupsCubit.removeGroup(group.id);
    }
  }
}

/// Header for the implicit "ungrouped" section (only shown when groups exist).
class _UngroupedHeader extends StatelessWidget {
  const _UngroupedHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2, left: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.workspaceNavUngrouped,
              style: styles.smSemiboldColored(cs.onSurfaceVariant),
            ),
          ),
          Text(
            '$count',
            style: styles.xsColored(cs.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

/// One workspace entry: workspace icon (accent ring when set) + name, active
/// highlight, hover close, right-click context menu.
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

  void _menu(Offset position) {
    showWorkspaceNavContextMenu(
      context: context,
      position: position,
      workspace: widget.workspace,
      onClose: widget.onClose,
      closable: widget.closable,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    final active = widget.active;
    final name = widget.workspace.localizedName(l10n);
    final WorkspaceAccentPreset? accent = widget.workspace.accent;
    final Color fg = active ? cs.primary : cs.onSurfaceVariant;
    final Color background = active
        ? cs.primary.withValues(alpha: 0.14)
        : _hovered
        ? cs.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;

    Widget leading = WorkspaceIcon.fromWorkspace(
      widget.workspace,
      size: 24,
      borderRadius: 7,
      padding: 4,
    );
    if (accent != null) {
      leading = Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: workspaceAccentColor(context, accent),
            width: 1.5,
          ),
        ),
        child: leading,
      );
    }

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapUp: (d) => _menu(d.globalPosition),
          onLongPressStart: (d) => _menu(d.globalPosition),
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.only(
              left: 6,
              right: 6,
              top: 8,
              bottom: 8,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                // Active indicator bar: a solid primary rail flags the selected
                // workspace far more legibly than the old grey tint alone.
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: active ? cs.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 7),
                leading,
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
                _WorkspaceAgentStatusBadge(
                  workspaceId: widget.workspace.workspaceId,
                ),
                // Constant-size trailing slot: reserving the close affordance's
                // footprint keeps row height stable across hover.
                SizedBox(
                  width: TpIconButton.kCompactSize,
                  height: TpIconButton.kCompactSize,
                  child: _showClose
                      ? TpIconButton(
                          icon: Icons.close,
                          tooltip: l10n.closeTab,
                          size: TpIconButton.kCompactSize,
                          compact: true,
                          color: cs.onSurfaceVariant,
                          backgroundColor: Colors.transparent,
                          onTap: widget.onClose,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
