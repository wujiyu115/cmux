import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/svn_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/vcs/svn_service.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import 'svn_changes_list.dart';

/// One SVN working-copy group inside the source control panel — the svn
/// sibling of [GitSourceControlPanel]'s per-repo body: header (url tail +
/// revision + update/refresh), checked rows list, externals section, and a
/// commit box whose selection *is* the commit set (svn has no staging).
class SvnRepoSection extends StatefulWidget {
  const SvnRepoSection({
    required this.cubit,
    required this.workspaceId,
    super.key,
  });

  final SvnCubit cubit;
  final String workspaceId;

  @override
  State<SvnRepoSection> createState() => _SvnRepoSectionState();
}

class _SvnRepoSectionState extends State<SvnRepoSection> {
  final _commitController = TextEditingController();

  SvnCubit get _cubit => widget.cubit;

  @override
  void initState() {
    super.initState();
    _commitController.text = _cubit.state.commitMessage;
    _cubit.refresh();
  }

  @override
  void dispose() {
    _commitController.dispose();
    super.dispose();
  }

  Future<void> _openDiff(SvnFileChange change) async {
    String? diff;
    try {
      diff = await _cubit.serviceDiff(change.path);
    } on SvnException {
      diff = null;
    }
    if (!mounted || diff == null) return;
    final absolutePath = _cubit.state.repoRoot.isEmpty
        ? change.path
        : '${_cubit.state.repoRoot}/${change.path}';
    await context.read<WorkbenchEditorOpener>().openChangesDiff(
      workspaceId: widget.workspaceId,
      absolutePath: absolutePath,
      title: change.path,
      loadDiff: ({ignoreWhitespace = false, fullContext = false}) async =>
          _cubit.serviceDiff(change.path),
    );
  }

  Future<void> _confirmRevert(List<String> paths) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => TpDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(
              title: l10n.svnRevertTitle,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.svnRevertBody(paths.length)),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.svnRevertAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _cubit.revert(paths);
    }
  }

  Future<void> _commit() async {
    final ok = await _cubit.commit();
    if (!mounted) return;
    if (ok) {
      _commitController.clear();
    } else if (_cubit.state.commitMessage.trim().isEmpty ||
        _cubit.state.selectedPaths.isEmpty) {
      AppToast.show(
        context,
        message: context.l10n.svnCommitNothingSelected,
        variant: TpToastVariant.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return BlocProvider.value(
      value: _cubit,
      child: BlocConsumer<SvnCubit, SvnState>(
        listenWhen: (prev, next) =>
            (prev.errorMessage != next.errorMessage &&
                next.errorMessage != null) ||
            prev.commitMessage != next.commitMessage,
        listener: (context, state) {
          if (state.errorMessage != null) {
            AppToast.show(
              context,
              message: state.errorMessage ?? '',
              variant: TpToastVariant.error,
            );
          }
          if (_commitController.text != state.commitMessage) {
            _commitController.text = state.commitMessage;
          }
        },
        buildWhen: (prev, next) =>
            prev.svnAvailable != next.svnAvailable ||
            prev.isRepository != next.isRepository ||
            prev.isLoading != next.isLoading ||
            prev.busy != next.busy ||
            prev.info != next.info ||
            prev.changes != next.changes ||
            prev.selectedPaths != next.selectedPaths,
        builder: (context, state) => _buildBody(context, state, l10n, cs),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SvnState state,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    if (!state.svnAvailable) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: cs.error),
            const SizedBox(width: 6),
            Expanded(child: Text(l10n.svnNotInstalled)),
          ],
        ),
      );
    }
    if (!state.isRepository) {
      if (state.isLoading) {
        return const SizedBox(
          height: 32,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SvnHeader(
            url: state.info?.url ?? '',
            revision: state.info?.revision ?? 0,
            busy: state.busy || state.isLoading,
            onRefresh: () => unawaited(_cubit.refresh()),
            onUpdate: () => unawaited(_cubit.update()),
          ),
          const SizedBox(height: 8),
          SvnChangesList(
            rows: state.workRows,
            selectedPaths: state.selectedPaths,
            onToggle: _cubit.toggleSelected,
            onOpenDiff: (row) => unawaited(_openDiff(row)),
            onRevert: (rows) => unawaited(
              _confirmRevert([for (final r in rows) r.path]),
            ),
            onAdd: (row) => unawaited(_cubit.addUnversioned(row.path)),
          ),
          if (state.externalsRows.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ExternalsFoldout(rows: state.externalsRows),
          ],
          const SizedBox(height: 8),
          _CommitBox(
            controller: _commitController,
            busy: state.busy,
            selectedCount: state.selectedPaths.length,
            onChanged: _cubit.setCommitMessage,
            onCommit: () => unawaited(_commit()),
            onSelectAll: _cubit.selectAll,
            onClearSelection: _cubit.clearSelection,
          ),
        ],
      ),
    );
  }
}

class _SvnHeader extends StatelessWidget {
  const _SvnHeader({
    required this.url,
    required this.revision,
    required this.busy,
    required this.onRefresh,
    required this.onUpdate,
  });

  final String url;
  final int revision;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final title = url.split('/').last;
    return Row(
      children: [
        Icon(Icons.folder_special_outlined, size: 14, color: cs.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Tooltip(
            message: url,
            child: Text(
              'SVN · $title (r$revision)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TpTextStyles.of(context).smSemibold,
            ),
          ),
        ),
        if (busy) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ] else ...[
          TpIconButton(
            icon: Icons.download_outlined,
            tooltip: l10n.svnUpdate,
            onTap: onUpdate,
          ),
          TpIconButton(
            icon: Icons.refresh,
            tooltip: l10n.svnRefresh,
            onTap: onRefresh,
          ),
        ],
      ],
    );
  }
}

class _ExternalsFoldout extends StatelessWidget {
  const _ExternalsFoldout({required this.rows});

  final List<SvnFileChange> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ExpansionTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(left: 16, bottom: 4),
      title: Text(
        l10n.svnExternals(rows.length),
        style: TpTextStyles.of(context).xsColored(
          Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                Text(
                  row.badge,
                  style: TpTextStyles.of(context).xsSemiboldColored(
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    row.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TpTextStyles.of(context).xs,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CommitBox extends StatelessWidget {
  const _CommitBox({
    required this.controller,
    required this.busy,
    required this.selectedCount,
    required this.onChanged,
    required this.onCommit,
    required this.onSelectAll,
    required this.onClearSelection,
  });

  final TextEditingController controller;
  final bool busy;
  final int selectedCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.svnSelectedCount(selectedCount),
                style: TpTextStyles.of(context).xsColored(
                  cs.onSurfaceVariant,
                ),
              ),
            ),
            TpIconButton(
              icon: Icons.done_all,
              tooltip: l10n.svnSelectAll,
              onTap: onSelectAll,
            ),
            TpIconButton(
              icon: Icons.clear_all,
              tooltip: l10n.svnClearSelection,
              onTap: onClearSelection,
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onChanged: onChanged,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(
            hintText: l10n.svnCommitHint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: busy ? null : onCommit,
          icon: const Icon(Icons.upload, size: 16),
          label: Text(l10n.svnCommit),
        ),
      ],
    );
  }
}
