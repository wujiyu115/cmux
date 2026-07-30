import 'package:flutter/foundation.dart';

import '../../models/workspace_folder.dart';
import '../../models/workspace_terminal_session_spec.dart';
import '../../models/workspace_topology.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../host/host_interactive_shell.dart';
import '../host/wsl_distro_lookup.dart';
import '../terminal/workspace_shell_connector.dart';

enum WorkspaceTerminalLaunchAction { openSession, newSshProfile, settings }

/// One choice in a workspace "default terminal" picker: a label plus the
/// encoded [Workspace.defaultShell] value it selects (`null` = global default).
@immutable
class WorkspaceDefaultTerminalOption {
  const WorkspaceDefaultTerminalOption({required this.label, this.value});

  final String label;

  /// Encoded shell: a local executable path, or a `wsl:*` / `ssh:*` / `local`
  /// target id. `null` means "follow the global default".
  final String? value;
}

@immutable
class WorkspaceTerminalLaunchMenuItem {
  const WorkspaceTerminalLaunchMenuItem.session({
    required this.spec,
    required this.label,
  }) : action = WorkspaceTerminalLaunchAction.openSession,
       isDivider = false;

  const WorkspaceTerminalLaunchMenuItem.divider()
    : spec = null,
      label = '',
      action = WorkspaceTerminalLaunchAction.openSession,
      isDivider = true;

  const WorkspaceTerminalLaunchMenuItem.newSsh()
    : spec = null,
      label = '',
      action = WorkspaceTerminalLaunchAction.newSshProfile,
      isDivider = false;

  const WorkspaceTerminalLaunchMenuItem.settings()
    : spec = null,
      label = '',
      action = WorkspaceTerminalLaunchAction.settings,
      isDivider = false;

  final WorkspaceTerminalSessionSpec? spec;
  final String label;
  final WorkspaceTerminalLaunchAction action;
  final bool isDivider;
}

/// IDEA-style “+ ▾” menu: local shells, workspace targets, SSH profiles.
abstract final class WorkspaceTerminalLaunchCatalog {
  WorkspaceTerminalLaunchCatalog._();

  /// Candidates for a workspace "default terminal" setting (图 12c / 图 09):
  /// a "global default" sentinel, every discovered local shell, and each WSL
  /// distro. [globalDefaultLabel] localizes the sentinel row.
  static Future<List<WorkspaceDefaultTerminalOption>> buildDefaultTerminalOptions({
    required String globalDefaultLabel,
  }) async {
    final options = <WorkspaceDefaultTerminalOption>[
      WorkspaceDefaultTerminalOption(label: globalDefaultLabel),
    ];
    for (final shell in HostInteractiveShell.discoverSpecs()) {
      options.add(
        WorkspaceDefaultTerminalOption(
          label: shell.menuLabel,
          value: shell.executable,
        ),
      );
    }
    for (final distro in await WslDistroLookup.list()) {
      options.add(
        WorkspaceDefaultTerminalOption(label: 'WSL · $distro', value: 'wsl:$distro'),
      );
    }
    return options;
  }

  static List<WorkspaceTerminalLaunchMenuItem> buildLocalShells() {
    final items = <WorkspaceTerminalLaunchMenuItem>[];
    for (final shell in HostInteractiveShell.discoverSpecs()) {
      items.add(
        WorkspaceTerminalLaunchMenuItem.session(
          spec: WorkspaceTerminalLocalSpec(shell.executable),
          label: shell.menuLabel,
        ),
      );
    }
    return items;
  }

  static Future<List<WorkspaceTerminalLaunchMenuItem>> build({
    required List<WorkspaceFolder> folders,
    required SshProfileRepository sshProfiles,
    required WorkspaceShellConnector connector,
  }) async {
    final items = buildLocalShells();

    final distros = await WslDistroLookup.list();
    if (distros.isNotEmpty) {
      items.add(const WorkspaceTerminalLaunchMenuItem.divider());
      for (final distro in distros) {
        items.add(
          WorkspaceTerminalLaunchMenuItem.session(
            spec: WorkspaceTerminalWorkspaceTargetSpec('wsl:$distro'),
            label: 'WSL · $distro',
          ),
        );
      }
    }

    final remoteTargets = workspaceTargetIds(folders)
        .where((id) => id != WorkspaceFolder.localTargetId)
        .toList(growable: false);
    if (remoteTargets.isNotEmpty) {
      items.add(const WorkspaceTerminalLaunchMenuItem.divider());
      for (final targetId in remoteTargets) {
        final spec = WorkspaceTerminalWorkspaceTargetSpec(targetId);
        final label = await connector.labelForSpec(spec);
        items.add(
          WorkspaceTerminalLaunchMenuItem.session(spec: spec, label: label),
        );
      }
    }

    final profiles = await sshProfiles.loadAll();
    items.add(const WorkspaceTerminalLaunchMenuItem.divider());
    items.add(WorkspaceTerminalLaunchMenuItem.newSsh());
    for (final profile in profiles) {
      items.add(
        WorkspaceTerminalLaunchMenuItem.session(
          spec: WorkspaceTerminalSshProfileSpec(profile.id),
          label: profile.hostIdentifier,
        ),
      );
    }

    items.add(const WorkspaceTerminalLaunchMenuItem.divider());
    items.add(WorkspaceTerminalLaunchMenuItem.settings());
    return items;
  }
}
