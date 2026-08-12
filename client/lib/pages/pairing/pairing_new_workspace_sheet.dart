import 'package:flutter/material.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
import 'pairing_block_button.dart';
import 'pairing_remote_dir_browser_page.dart';
import 'pairing_sheet_parts.dart';

/// Bottom sheet to create a workspace on the paired desktop: pick the machine,
/// pick a folder on it, optionally name it, and file it under a group.
///
/// Follows the mobile prototype's `new-workspace.html`: a subtitle explaining
/// what a workspace is, then machine / folder / name / group as four labelled
/// fields, where machine and group are `.picker` rows opening a second-level
/// option sheet and the folder is a dashed `.pathbox` until one is chosen. Create
/// stays disabled until there is a folder, so the sheet never has to reject a
/// submit it could have prevented.
///
/// [cubit], [groups] and [targets] are captured by the caller before the sheet
/// opens (the modal route sits above the pairing shell's `BlocProvider`).
Future<void> showPairingNewWorkspaceSheet(
  BuildContext context,
  PairingClientCubit cubit,
  List<PairingGroup> groups,
  List<PairingTarget> targets,
) {
  return showPairingSheet<void>(
    context: context,
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

/// Sentinel for the "no group" option. Empty id = ungrouped, which is also what
/// the wire treats as "no group".
const _ungrouped = PairingGroup(id: '', name: '', order: -1);

/// Prototype `#wname`: `maxlength="32"`.
const _nameMaxLength = 32;

class _PairingNewWorkspaceSheetState extends State<_PairingNewWorkspaceSheet> {
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();

  String? _folderPath;
  PairingGroup _group = _ungrouped;

  /// The machine the folder will live on. Null when the host advertised none, in
  /// which case no `targetId` is ever sent and the host uses its default plane.
  PairingTarget? _target;

  /// Whether the name in the field came from the folder rather than the user.
  /// Only an auto-filled name is cleared when the machine changes — a name the
  /// user typed outlives the folder it was seeded from.
  bool _nameAutoFilled = false;
  bool _submitting = false;
  String? _error;

  /// Hidden for a single machine, not just for none: the host always lists
  /// itself, so one entry means there is nothing to pick.
  bool get _showTargetPicker => widget.targets.length > 1;

  @override
  void initState() {
    super.initState();
    _target = widget.targets.isEmpty ? null : widget.targets.first;
    _nameFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_onFocusChanged);
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// The input's accent halo is painted outside its border, so focus changes have
  /// to rebuild this subtree.
  void _onFocusChanged() => setState(() {});

  Future<void> _pickTarget() async {
    final picked = await showPairingOptionSheet<String>(
      context: context,
      title: context.l10n.pairingNewWorkspaceTargetLabel,
      current: _target?.id,
      options: [
        for (final target in widget.targets)
          // Host-rendered ('WSL · Ubuntu', an SSH profile's own name): shown
          // verbatim, never localized.
          PairingSheetOption(value: target.id, label: target.label),
      ],
    );
    if (!mounted || picked == null || picked == _target?.id) return;
    final next = widget.targets.firstWhere((t) => t.id == picked);
    // Switching machines invalidates the folder: a path on one machine names
    // nothing on another, and the host cannot tell the difference ('/home/me' is
    // plausible everywhere). Clearing it is what keeps the pair coherent.
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

  Future<void> _pickGroup() async {
    final l10n = context.l10n;
    final picked = await showPairingOptionSheet<String>(
      context: context,
      title: l10n.pairingNewWorkspaceGroupLabel,
      current: _group.id,
      options: [
        PairingSheetOption(value: '', label: l10n.workspaceNavUngrouped),
        for (final group in widget.groups)
          PairingSheetOption(value: group.id, label: group.name),
      ],
    );
    if (!mounted || picked == null) return;
    setState(() {
      _group = picked.isEmpty
          ? _ungrouped
          : widget.groups.firstWhere((g) => g.id == picked);
    });
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
      // Prototype: the name placeholder starts naming the folder once one is
      // chosen, so an unnamed workspace is predictable rather than mysterious.
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = _basename(picked);
        _nameAutoFilled = true;
      }
      _error = null;
    });
  }

  bool get _canSubmit =>
      (_folderPath?.isNotEmpty ?? false) && !_submitting;

  Future<void> _submit() async {
    final folder = _folderPath;
    if (!_canSubmit || folder == null) return;
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
        _error = result.error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final folder = _folderPath;
    final hasFolder = folder != null && folder.isNotEmpty;
    final hostError = _error;

    return Padding(
      // Lifts the sheet above the soft keyboard instead of letting it cover the
      // name field. Not in the prototype, which is a static mock.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PairingSheetGrab(),
            PairingSheetHead(
              title: l10n.pairingNewWorkspace,
              onClose: _submitting ? null : () => Navigator.of(context).pop(),
            ),
            PairingSheetSubtitle(l10n.pairingNewWorkspaceSubtitle),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_showTargetPicker) ...[
                      PairingFieldLabel(
                        label: l10n.pairingNewWorkspaceTargetLabel,
                      ),
                      PairingPickerRow(
                        icon: Icons.desktop_windows_outlined,
                        value: _target?.label ?? '',
                        onTap: _submitting ? null : _pickTarget,
                      ),
                      const SizedBox(height: 18),
                    ],
                    PairingFieldLabel(
                      label: l10n.pairingNewWorkspaceFolderLabel,
                      marker: l10n.pairingFieldRequired,
                    ),
                    _PathBox(
                      path: folder,
                      placeholder: l10n.pairingNoFolderSelected,
                      browseLabel: l10n.pairingBrowseFolder,
                      onBrowse: _submitting ? null : _browse,
                    ),
                    PairingFieldHelp(
                      hasFolder
                          ? l10n.pairingNewWorkspaceFolderPicked
                          : l10n.pairingNewWorkspaceFolderHelp,
                    ),
                    const SizedBox(height: 18),
                    PairingFieldLabel(
                      label: l10n.pairingNewWorkspaceNameLabel,
                      marker: l10n.pairingFieldOptional,
                      used: _nameController.text.characters.length,
                      max: _nameMaxLength,
                    ),
                    PairingSheetTextField(
                      controller: _nameController,
                      focusNode: _nameFocus,
                      hintText: hasFolder
                          ? l10n.pairingNewWorkspaceNameHintFolder(
                              _basename(folder),
                            )
                          : l10n.pairingNewWorkspaceNameHint,
                      enabled: !_submitting,
                      maxLength: _nameMaxLength,
                      onSubmitted: _submit,
                    ),
                    const SizedBox(height: 18),
                    PairingFieldLabel(
                      label: l10n.pairingNewWorkspaceGroupLabel,
                    ),
                    PairingPickerRow(
                      icon: Icons.folder_outlined,
                      value: _group.id.isEmpty
                          ? l10n.workspaceNavUngrouped
                          : _group.name,
                      isPlaceholder: _group.id.isEmpty,
                      onTap: _submitting ? null : _pickGroup,
                    ),
                    if (hostError != null)
                      PairingFieldHelp(
                        // Localized headline plus the host's untranslatable
                        // reason — see the same pattern in the new-group sheet.
                        '${l10n.pairingWorkspaceCreateFailed} $hostError',
                        isError: true,
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PairingBlockButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: _submitting
                        ? PairingCreatingLabel(label: l10n.pairingCreating)
                        : Text(l10n.pairingCreate),
                  ),
                  const SizedBox(height: 10),
                  PairingBlockButton(
                    outlined: true,
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prototype `.pathbox`: the chosen path in mono beside a small Browse button,
/// its border dashed while empty so an unfilled required field is visible at a
/// glance. The dash is drawn by hand — Flutter's `Border` has no dashed style.
class _PathBox extends StatelessWidget {
  const _PathBox({
    required this.path,
    required this.placeholder,
    required this.browseLabel,
    required this.onBrowse,
  });

  final String? path;
  final String placeholder;
  final String browseLabel;
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = pairingMutedColor(cs);
    final filled = path != null && path!.isNotEmpty;
    return CustomPaint(
      painter: filled ? null : _DashedBorderPainter(color: cs.outlineVariant),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: filled ? Border.all(color: cs.outlineVariant) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 22, color: muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                filled ? path! : placeholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: filled
                    // Mono for a path: it is a machine string, and the desktop
                    // may return either separator style.
                    ? appMonoTextStyle(context, fontSize: 14)
                    : TextStyle(fontSize: 15, color: muted),
              ),
            ),
            const SizedBox(width: 12),
            // Prototype `.btn.ghost.sm`: 40 tall, 11px radius, 15px label.
            _SmallGhostButton(label: browseLabel, onPressed: onBrowse),
          ],
        ),
      ),
    );
  }
}

class _SmallGhostButton extends StatelessWidget {
  const _SmallGhostButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        // Both bounds pinned, like PairingBlockButton: the global button theme
        // clamps height to a 26px compact track, so a minimum of 40 alone yields
        // `40<=h<=26` — not-normalized constraints that blow up as a
        // hundred-thousand-pixel overflow rather than a clipped button.
        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
        maximumSize: const WidgetStatePropertyAll(Size(double.infinity, 40)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        foregroundColor: WidgetStatePropertyAll(cs.onSurface),
        backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHighest),
        side: WidgetStatePropertyAll(BorderSide(color: cs.outlineVariant)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
      ),
      child: Text(label),
    );
  }
}

/// Draws the `.pathbox.empty` dashed outline: 14px radius, 4-on/4-off.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 4;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Last path segment, tolerating either separator — the host may be Windows or
/// POSIX, and the phone never learns which.
String _basename(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}
