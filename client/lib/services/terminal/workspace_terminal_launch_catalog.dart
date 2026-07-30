import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/workspace_folder.dart';
import '../../models/workspace_terminal_session_spec.dart';
import '../../models/workspace_topology.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../host/host_interactive_shell.dart';
import '../host/wsl_distro_lookup.dart';
import '../terminal/workspace_shell_connector.dart';

enum WorkspaceTerminalLaunchAction {
  openSession,
  newSshProfile,
  settings,
  newWorktree,
  refreshWorktrees,
}

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

  const WorkspaceTerminalLaunchMenuItem.newWorktree()
    : spec = null,
      label = '',
      action = WorkspaceTerminalLaunchAction.newWorktree,
      isDivider = false;

  const WorkspaceTerminalLaunchMenuItem.refreshWorktrees()
    : spec = null,
      label = '',
      action = WorkspaceTerminalLaunchAction.refreshWorktrees,
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
    final seen = <String>{};
    for (final shell in HostInteractiveShell.discoverSpecs()) {
      // COMSPEC and the hard-coded System32 path resolve to the same cmd.exe
      // with different casing; canonicalize so it appears once.
      if (!seen.add(_normalizedPath(shell.executable))) continue;
      items.add(
        WorkspaceTerminalLaunchMenuItem.session(
          spec: WorkspaceTerminalLocalSpec(shell.executable),
          label: shell.menuLabel,
        ),
      );
    }
    return items;
  }

  /// Shell-launch entries only (local shells, WSL distros, workspace remote
  /// targets, SSH profiles), deduped. Tools (new worktree / new SSH / settings)
  /// are composed separately by the "+" menu so shells and tools stay grouped.
  static Future<List<WorkspaceTerminalLaunchMenuItem>> build({
    required List<WorkspaceFolder> folders,
    required SshProfileRepository sshProfiles,
    required WorkspaceShellConnector connector,
  }) async {
    final items = <WorkspaceTerminalLaunchMenuItem>[];
    final seen = <String>{};

    void addSession(WorkspaceTerminalSessionSpec spec, String label) {
      if (!seen.add(spec.titleBaseKey)) return;
      items.add(
        WorkspaceTerminalLaunchMenuItem.session(spec: spec, label: label),
      );
    }

    for (final shell in buildLocalShells()) {
      addSession(shell.spec!, shell.label);
    }

    for (final distro in await WslDistroLookup.list()) {
      addSession(
        WorkspaceTerminalWorkspaceTargetSpec('wsl:$distro'),
        'WSL · $distro',
      );
    }

    final remoteTargets = workspaceTargetIds(folders)
        .where((id) => id != WorkspaceFolder.localTargetId);
    for (final targetId in remoteTargets) {
      final spec = WorkspaceTerminalWorkspaceTargetSpec(targetId);
      // A WSL folder target overlaps the enumerated distro above; addSession
      // dedupes on titleBaseKey so it is not listed twice.
      addSession(spec, await connector.labelForSpec(spec));
    }

    for (final profile in await sshProfiles.loadAll()) {
      addSession(
        WorkspaceTerminalSshProfileSpec(profile.id),
        profile.hostIdentifier,
      );
    }

    return items;
  }

  static String _normalizedPath(String path) {
    final trimmed = path.trim();
    return Platform.isWindows ? trimmed.toLowerCase() : trimmed;
  }
}
