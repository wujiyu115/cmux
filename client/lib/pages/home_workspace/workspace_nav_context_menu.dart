import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/workspace_groups_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import '../../services/terminal/workspace_terminal_launch_catalog.dart';
import 'workspace_accent_picker.dart';
import 'workspace_actions.dart';

/// Right-click / long-press menu for a workspace row in the nav sidebar
/// (图 12): rename, icon, default terminal, move-to-group, accent, close.
Future<void> showWorkspaceNavContextMenu({
  required BuildContext context,
  required Offset position,
  required Workspace workspace,
  required VoidCallback onClose,
  bool closable = true,
}) async {
  final l10n = context.l10n;
  final tap = TapDownDetails(globalPosition: position);
  final selected = await showTpActionMenuFromSpecsAtTap<String>(
    context: context,
    tapDetails: tap,
    specs: [
      TpActionMenuSpec.item(
        value: 'rename',
        icon: Icons.edit_outlined,
        label: l10n.homeWorkspaceRenameWorkspace,
      ),
      TpActionMenuSpec.item(
        value: 'icon',
        icon: Icons.image_outlined,
        label: l10n.workspaceIcon,
      ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: 'terminal',
        icon: Icons.terminal_rounded,
        label: l10n.workspaceDefaultTerminal,
      ),
      TpActionMenuSpec.item(
        value: 'group',
        icon: Icons.folder_outlined,
        label: l10n.workspaceMoveToGroup,
      ),
      TpActionMenuSpec.item(
        value: 'accent',
        icon: Icons.palette_outlined,
        label: l10n.workspaceAccentColor,
      ),
      if (closable) ...[
        const TpActionMenuSpec.divider(),
        TpActionMenuSpec.item(
          value: 'close',
          icon: Icons.close_rounded,
          label: l10n.closeTab,
        ),
      ],
    ],
  );
  if (selected == null || !context.mounted) return;
  switch (selected) {
    case 'rename':
      await showRenameWorkspaceDialog(context, workspace);
    case 'icon':
      await context.read<ChatCubit>().editWorkspaceIcon(
        context,
        context.read<SessionRepository>(),
        workspace,
      );
    case 'terminal':
      await _pickDefaultTerminal(context, position, workspace);
    case 'group':
      await _pickGroup(context, position, workspace);
    case 'accent':
      await _pickAccent(context, workspace);
    case 'close':
      onClose();
  }
}

Future<void> _pickDefaultTerminal(
  BuildContext context,
  Offset position,
  Workspace workspace,
) async {
  final l10n = context.l10n;
  final options = await WorkspaceTerminalLaunchCatalog.buildDefaultTerminalOptions(
    globalDefaultLabel: l10n.workspaceDefaultTerminalGlobal,
  );
  if (!context.mounted) return;
  final current = workspace.defaultShell ?? '';
  final selected = await showTpActionMenuFromSpecsAtTap<int>(
    context: context,
    tapDetails: TapDownDetails(globalPosition: position),
    specs: [
      for (var i = 0; i < options.length; i++)
        TpActionMenuSpec.item(
          value: i,
          icon: options[i].value == null
              ? Icons.settings_suggest_outlined
              : Icons.terminal_rounded,
          label: options[i].label,
          selected: (options[i].value ?? '') == current,
        ),
    ],
  );
  if (selected == null || !context.mounted) return;
  final value = options[selected].value;
  await context.read<ChatCubit>().updateWorkspaceMetadata(
    context.read<SessionRepository>(),
    workspace.workspaceId,
    defaultShell: value,
    clearDefaultShell: value == null,
  );
}

Future<void> _pickGroup(
  BuildContext context,
  Offset position,
  Workspace workspace,
) async {
  final l10n = context.l10n;
  final groupsCubit = context.read<WorkspaceGroupsCubit>();
  final groups = groupsCubit.state.groups;
  final selected = await showTpActionMenuFromSpecsAtTap<String>(
    context: context,
    tapDetails: TapDownDetails(globalPosition: position),
    specs: [
      TpActionMenuSpec.item(
        value: '__remove__',
        icon: Icons.folder_off_outlined,
        label: l10n.workspaceRemoveFromGroup,
        selected: workspace.groupId.isEmpty,
      ),
      if (groups.isNotEmpty) const TpActionMenuSpec.divider(),
      for (final group in groups)
        TpActionMenuSpec.item(
          value: group.id,
          icon: Icons.folder_outlined,
          label: group.name.isEmpty ? l10n.workspaceNavUngrouped : group.name,
          selected: group.id == workspace.groupId,
        ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: '__new__',
        icon: Icons.create_new_folder_outlined,
        label: l10n.workspaceNavNewGroup,
      ),
    ],
  );
  if (selected == null || !context.mounted) return;

  String targetGroupId;
  if (selected == '__remove__') {
    targetGroupId = '';
  } else if (selected == '__new__') {
    final name = await showTpTextPromptDialog(
      context,
      title: l10n.workspaceNavNewGroup,
      hintText: l10n.workspaceNavGroupNameHint,
      confirmLabel: l10n.save,
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    targetGroupId = await groupsCubit.addGroup(name);
  } else {
    targetGroupId = selected;
  }
  if (!context.mounted) return;
  await context.read<ChatCubit>().updateWorkspaceMetadata(
    context.read<SessionRepository>(),
    workspace.workspaceId,
    groupId: targetGroupId,
  );
}

Future<void> _pickAccent(BuildContext context, Workspace workspace) async {
  final pick = await showWorkspaceAccentPickerDialog(
    context,
    current: workspace.accent,
  );
  if (pick == null || !context.mounted) return;
  await context.read<ChatCubit>().updateWorkspaceMetadata(
    context.read<SessionRepository>(),
    workspace.workspaceId,
    accent: pick.accent,
    clearAccent: pick.accent == null,
  );
}
