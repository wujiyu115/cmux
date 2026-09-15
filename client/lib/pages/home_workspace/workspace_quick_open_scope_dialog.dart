import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/workspace_index_dirs.dart';
import '../../repositories/session_repository.dart';
import '../../services/storage/workspace_directory_picker.dart';
import '../../utils/workspace/workspace_path_picker.dart';

/// Opens the quick-open search-scope editor for [workspace]. Every add /
/// remove persists immediately through [ChatCubit.updateWorkspaceMetadata] —
/// closing the dialog never discards a change (the dialog has no save
/// action). Rules are workspace-root-relative; the shared index registry
/// re-keys its cache on them, so the next Ctrl+P honors the new scope.
Future<void> editWorkspaceQuickOpenScope(
  BuildContext context,
  Workspace workspace,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _QuickOpenScopeDialog(workspace: workspace),
  );
}

/// Dual-list editor over [Workspace.indexDirRules]: excluded directories leave
/// the Ctrl+P index, restored (included) directories carve subtrees back out of
/// an exclude.
class _QuickOpenScopeDialog extends StatefulWidget {
  const _QuickOpenScopeDialog({required this.workspace});

  final Workspace workspace;

  @override
  State<_QuickOpenScopeDialog> createState() => _QuickOpenScopeDialogState();
}

class _QuickOpenScopeDialogState extends State<_QuickOpenScopeDialog> {
  late final List<String> _excluded = List.of(
    widget.workspace.indexDirRules.excluded,
  );
  late final List<String> _included = List.of(
    widget.workspace.indexDirRules.included,
  );
  final _excludeController = TextEditingController();
  final _includeController = TextEditingController();

  @override
  void dispose() {
    _excludeController.dispose();
    _includeController.dispose();
    super.dispose();
  }

  /// Applies [mutate] to the local lists and persists the result. On a failed
  /// persist the local lists roll back to their pre-change state, so the rows
  /// always mirror what actually reached disk. [onPersisted] runs only after a
  /// successful write (used to clear the add-input after its row is durable).
  Future<void> _mutate(void Function() mutate, {VoidCallback? onPersisted}) async {
    final beforeExcluded = List.of(_excluded);
    final beforeIncluded = List.of(_included);
    setState(mutate);
    try {
      await context.read<ChatCubit>().updateWorkspaceMetadata(
        context.read<SessionRepository>(),
        widget.workspace.workspaceId,
        indexDirRules: WorkspaceIndexDirs(
          excluded: _excluded,
          included: _included,
        ),
      );
      onPersisted?.call();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _excluded
          ..clear()
          ..addAll(beforeExcluded);
        _included
          ..clear()
          ..addAll(beforeIncluded);
      });
      AppToast.show(
        context,
        message: context.l10n.workspaceQuickOpenScopeSaveFailed(
          error.toString(),
        ),
        variant: TpToastVariant.error,
      );
    }
  }

  void _addRule({required bool include}) {
    final controller = include ? _includeController : _excludeController;
    final path = normalizeIndexDirRule(controller.text);
    if (path.isEmpty) return;
    // Cross-list duplicates are contradictory (equal depth — exclude wins),
    // so either list blocks the add.
    if (_excluded.contains(path) || _included.contains(path)) {
      AppToast.show(
        context,
        message: context.l10n.workspaceQuickOpenScopeDuplicate,
        variant: TpToastVariant.warning,
      );
      return;
    }
    unawaited(
      _mutate(
        () => (include ? _included : _excluded).add(path),
        onPersisted: controller.clear,
      ),
    );
  }

  void _removeRule(String path, {required bool include}) {
    unawaited(
      _mutate(() => (include ? _included : _excluded).remove(path)),
    );
  }

  /// Browses the primary folder's machine and adds the picked directory's
  /// root-relative path straight to the section's list (typed input stays
  /// available for subtrees not on disk).
  Future<void> _browse({required bool include}) async {
    final folders = widget.workspace.folders;
    if (folders.isEmpty || folders.first.path.trim().isEmpty) {
      AppToast.show(
        context,
        message: context.l10n.workspaceQuickOpenScopeNoFolder,
        variant: TpToastVariant.warning,
      );
      return;
    }
    final folder = folders.first;
    final picker = context.read<WorkspaceDirectoryPicker>();
    final picked = await pickWorkspaceDirectoryPath(
      context,
      targetId: folder.targetId,
    );
    if (picked == null || picked.trim().isEmpty || !mounted) return;
    final String relative;
    try {
      final fs = await picker.filesystemFor(folder.targetId);
      final ctx = fs.pathContext;
      final root = ctx.normalize(folder.path.trim());
      final abs = ctx.normalize(picked.trim());
      if (!ctx.isWithin(root, abs)) {
        if (!mounted) return;
        AppToast.show(
          context,
          message: context.l10n.workspaceQuickOpenScopeOutsideRoot,
          variant: TpToastVariant.warning,
        );
        return;
      }
      relative = normalizeIndexDirRule(ctx.relative(abs, from: root));
    } on Object {
      if (!mounted) return;
      AppToast.show(
        context,
        message: context.l10n.workspaceQuickOpenScopeOutsideRoot,
        variant: TpToastVariant.error,
      );
      return;
    }
    if (relative.isEmpty || !mounted) return;
    if (_excluded.contains(relative) || _included.contains(relative)) {
      AppToast.show(
        context,
        message: context.l10n.workspaceQuickOpenScopeDuplicate,
        variant: TpToastVariant.warning,
      );
      return;
    }
    await _mutate(() => (include ? _included : _excluded).add(relative));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpDialog(
      maxWidth: 560,
      maxHeight: 560,
      child: TpDialogPinnedLayout(
        header: TpDialogHeader(
          title: l10n.workspaceQuickOpenScope,
          onClose: () => Navigator.of(context).pop(),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.workspaceQuickOpenScopeSubtitle,
              style: TpTextStyles.of(context).smColored(
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.workspaceQuickOpenScopeAutoSave,
              style: TpTextStyles.of(context).xsColored(
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _ScopeSection(
              title: l10n.workspaceQuickOpenScopeExcludedTitle,
              hint: l10n.workspaceQuickOpenScopeExcludedHint,
              entries: _excluded,
              controller: _excludeController,
              onAdd: () => _addRule(include: false),
              onBrowse: () => _browse(include: false),
              onRemove: (path) => _removeRule(path, include: false),
            ),
            const SizedBox(height: 16),
            _ScopeSection(
              title: l10n.workspaceQuickOpenScopeIncludedTitle,
              hint: l10n.workspaceQuickOpenScopeIncludedHint,
              entries: _included,
              controller: _includeController,
              onAdd: () => _addRule(include: true),
              onBrowse: () => _browse(include: true),
              onRemove: (path) => _removeRule(path, include: true),
              warningFor: _includeWarning,
            ),
          ],
        ),
      ),
    );
  }

  String? _includeWarning(String path) {
    if (_excluded.contains(path)) {
      return context.l10n.workspaceQuickOpenScopeIncludeMatchesExclude;
    }
    final underExclude = _excluded.any(
      (excluded) => path.startsWith('$excluded/'),
    );
    if (!underExclude) return context.l10n.workspaceQuickOpenScopeOrphanInclude;
    return null;
  }
}

