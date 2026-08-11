import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_typography_scale.dart';
import '../../utils/ui/app_keys.dart';
import 'pairing_nav_bar.dart';
import 'pairing_new_group_sheet.dart';
import 'pairing_new_workspace_sheet.dart';
import 'pairing_workspace_group.dart';

/// A paired desktop's workspace tree: every workspace — including dormant ones
/// with nothing running — as a collapsible group listing its live terminals.
/// Tapping one opens its live mirror; a dormant workspace offers to open a
/// terminal host-side first. Workspaces are folded by their desktop group when
/// the host advertises any.
class PairingSessionListPage extends StatelessWidget {
  const PairingSessionListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PairingClientCubit, PairingClientState>(
      builder: (context, state) {
        final l10n = context.l10n;
        final cubit = context.read<PairingClientCubit>();
        final spacing = context.tpSpacing;
        return Scaffold(
          key: AppKeys.pairingSessionListPage,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PairingNavBar(
                  title: state.activeHostName ?? l10n.pairingDesktopFallback,
                  onBack: cubit.cancel,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PairingNavAction(
                        icon: Icons.add,
                        tooltip: l10n.pairingCreate,
                        onTap: () => _openCreateMenu(context, cubit, state),
                      ),
                      PairingNavAction(
                        icon: Icons.refresh,
                        tooltip: l10n.pairingRefresh,
                        onTap: cubit.refreshWorkspaces,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: cubit.refreshWorkspaces,
                    child: ListView(
                      // A ListView even when empty, so pull-to-refresh keeps
                      // working with nothing to show.
                      padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                      children: [
                        const _ConnectionRow(),
                        if (state.workspaces.isEmpty)
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.5,
                            child: Center(child: Text(l10n.pairingNoWorkspaces)),
                          )
                        else
                          ..._buildTree(state, cubit),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(l10n.pairingNewWorkspace),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showPairingNewWorkspaceSheet(context, cubit, groups, targets);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_special_outlined),
              title: Text(l10n.pairingNewGroup),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showPairingNewGroupSheet(context, cubit);
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
  List<Widget> _buildTree(PairingClientState state, PairingClientCubit cubit) {
    final workspaces = state.workspaces;
    final groups = [...state.groups]..sort((a, b) => a.order.compareTo(b.order));

    if (groups.isEmpty) {
      return [
        for (final workspace in workspaces)
          _workspaceTile(state, workspace, cubit),
      ];
    }

    final knownIds = {for (final g in groups) g.id};
    final widgets = <Widget>[];
    for (final group in groups) {
      final members = [
        for (final w in workspaces)
          if (w.groupId == group.id) w,
      ];
      widgets.add(
        _GroupSection(
          title: group.name,
          count: members.length,
          children: [
            for (final w in members) _workspaceTile(state, w, cubit),
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
            for (final w in orphans) _workspaceTile(state, w, cubit),
          ],
        ),
      );
    }
    return widgets;
  }

  Widget _workspaceTile(
    PairingClientState state,
    PairingWorkspaceNode ws,
    PairingClientCubit cubit,
  ) {
    return PairingWorkspaceGroup(
      workspace: ws,
      activatingKey: state.activatingKey,
      onOpenNode: cubit.activateAndOpen,
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
    final spacing = context.tpSpacing;
    final title = widget.title ?? context.l10n.workspaceNavUngrouped;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.xs,
              vertical: spacing.sm,
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    Icons.chevron_right,
                    size: context.tpIconSizes.sm,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                SizedBox(width: spacing.xs),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: spacing.sm),
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

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final typography = context.appTypography;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.md),
      child: Row(
        children: [
          TpStatusBadge(
            label: context.l10n.pairingConnectedBadge,
            tone: TpStatusBadgeTone.success,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: BlocSelector<PairingClientCubit, PairingClientState, String?>(
              selector: (state) => state.activeHostUrl,
              builder: (context, url) => url == null
                  ? const SizedBox.shrink()
                  : Text(
                      url,
                      style: appMonoTextStyle(
                        context,
                        fontSize: typography.bodySmall,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
