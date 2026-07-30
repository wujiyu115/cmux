import 'dart:async';
import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_terminal_session_spec.dart';
import '../../pages/ssh_profiles/ssh_profile_form_dialog.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/terminal/workspace_shell_connector.dart';
import '../../services/terminal/workspace_terminal_launch_catalog.dart';
typedef WorkspaceTerminalSessionSelected =
    void Function(WorkspaceTerminalSessionSpec spec);

/// Shows the workspace shell launch catalog at [globalPosition] (Orca-style +).
///
/// Uses [showTpActionMenuFromSpecs] (root overlay) so PTY-driven rebuilds
/// cannot tear down an anchored popover mid-stream.
Future<void> showWorkspaceTerminalLaunchMenu({
  required BuildContext context,
  required Offset globalPosition,
  required List<WorkspaceFolder> folders,
  required WorkspaceShellConnector connector,
  required WorkspaceTerminalSessionSelected onSessionSelected,
  VoidCallback? onNewWorktree,
  VoidCallback? onRefreshWorktrees,
}) async {
  final catalog = await WorkspaceTerminalLaunchCatalog.build(
    folders: folders,
    sshProfiles: context.read<SshProfileRepository>(),
    connector: connector,
  );
  if (!context.mounted) return;

  // Two isolated groups: every shell-launch entry first, then a divider, then
  // the tools (worktree management, new SSH profile, settings). Keeping shells
  // and tools apart matches the requested grouping.
  final items = <WorkspaceTerminalLaunchMenuItem>[
    ...catalog,
    const WorkspaceTerminalLaunchMenuItem.divider(),
    if (onNewWorktree != null)
      const WorkspaceTerminalLaunchMenuItem.newWorktree(),
    if (onRefreshWorktrees != null)
      const WorkspaceTerminalLaunchMenuItem.refreshWorktrees(),
    const WorkspaceTerminalLaunchMenuItem.newSsh(),
    const WorkspaceTerminalLaunchMenuItem.settings(),
  ];

  final selected =
      await showTpActionMenuFromSpecs<WorkspaceTerminalLaunchMenuItem>(
        context: context,
        globalPosition: globalPosition,
        specs: _launchMenuSpecs(context, items),
      );
  if (!context.mounted || selected == null) return;
  await _handleLaunchMenuSelection(
    context: context,
    selected: selected,
    onSessionSelected: onSessionSelected,
    onNewWorktree: onNewWorktree,
    onRefreshWorktrees: onRefreshWorktrees,
  );
}

List<TpActionMenuSpec> _launchMenuSpecs(
  BuildContext context,
  List<WorkspaceTerminalLaunchMenuItem> items,
) {
  final l10n = context.l10n;
  final specs = <TpActionMenuSpec>[];
  for (final item in items) {
    if (item.isDivider) {
      specs.add(const TpActionMenuSpec.divider());
      continue;
    }
    switch (item.action) {
      case WorkspaceTerminalLaunchAction.openSession:
        specs.add(
          TpActionMenuSpec.item(
            value: item,
            label: item.label,
            icon: Icons.terminal,
          ),
        );
      case WorkspaceTerminalLaunchAction.newSshProfile:
        specs.add(
          TpActionMenuSpec.item(
            value: item,
            label: l10n.workspaceTerminalNewSshSession,
            icon: Icons.add_link,
          ),
        );
      case WorkspaceTerminalLaunchAction.settings:
        specs.add(
          TpActionMenuSpec.item(
            value: item,
            label: l10n.workspaceTerminalSettings,
            icon: Icons.settings_outlined,
          ),
        );
      case WorkspaceTerminalLaunchAction.newWorktree:
        specs.add(
          TpActionMenuSpec.item(
            value: item,
            label: l10n.worktreeNewWorktreeTooltip,
            icon: Icons.account_tree_outlined,
          ),
        );
      case WorkspaceTerminalLaunchAction.refreshWorktrees:
        specs.add(
          TpActionMenuSpec.item(
            value: item,
            label: l10n.worktreeRefreshTooltip,
            icon: Icons.refresh_rounded,
          ),
        );
    }
  }
  return specs;
}

Future<void> _handleLaunchMenuSelection({
  required BuildContext context,
  required WorkspaceTerminalLaunchMenuItem selected,
  required WorkspaceTerminalSessionSelected onSessionSelected,
  VoidCallback? onNewWorktree,
  VoidCallback? onRefreshWorktrees,
}) async {
  switch (selected.action) {
    case WorkspaceTerminalLaunchAction.openSession:
      final spec = selected.spec;
      if (spec != null) onSessionSelected(spec);
    case WorkspaceTerminalLaunchAction.newSshProfile:
      await showSshProfileFormDialog(context);
    case WorkspaceTerminalLaunchAction.settings:
      if (!context.mounted) return;
      await showWorkspaceTerminalSettingsSheet(context);
    case WorkspaceTerminalLaunchAction.newWorktree:
      onNewWorktree?.call();
    case WorkspaceTerminalLaunchAction.refreshWorktrees:
      onRefreshWorktrees?.call();
  }
}

/// Centered theme dialog for workspace shell (also reachable from the + catalog).
Future<void> showWorkspaceTerminalSettingsSheet(BuildContext context) async {
  final l10n = context.l10n;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return BlocBuilder<LayoutCubit, LayoutState>(
        builder: (context, state) {
          // This quick dialog only exposes the three legacy presets; a catalog
          // id (chosen in the full settings section) shows as "adaptive" here.
          final rawMode = state.preferences.terminalThemeMode;
          final mode =
              (rawMode == 'classicDark' || rawMode == 'highContrast')
              ? rawMode
              : 'adaptive';
          return TpDialog(
            maxWidth: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TpDialogHeader(
                  title: l10n.workspaceTerminalSettings,
                  onClose: () => Navigator.of(ctx).pop(),
                ),
                SizedBox(height: context.tpSpacing.lg),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'adaptive',
                      label: Text(l10n.workspaceTerminalThemeAdaptive),
                    ),
                    ButtonSegment(
                      value: 'classicDark',
                      label: Text(l10n.workspaceTerminalThemeClassicDark),
                    ),
                    ButtonSegment(
                      value: 'highContrast',
                      label: Text(l10n.workspaceTerminalThemeHighContrast),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) {
                    final value = selection.firstOrNull;
                    if (value == null) return;
                    context.read<LayoutCubit>().setTerminalThemeMode(value);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