/// One editable rule list: title + hint, committed rows with remove buttons,
/// and an add row (relative-path input, browse, add).
class _ScopeSection extends StatelessWidget {
  const _ScopeSection({
    required this.title,
    required this.hint,
    required this.entries,
    required this.controller,
    required this.onAdd,
    required this.onBrowse,
    required this.onRemove,
    this.warningFor,
  });

  final String title;
  final String hint;
  final List<String> entries;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final VoidCallback onBrowse;
  final ValueChanged<String> onRemove;
  final String? Function(String path)? warningFor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: styles.mdSemiboldColored(cs.onSurface)),
        const SizedBox(height: 2),
        Text(hint, style: styles.xsColored(cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.workspaceQuickOpenScopeEmpty,
              style: styles.smColored(cs.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
          )
        else
          for (final entry in entries) ...[
            _RuleRow(path: entry, onRemove: () => onRemove(entry)),
            if (warningFor?.call(entry) case final warning?)
              _WarningLine(text: warning),
          ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.workspaceQuickOpenScopeAddPathHint,
                ),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 4),
            TpIconButton(
              icon: Icons.folder_open_outlined,
              tooltip: l10n.workspaceQuickOpenScopeBrowse,
              onTap: onBrowse,
              size: TpIconButton.kCompactSize,
              compact: true,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            TpIconButton(
              icon: Icons.add_rounded,
              tooltip: l10n.add,
              onTap: onAdd,
              size: TpIconButton.kCompactSize,
              compact: true,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.subdirectory_arrow_right_rounded,
            size: context.tpIconSizes.sm,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TpTextStyles.of(context).smColored(cs.onSurface),
            ),
          ),
          TpIconButton(
            icon: Icons.close_rounded,
            onTap: onRemove,
            size: TpIconButton.kCompactSize,
            compact: true,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _WarningLine extends StatelessWidget {
  const _WarningLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 26, bottom: 6),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 12, color: cs.error),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TpTextStyles.of(context).xsColored(cs.error),
            ),
          ),
        ],
      ),
    );
  }
}
