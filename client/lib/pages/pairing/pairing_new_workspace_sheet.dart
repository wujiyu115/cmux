import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
import 'pairing_remote_dir_browser_page.dart';

/// Bottom sheet to create a workspace on the paired desktop: pick the machine,
/// pick an existing folder on it, optionally name it, and file it under a group.
///
/// [cubit], [groups] and [targets] are captured by the caller before the sheet
/// opens (the modal route sits above the pairing shell's `BlocProvider`).
Future<void> showPairingNewWorkspaceSheet(
  BuildContext context,
  PairingClientCubit cubit,
  List<PairingGroup> groups,
  List<PairingTarget> targets,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PairingNewWorkspaceSheet(
      cubit: cubit,
      groups: groups,
      targets: targets,
    ),
  );
}

class _PairingNewWorkspaceSheet extends StatefulWidget {
  const _PairingNewWorkspaceSheet({
    required this.cubit,
    required this.groups,
    required this.targets,
  });

  final PairingClientCubit cubit;
  final List<PairingGroup> groups;

  /// The desktop's machines. Empty from a desktop that predates machine
  /// selection; a single entry means there is nothing to choose.
  final List<PairingTarget> targets;

  @override
  State<_PairingNewWorkspaceSheet> createState() =>
      _PairingNewWorkspaceSheetState();
}

/// Sentinel for the "no group" option in the group select. id empty = ungrouped.
const _ungrouped = PairingGroup(id: '', name: '', order: -1);

class _PairingNewWorkspaceSheetState extends State<_PairingNewWorkspaceSheet> {
  final _nameController = TextEditingController();
  String? _folderPath;
  PairingGroup _group = _ungrouped;

  /// The machine the folder will live on. Null when the host advertised none, in
  /// which case no `targetId` is ever sent and the host uses its default plane.
  PairingTarget? _target;

  /// Whether the name in the field was derived from the folder rather than typed.
  /// Only an auto-filled name is cleared when the machine changes — a name the
  /// user chose outlives the folder it was seeded from.
  bool _nameAutoFilled = false;
  bool _submitting = false;
  String? _error;

  /// Hidden for a single machine, not just for none: the host always lists itself,
  /// so one entry means there is nothing to pick and a one-option dropdown is
  /// pure noise.
  bool get _showTargetPicker => widget.targets.length > 1;

  @override
  void initState() {
    super.initState();
    _target = widget.targets.isEmpty ? null : widget.targets.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final picked = await showPairingRemoteDirBrowser(
      context,
      widget.cubit,
      initialPath: _folderPath,
      target: _target,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _folderPath = picked;
      // Default the name to the folder basename when the user hasn't typed one.
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = _basename(picked);
        _nameAutoFilled = true;
      }
      _error = null;
    });
  }

  /// Switching machines invalidates the folder: a path on one machine names
  /// nothing on another, and the host cannot tell the difference (`/home/me` is
  /// plausible everywhere). Clearing it is what keeps the path/target pair
  /// coherent, not a courtesy.
  void _onTargetChanged(PairingTarget? next) {
    if (next == null || next.id == _target?.id) return;
    setState(() {
      _target = next;
      _folderPath = null;
      if (_nameAutoFilled) {
        _nameController.clear();
        _nameAutoFilled = false;
      }
      _error = null;
    });
  }

  Future<void> _submit() async {
    final folder = _folderPath;
    if (_submitting) return;
    if (folder == null || folder.isEmpty) {
      setState(() => _error = context.l10n.pairingSelectFolderFirst);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await widget.cubit.createWorkspace(
      folderPath: folder,
      title: _nameController.text.trim(),
      groupId: _group.id.isEmpty ? null : _group.id,
      targetId: _target?.id,
    );
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _submitting = false;
        // Localized headline plus the host's untranslatable reason — see the
        // same pattern in the new-group sheet.
        _error = '${context.l10n.pairingWorkspaceCreateFailed}\n${result.error}';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final error = _error;
    final folder = _folderPath;
    final groupItems = <PairingGroup>[
      _ungrouped,
      ...widget.groups,
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            spacing.lg,
            spacing.lg,
            spacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.pairingNewWorkspace, style: styles.lgSemibold),
              SizedBox(height: spacing.md),
              // Machine first, then the folder on it — the folder field is
              // meaningless until you know which machine it is being read from.
              if (_showTargetPicker) ...[
                Text(
                  l10n.pairingNewWorkspaceTargetLabel,
                  style: styles.mutedSm,
                ),
                SizedBox(height: spacing.xs),
                TpSelect<PairingTarget>(
                  items: widget.targets,
                  initialItem: _target,
                  searchable: false,
                  // Host-rendered ('WSL · Ubuntu', an SSH profile's own name):
                  // shown verbatim, never localized.
                  itemLabel: (t) => t.label,
                  enabled: !_submitting,
                  onChanged: _onTargetChanged,
                ),
                SizedBox(height: spacing.md),
              ],
              Text(l10n.pairingNewWorkspaceFolderLabel, style: styles.mutedSm),
              SizedBox(height: spacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      folder == null || folder.isEmpty
                          ? '—'
                          : folder,
                      style: appMonoTextStyle(
                        context,
                        fontSize: 14,
                        color: folder == null || folder.isEmpty
                            ? cs.onSurfaceVariant
                            : cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  TpButton(
                    variant: TpButtonVariant.secondary,
                    onPressed: _submitting ? null : _browse,
                    child: Text(l10n.pairingBrowseFolder),
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              Text(l10n.pairingNewWorkspaceNameLabel, style: styles.mutedSm),
              SizedBox(height: spacing.xs),
              TpInput(
                controller: _nameController,
                enabled: !_submitting,
                decoration: InputDecoration(
                  hintText: l10n.pairingNewWorkspaceNameHint,
                ),
              ),
              SizedBox(height: spacing.md),
              Text(l10n.pairingNewWorkspaceGroupLabel, style: styles.mutedSm),
              SizedBox(height: spacing.xs),
              TpSelect<PairingGroup>(
                items: groupItems,
                initialItem: _group,
                searchable: false,
                itemLabel: (g) =>
                    g.id.isEmpty ? l10n.workspaceNavUngrouped : g.name,
                onChanged: (g) {
                  if (g != null) setState(() => _group = g);
                },
              ),
              if (error != null) ...[
                SizedBox(height: spacing.sm),
                Text(error, style: styles.smColored(cs.error)),
              ],
              SizedBox(height: spacing.md),
              TpButton(
                onPressed: _submitting ? null : _submit,
                child: Text(l10n.pairingCreate),
              ),
              SizedBox(height: spacing.xs),
              TpButton(
                variant: TpButtonVariant.ghost,
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _basename(String path) {
    final trimmed = path.replaceAll(RegExp(r'[/\\]+$'), '');
    final idx = trimmed.lastIndexOf(RegExp(r'[/\\]'));
    return idx < 0 ? trimmed : trimmed.substring(idx + 1);
  }
}
