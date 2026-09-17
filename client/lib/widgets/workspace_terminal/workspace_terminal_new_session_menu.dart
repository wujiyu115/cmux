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
import '../../theme/terminal/user_terminal_theme_registry.dart';
import '../settings/color_theme_picker.dart';
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

/// Quick colour-theme switch for the workspace shell (also reachable from the +
/// catalog). Opens the same unified [ColorThemePicker] as settings — one theme
/// drives the UI, terminal, and file browser together — and writes the chosen
/// id into whichever brightness slot is currently active.
Future<void> showWorkspaceTerminalSettingsSheet(BuildContext context) async {
  final controller = context.read<LayoutCubit>();
  final platformDark = MediaQuery.platformBrightnessOf(context) ==
      Brightness.dark;
  final prefs = controller.state.preferences;
  final currentId = switch (prefs.themeMode) {
    'light' => prefs.lightThemeId,
    'dark' => prefs.darkThemeId,
    _ => platformDark ? prefs.darkThemeId : prefs.lightThemeId,
  };
  final selected = await ColorThemePicker.show(
    context,
    selectedId: currentId,
    importedThemes: UserTerminalThemeRegistry.instance.themes,
  );
  if (selected == null || !context.mounted) return;
  await controller.setActiveColorTheme(selected, platformDark: platformDark);
}
