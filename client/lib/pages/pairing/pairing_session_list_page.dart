import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import 'mobile_chrome.dart';
import 'pairing_delete_sheet.dart';
import 'pairing_new_group_sheet.dart';
import 'pairing_new_workspace_sheet.dart';
import 'pairing_workspace_group.dart';

/// A paired desktop's workspace tree, in the reference's detail-screen shape:
/// circular back / more chips, an oversized host title, liveness under it, then
/// the workspace rows. The bottom bar carries the real controls this screen has
/// — an online-only filter, workspace search, and the create action.
///
/// Every workspace is listed (including dormant ones); tapping a workspace
/// unfolds its terminals, tapping a terminal opens its live mirror.
class PairingSessionListPage extends StatefulWidget {
  const PairingSessionListPage({super.key});

  @override
  State<PairingSessionListPage> createState() => _PairingSessionListPageState();
}

class _PairingSessionListPageState extends State<PairingSessionListPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _onlineOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PairingClientCubit, PairingClientState>(
      builder: (context, state) {
        final l10n = context.l10n;
        final cubit = context.read<PairingClientCubit>();
        final visible = _visibleWorkspaces(state);
        final liveWorkspaces = state.workspaces
            .where((w) => w.panes.any((p) => p.live))
            .length;
        return Scaffold(
          key: AppKeys.pairingSessionListPage,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  onBack: cubit.cancel,
                  onMore: () => _showMoreMenu(context, cubit),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: cubit.refreshWorkspaces,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                      children: [
                        Text(
                          state.activeHostName ?? l10n.pairingDesktopFallback,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        const _ConnectionStatus(),
                        const SizedBox(height: 18),
                        if (state.workspaces.isEmpty)
                          _EmptyNotice(text: l10n.pairingNoWorkspaces)
                        else if (visible.isEmpty)
                          _EmptyNotice(text: l10n.pairingNoMatchingWorkspaces)
                        else
                          ..._buildTree(context, state, cubit, visible),
                      ],
                    ),
                  ),
                ),
                _BottomBar(
                  controller: _search,
                  query: _query,
                  onlineOnly: _onlineOnly,
                  liveCount: liveWorkspaces,
                  onQueryChanged: (value) => setState(() => _query = value),
                  onToggleOnlineOnly: () =>
                      setState(() => _onlineOnly = !_onlineOnly),
                  onCreate: () => _openCreateMenu(context, cubit, state),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Search matches workspace names and their terminal titles; the online-only
  /// filter keeps workspaces that have at least one live pane.
  List<PairingWorkspaceNode> _visibleWorkspaces(PairingClientState state) {
    final query = _query.trim().toLowerCase();
    return [
      for (final workspace in state.workspaces)
        if ((!_onlineOnly || workspace.panes.any((p) => p.live)) &&
            (query.isEmpty ||
                workspace.title.toLowerCase().contains(query) ||
                workspace.panes.any(
                  (p) => p.title.toLowerCase().contains(query),
                )))
          workspace,
    ];
  }

  void _showMoreMenu(BuildContext context, PairingClientCubit cubit) {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh, size: 22),
              title: Text(l10n.pairingRefresh),
              onTap: () {
                Navigator.of(sheetContext).pop();
                cubit.refreshWorkspaces();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_off, size: 22),
              title: Text(l10n.pairingDisconnect),
              onTap: () {
                Navigator.of(sheetContext).pop();
                cubit.cancel();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom-sheet menu: create a workspace or a group. Both flows run on the
  /// desktop over the pairing channel.
  void _openCreateMenu(
    BuildContext context,
    PairingClientCubit cubit,
    PairingClientState state,
  ) {
    final l10n = context.l10n;
    final groups = state.groups;
    final targets = state.targets;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined, size: 22),
              title: Text(l10n.pairingNewWorkspace),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showPairingNewWorkspaceSheet(context, cubit, groups, targets);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_special_outlined, size: 22),
              title: Text(l10n.pairingNewGroup),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showPairingNewGroupSheet(context, cubit, groups);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Flat when the host advertises no groups (preserves the original list);
  /// otherwise folds workspaces under a collapsible section per group, with any
  /// ungrouped / orphaned workspaces in a trailing section.
  List<Widget> _buildTree(
    BuildContext context,
    PairingClientState state,
    PairingClientCubit cubit,
    List<PairingWorkspaceNode> workspaces,
  ) {
    final groups = [...state.groups]
      ..sort((a, b) => a.order.compareTo(b.order));

    if (groups.isEmpty) {
      return [
        for (final workspace in workspaces)
          _workspaceTile(context, state, workspace, cubit),
      ];
    }

    final knownIds = {for (final g in groups) g.id};
    final widgets = <Widget>[];
    for (final group in groups) {
      final members = [
        for (final w in workspaces)
          if (w.groupId == group.id) w,
      ];
      if (members.isEmpty) continue;
      widgets.add(
        _GroupSection(
          title: group.name,
          count: members.length,
          children: [
            for (final w in members) _workspaceTile(context, state, w, cubit),
          ],
        ),
      );
    }
    final orphans = [
      for (final w in workspaces)
        if (w.groupId.isEmpty || !knownIds.contains(w.groupId)) w,
    ];
    if (orphans.isNotEmpty) {
      widgets.add(
        _GroupSection(
          title: null,
          count: orphans.length,
          children: [
            for (final w in orphans) _workspaceTile(context, state, w, cubit),
          ],
        ),
      );
    }
    return widgets;
  }

  Widget _workspaceTile(
    BuildContext context,
    PairingClientState state,
    PairingWorkspaceNode ws,
    PairingClientCubit cubit,
  ) {
    return PairingWorkspaceGroup(
      workspace: ws,
      activatingKey: state.activatingKey,
      onOpenNode: cubit.activateAndOpen,
      // Long-press is the destructive affordance: tap keeps its meaning, so
      // nothing accidental can delete a workspace.
      onDeleteWorkspace: (workspace) =>
          showPairingDeleteWorkspaceSheet(context, cubit, workspace),
      onDeleteNode: (node) =>
          showPairingCloseTerminalSheet(context, cubit, node),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onMore});

  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          MobileRoundButton(
            icon: Icons.arrow_back,
            tooltip: context.l10n.back,
            onTap: onBack,
            iconSize: 19,
          ),
          const Spacer(),
          MobileRoundButton(
            key: AppKeys.pairingWorkspaceMoreButton,
            icon: Icons.more_horiz,
            tooltip: context.l10n.moreActions,
            onTap: onMore,
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: mobileOnlineColor(context),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              context.l10n.pairingConnectedBadge,
              style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
            ),
            Text(
              ' · ${context.l10n.pairingLanLabel}',
              style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 3),
        BlocSelector<PairingClientCubit, PairingClientState, String?>(
          selector: (state) => state.activeHostUrl,
          builder: (context, url) => url == null
              ? const SizedBox.shrink()
              : Text(
                  url,
                  style: appMonoTextStyle(
                    context,
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  const _EmptyNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The detail screen's floating control strip: online-only filter, workspace
/// search, and the create action. Mirrors the reference bottom bar, with real
/// behaviour behind each control instead of decorative slots.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controller,
    required this.query,
    required this.onlineOnly,
    required this.liveCount,
    required this.onQueryChanged,
    required this.onToggleOnlineOnly,
    required this.onCreate,
  });

  final TextEditingController controller;
  final String query;
  final bool onlineOnly;
  final int liveCount;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleOnlineOnly;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: mobileHairlineColor(context))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              _FilterButton(
                active: onlineOnly,
                badgeCount: liveCount,
                onTap: onToggleOnlineOnly,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SearchPill(
                  controller: controller,
                  query: query,
                  onChanged: onQueryChanged,
                ),
              ),
              const SizedBox(width: 8),
              _CreateButton(onTap: onCreate),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.active,
    required this.badgeCount,
    required this.onTap,
  });

  final bool active;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = active ? cs.onPrimary : cs.onSurface;
    return Tooltip(
      message: context.l10n.pairingOnlyOnline,
      child: SizedBox(
        width: 44,
        height: 44,
        // The badge hangs off the circle's top-right corner; it must sit
        // *outside* the clipped Material or the circle shape cuts it in half.
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Material(
                color: active ? cs.primary : mobileCardColor(context),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: AppKeys.pairingOnlineOnlyToggle,
                  onTap: onTap,
                  child: Center(
                    child: Icon(Icons.filter_list, size: 21, color: foreground),
                  ),
                ),
              ),
            ),
            if (badgeCount > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  height: 17,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // Inverted against the chip in both states: a primary badge
                    // would vanish into the active (primary) chip.
                    color: cs.onSurface,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.surface,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({
    required this.controller,
    required this.query,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: mobileCardColor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: mobileHairlineColor(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: AppKeys.pairingWorkspaceSearchField,
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 15, color: cs.onSurface),
              // The global input theme is an outlined, filled control; the pill
              // supplies both, so every state border must be switched off or a
              // focus ring is painted inside the pill.
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: context.l10n.pairingSearchWorkspaces,
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
          if (query.isNotEmpty)
            InkWell(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              borderRadius: BorderRadius.circular(12),
              child: Icon(
                Icons.cancel,
                size: 17,
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.l10n.pairingCreate,
      child: Material(
        // Inverted chip, matching the reference's white "+" on a dark sheet.
        color: cs.onSurface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: AppKeys.pairingWorkspaceCreateButton,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.add, size: 22, color: cs.surface),
          ),
        ),
      ),
    );
  }
}

/// A collapsible section grouping workspaces under a group label. A null [title]
/// renders the "ungrouped" label.
class _GroupSection extends StatefulWidget {
  const _GroupSection({
    required this.title,
    required this.count,
    required this.children,
  });

  final String? title;
  final int count;
  final List<Widget> children;

  @override
  State<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends State<_GroupSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = widget.title ?? context.l10n.workspaceNavUngrouped;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.count}',
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
        if (_expanded) ...widget.children,
      ],
    );
  }
}
