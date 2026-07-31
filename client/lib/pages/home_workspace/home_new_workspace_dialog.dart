import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/workspace_groups_cubit.dart';
import '../../models/workspace_accent.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_group.dart';
import '../../repositories/session_repository.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../services/terminal/workspace_terminal_launch_catalog.dart';
import '../../theme/workspace_accent_palette.dart';
import '../../widgets/workspace_create_directory_picker.dart';
import '../../l10n/l10n_extensions.dart';
import 'workspace_accent_picker.dart';

typedef NewWorkspaceResult = ({
  List<WorkspaceFolder> folders,
  String display,
  String? defaultShell,
  String groupId,
  WorkspaceAccentPreset? accent,
});

/// Large centered "create workspace" modal launched from the workspace workspaces
/// toolbar.
Future<void> showHomeNewWorkspaceDialog(
  BuildContext context, {
  required ChatCubit chatCubit,
  required SessionRepository repository,
}) async {
  final result = await showDialog<NewWorkspaceResult>(
    context: context,
    builder: (_) => const HomeNewWorkspaceDialog(),
  );
  if (result == null || !context.mounted || result.folders.isEmpty) return;

  final workspaceId = await chatCubit.createWorkspace(
    result.folders,
    repository,
    display: result.display,
    allowDuplicate: true,
  );
  final hasMetadata = result.defaultShell != null ||
      result.groupId.isNotEmpty ||
      result.accent != null;
  if (hasMetadata) {
    await chatCubit.updateWorkspaceMetadata(
      repository,
      workspaceId,
      defaultShell: result.defaultShell,
      groupId: result.groupId,
      accent: result.accent,
    );
  }
  if (!context.mounted) return;
  context.go('/home-v2/workspace/$workspaceId');
}

class HomeNewWorkspaceDialog extends StatefulWidget {
  const HomeNewWorkspaceDialog({super.key});

  @override
  State<HomeNewWorkspaceDialog> createState() => _HomeNewWorkspaceDialogState();
}

class _HomeNewWorkspaceDialogState extends State<HomeNewWorkspaceDialog> {
  late final TextEditingController _nameController;
  var _targetId = WorkspaceFolder.localTargetId;
  var _folders = <WorkspaceFolder>[];

  List<WorkspaceDefaultTerminalOption> _terminalOptions = const [];
  WorkspaceDefaultTerminalOption? _terminal;

  /// Set once the user picks a terminal by hand — suppresses auto-matching so a
  /// later directory change never clobbers their explicit choice.
  bool _terminalTouched = false;
  String _groupId = '';
  WorkspaceAccentPreset? _accent;
  bool _optionsRequested = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_optionsRequested) return;
    _optionsRequested = true;
    _loadTerminalOptions(context.l10n.workspaceDefaultTerminalGlobal);
  }

  Future<void> _loadTerminalOptions(String globalLabel) async {
    final options =
        await WorkspaceTerminalLaunchCatalog.buildDefaultTerminalOptions(
      globalDefaultLabel: globalLabel,
    );
    if (!mounted) return;
    setState(() {
      _terminalOptions = options;
      _terminal = options.isEmpty ? null : options.first;
      _autoMatchTerminal();
    });
  }

  /// Aligns the default terminal to the primary folder's machine: a WSL folder
  /// (`wsl:<distro>` targetId) selects that distro's WSL terminal, matching the
  /// option whose [WorkspaceDefaultTerminalOption.value] equals the targetId.
  /// No-op once the user has chosen a terminal manually. Local folders keep the
  /// global default (there is no `local` option value to match).
  void _autoMatchTerminal() {
    if (_terminalTouched || _terminalOptions.isEmpty) return;
    final targetId = _folders.isEmpty ? '' : _folders.first.targetId.trim();
    if (targetId.isEmpty) return;
    for (final option in _terminalOptions) {
      if (option.value == targetId) {
        _terminal = option;
        return;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  static String _basename(String path) {
    final parts = path.replaceAll(r'\', '/').split('/')
      ..removeWhere((p) => p.isEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  void _onTargetChanged(String next) {
    if (next == _targetId) return;
    setState(() => _targetId = next);
  }

  void _submit() {
    final valid = _folders.where((f) => f.path.trim().isNotEmpty).toList();
    if (valid.isEmpty) return;
    Navigator.of(context).pop((
      folders: List<WorkspaceFolder>.unmodifiable(valid),
      display: _nameController.text.trim(),
      defaultShell: _terminal?.value,
      groupId: _groupId,
      accent: _accent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final hasDirectory = _folders.isNotEmpty;
    final firstPath = hasDirectory ? _folders.first.path : '';
    final groups = context.watch<WorkspaceGroupsCubit>().state.groups;
    final ungrouped = WorkspaceGroup(id: '', name: l10n.workspaceNavUngrouped);
    final groupItems = [ungrouped, ...groups];
    final selectedGroup =
        groupItems.firstWhere((g) => g.id == _groupId, orElse: () => ungrouped);

    return TpDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.newWorkspace),
          const SizedBox(height: 8),
          Text(
            l10n.homeWorkspaceNewWorkspaceSubtitle,
            textAlign: TextAlign.center,
            style: styles.mdColored(cs.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          WorkspaceCreateDirectoryPicker(
            targetId: _targetId,
            onTargetChanged: _onTargetChanged,
            folders: _folders,
            onFoldersChanged: (next) => setState(() {
              _folders = next;
              _autoMatchTerminal();
            }),
          ),
          const SizedBox(height: 16),
          WorkspaceCreateNameField(
            controller: _nameController,
            hint: hasDirectory
                ? _basename(firstPath)
                : l10n.homeWorkspaceNewWorkspaceNameHint,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _LabeledField(
                  label: l10n.workspaceDefaultTerminal,
                  child: TpSelect<WorkspaceDefaultTerminalOption>(
                    items: _terminalOptions,
                    initialItem: _terminal,
                    itemLabel: (o) => o.label,
                    searchable: false,
                    onChanged: (o) => setState(() {
                      _terminal = o;
                      _terminalTouched = true;
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LabeledField(
                  label: l10n.workspaceMoveToGroup,
                  child: TpSelect<WorkspaceGroup>(
                    items: groupItems,
                    initialItem: selectedGroup,
                    itemLabel: (g) =>
                        g.name.isEmpty ? l10n.workspaceNavUngrouped : g.name,
                    searchable: false,
                    onChanged: (g) => setState(() => _groupId = g?.id ?? ''),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _LabeledField(
                label: l10n.workspaceAccentColor,
                child: _AccentButton(
                  accent: _accent,
                  onTap: () async {
                    final pick = await showWorkspaceAccentPickerDialog(
                      context,
                      current: _accent,
                    );
                    if (pick != null) setState(() => _accent = pick.accent);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: hasDirectory ? _submit : null,
                child: Text(l10n.homeWorkspaceCreateWorkspace),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: styles.xsColored(cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _AccentButton extends StatelessWidget {
  const _AccentButton({required this.accent, required this.onTap});

  final WorkspaceAccentPreset? accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = accent == null
        ? cs.outlineVariant
        : workspaceAccentColor(context, accent);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outlineVariant),
        ),
        child: accent == null
            ? Icon(
                Icons.palette_outlined,
                size: context.tpIconSizes.sm,
                color: cs.onSurfaceVariant,
              )
            : Icon(Icons.check, size: context.tpIconSizes.sm, color: Colors.white),
      ),
    );
  }
}
