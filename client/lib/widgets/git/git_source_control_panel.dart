import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/git_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_status.dart';
import '../../models/layout_preferences.dart';
import '../../services/git/git_changes_visible_rows.dart';
import '../../services/git/git_repo_store.dart';
import '../../services/storage/runtime_context.dart';
import '../../services/vcs/vcs_detector.dart';
import 'svn_repo_section.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import 'git_branch_menu.dart';
import 'git_changes_tree_list.dart';
import 'git_view_mode_pill.dart';

/// VSCode-style "Source Control" panel for the editor workbench right-tools
/// rail.
///
/// A pure view over [GitRepoStore]: the per-root [GitCubit]s live in the store
/// (app-level), so reopening this tab paints the last-known status instantly
/// while [RightToolsPanel]'s poller keeps it fresh. The panel never spawns git
/// itself — switching to it is free.
///
/// Multi-folder workspaces: when more than one [roots] folder is mounted, a
/// repo selector switches which folder's source control is shown (each folder
/// may be its own git repository). A single folder shows it directly.
class GitSourceControlPanel extends StatefulWidget {
  const GitSourceControlPanel({
    required this.roots,
    required this.workContext,
    required this.workspaceId,
    super.key,
  });

  /// Workspace folders (first = primary). Each may be an independent git repo.
  final List<String> roots;

  /// Work-plane context for git commands (ssh/wsl/local).
  final RuntimeContext workContext;

  final String workspaceId;

  @override
  State<GitSourceControlPanel> createState() => _GitSourceControlPanelState();
}

class _GitSourceControlPanelState extends State<GitSourceControlPanel> {
  String? _selectedRoot;

  /// Non-empty workspace folders, primary first.
  List<String> get _roots =>
      widget.roots.where((p) => p.isNotEmpty).toList(growable: false);

  String get _activeRoot {
    final roots = _roots;
    if (roots.isEmpty) return '';
    final selected = _selectedRoot;
    if (selected != null && roots.contains(selected)) return selected;
    return roots.first;
  }

  GitRepoStore get _store => context.read<GitRepoStore>();

  RuntimeContext get _workContext => widget.workContext;

  GitCubit _cubitFor(String root) =>
      _store.cubitFor(root, workContext: _workContext);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final active = _activeRoot;
      if (active.isNotEmpty) _cubitFor(active).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final roots = _roots;
    if (roots.isEmpty) {
      return _GitCenteredHint(
        icon: Icons.source_outlined,
        text: context.l10n.gitNotARepository,
      );
    }
    if (roots.length == 1) {
      return _SvnAwareBody(
        root: roots.first,
        store: _store,
        workContext: _workContext,
        workspaceId: widget.workspaceId,
      );
    }
    final active = _activeRoot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RepoSelector(
          cubitFor: _cubitFor,
          roots: roots,
          selected: active,
          onSelect: (root) {
            setState(() => _selectedRoot = root);
            _cubitFor(root).refresh();
          },
        ),
        Expanded(
          child: _SvnAwareBody(
            key: ValueKey('git-repo:$active'),
            root: active,
            store: _store,
            workContext: _workContext,
            workspaceId: widget.workspaceId,
          ),
        ),
      ],
    );
  }
}

/// Git repo body plus any svn working copies nested below [root] (the
/// svn-in-git layout). Pure-git roots render exactly as before.
class _SvnAwareBody extends StatefulWidget {
  const _SvnAwareBody({
    required this.root,
    required this.store,
    required this.workContext,
    required this.workspaceId,
    super.key,
  });

  final String root;
  final GitRepoStore store;
  final RuntimeContext workContext;
  final String workspaceId;

  @override
  State<_SvnAwareBody> createState() => _SvnAwareBodyState();
}

class _SvnAwareBodyState extends State<_SvnAwareBody> {
  VcsProbeResult? _probe;

  /// Which VCS plane the panel shows. Auto-falls back to git when there are
  /// no svn areas (pure-git roots see no pill at all, exactly as before).
  bool _svnTab = false;

  @override
  void initState() {
    super.initState();
    unawaited(_probeAreas());
  }

  @override
  void didUpdateWidget(_SvnAwareBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root != widget.root) {
      _probe = null;
      _svnTab = false;
      unawaited(_probeAreas());
    }
  }

  Future<void> _probeAreas() async {
    final detector = VcsDetector();
    final fs = widget.workContext.filesystem;
    final result = await detector.probe(widget.root, fs);
    if (mounted) setState(() => _probe = result);
  }

  @override
  Widget build(BuildContext context) {
    final probe = _probe;
    final svnAreas = probe?.areas
            .where((a) => a.kind == VcsKind.svn)
            .toList(growable: false) ??
        const <VcsArea>[];
    // Git is always present for this body (the cubit refresh decides the
    // not-a-repo hint); svn only when the probe found working copies.
    final showTabs = svnAreas.isNotEmpty;
    final gitVisible = !showTabs || !_svnTab;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTabs) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: _VcsTabPill(
              svn: _svnTab,
              onChanged: (svn) => setState(() => _svnTab = svn),
            ),
          ),
        ],
        Expanded(
          child: gitVisible
              ? _GitRepoBody(
                  cubit: widget.store.cubitFor(
                    widget.root,
                    workContext: widget.workContext,
                  ),
                  workContext: widget.workContext,
                  workspaceId: widget.workspaceId,
                )
              : _SvnTabBody(
                  areas: svnAreas,
                  store: widget.store,
                  workContext: widget.workContext,
                  workspaceId: widget.workspaceId,
                ),
        ),
      ],
    );
  }
}

/// All svn sections stacked and scrollable, for the SVN tab.
class _SvnTabBody extends StatelessWidget {
  const _SvnTabBody({
    required this.areas,
    required this.store,
    required this.workContext,
    required this.workspaceId,
    super.key,
  });

  final List<VcsArea> areas;
  final GitRepoStore store;
  final RuntimeContext workContext;
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 10),
      children: [
        for (final area in areas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SvnRepoSection(
              key: ValueKey('svn-repo:${area.root}'),
              cubit: store.svnCubitFor(
                area.root,
                workContext: workContext,
              ),
              workspaceId: workspaceId,
            ),
          ),
      ],
    );
  }
}

/// Git | SVN segmented pill in the same chrome as [GitViewModePill].
class _VcsTabPill extends StatelessWidget {
  const _VcsTabPill({
    required this.svn,
    required this.onChanged,
    super.key,
  });

  final bool svn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.onSurface;
    return Container(
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _VcsTabSegment(
            icon: Icons.account_tree_outlined,
            tooltip: context.l10n.scmGitTabTooltip,
            selected: !svn,
            color: color,
            onTap: () => onChanged(false),
          ),
          Container(width: 1, height: 14, color: cs.outlineVariant),
          _VcsTabSegment(
            icon: Icons.layers_outlined,
            tooltip: context.l10n.scmSvnTabTooltip,
            selected: svn,
            color: color,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _VcsTabSegment extends StatelessWidget {
  const _VcsTabSegment({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.color,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? cs.onSurface.withValues(alpha: 0.12)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: color.withValues(alpha: 0.12),
          splashColor: color.withValues(alpha: 0.2),
          child: SizedBox(
            width: 34,
            height: 28,
            child: Center(
              child: Icon(icon, size: context.tpIconSizes.sm, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _RepoSelector extends StatelessWidget {
  const _RepoSelector({
    required this.cubitFor,
    required this.roots,
    required this.selected,
    required this.onSelect,
  });

  final GitCubit Function(String root) cubitFor;
  final List<String> roots;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final root in roots)
            _RepoChip(
              cubit: cubitFor(root),
              root: root,
              selected: root == selected,
              onTap: () => onSelect(root),
            ),
        ],
      ),
    );
  }
}

class _RepoChip extends StatelessWidget {
  const _RepoChip({
    required this.cubit,
    required this.root,
    required this.selected,
    required this.onTap,
  });

  final GitCubit cubit;
  final String root;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = p.basename(root).isEmpty ? root : p.basename(root);
    return BlocProvider.value(
      value: cubit,
      child: BlocSelector<GitCubit, GitState, int>(
        selector: (state) => state.status.isRepository
            ? state.status.staged.length + state.status.unstaged.length
            : 0,
        builder: (context, count) => ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).sm,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                _DirtyBadge(count: count, selected: selected),
              ],
            ],
          ),
          selected: selected,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onTap(),
          tooltip: root,
          labelStyle: TpTextStyles.of(context).smColored(
            selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _DirtyBadge extends StatelessWidget {
  const _DirtyBadge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: selected
            ? cs.onSecondaryContainer.withValues(alpha: 0.18)
            : cs.primaryContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$count',
        style: TpTextStyles.of(context).xsSemiboldColored(selected ? cs.onSecondaryContainer : cs.onPrimaryContainer),
      ),
    );
  }
}

class _GitRepoBody extends StatefulWidget {
  const _GitRepoBody({
    required this.cubit,
    required this.workContext,
    required this.workspaceId,
    super.key,
  });

  final GitCubit cubit;
  final RuntimeContext workContext;
  final String workspaceId;

  @override
  State<_GitRepoBody> createState() => _GitRepoBodyState();
}

class _GitRepoBodyState extends State<_GitRepoBody> {
  GitCubit get _cubit => widget.cubit;

  final _commitController = TextEditingController();
  final _changesScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();
  var _changesListReady = false;

  @override
  void initState() {
    super.initState();
    _commitController.text = _cubit.state.commitMessage;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _changesListReady = true);
    });
  }

  @override
  void dispose() {
    _commitController.dispose();
    _changesScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Future<void> _openDiff(GitFileChange change) async {
    // Match DiffViewer.initialFullContext so the first paint is full-file,
    // without a second git diff + parse after mount.
    final diff = await _cubit.diff(change, fullContext: true);
    if (!mounted || diff == null) return;
    final absolutePath = p.join(_cubit.state.repoRoot, change.path);
    context.read<WorkbenchEditorOpener>().openDiff(
      workspaceId: widget.workspaceId,
      absolutePath: absolutePath,
      source: change.staged
          ? WorkbenchDiffSource.staged
          : WorkbenchDiffSource.unstaged,
      title: change.path,
      diffText: diff,
      reloadDiff: (ignoreWhitespace, fullContext) => _cubit.diff(
        change,
        ignoreWhitespace: ignoreWhitespace,
        fullContext: fullContext,
      ),
    );
  }

  Future<void> _confirmDiscard(GitFileChange change) async {
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
              title: l10n.gitDiscardConfirmTitle,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.gitDiscardConfirmBody(change.path)),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.gitDiscard),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _cubit.discard(change);
    }
  }

  Future<void> _openBranchSheet() async {
    await _cubit.ensureBranches(force: true);
    if (!mounted) return;
    final action = await GitBranchSheet.show(
      context,
      branches: _cubit.state.branches,
      current: _cubit.state.status.branch,
    );
    if (action == null) return;
    if (action.checkout != null) {
      await _cubit.checkoutBranch(action.checkout!);
    } else if (action.createName != null) {
      await _cubit.createBranch(action.createName!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocConsumer<GitCubit, GitState>(
        listenWhen: (prev, next) =>
            (prev.errorMessage != next.errorMessage &&
                next.errorMessage != null) ||
            prev.commitMessage != next.commitMessage,
        listener: (context, state) {
          if (state.errorMessage != null) {
            AppToast.show(
              context,
              message: context.l10n.gitError(state.errorMessage ?? ''),
              variant: TpToastVariant.error,
            );
          }
          if (_commitController.text != state.commitMessage) {
            _commitController.text = state.commitMessage;
          }
        },
        buildWhen: (prev, next) =>
            prev.gitAvailable != next.gitAvailable ||
            prev.isRepository != next.isRepository ||
            prev.isLoading != next.isLoading,
        builder: (context, state) => _buildShell(context, state),
      ),
    );
  }

  Widget _buildShell(BuildContext context, GitState state) {
    final l10n = context.l10n;

    if (!state.gitAvailable) {
      return _GitCenteredHint(
        icon: Icons.error_outline,
        text: l10n.gitNotInstalled,
      );
    }
    if (!state.isRepository) {
      if (state.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _GitCenteredHint(
        icon: Icons.source_outlined,
        text: l10n.gitNotARepository,
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      child: Builder(
        // Selected (not inside the GitState selectors below) so a mode change
        // repaints this shell without waiting on git state, and without the
        // tool-views cache key (which would rebuild the file tree too).
        builder: (context) {
          final viewMode = context.select<LayoutCubit, GitChangesViewMode>(
            (c) => c.state.preferences.gitChangesViewMode,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BlocSelector<GitCubit, GitState, (String, int, int, bool, bool)>(
                selector: (state) => (
                  state.status.branch ?? 'HEAD',
                  state.status.ahead,
                  state.status.behind,
                  state.busy || state.isLoading,
                  state.allChangeFoldersExpanded,
                ),
                builder: (context, header) {
                  final (branch, ahead, behind, busy, allExpanded) = header;
                  return _Header(
                    branch: branch,
                    ahead: ahead,
                    behind: behind,
                    busy: busy,
                    allFoldersExpanded: allExpanded,
                    viewMode: viewMode,
                    onRefresh: () => unawaited(_cubit.refresh()),
                    onPush: () => unawaited(_cubit.push()),
                    onPull: () => unawaited(_cubit.pull()),
                    onBranch: () => unawaited(_openBranchSheet()),
                    onToggleExpandAll: _cubit.toggleExpandAllFolders,
                    onViewModeChanged: (mode) => unawaited(
                      context.read<LayoutCubit>().setGitChangesViewMode(mode),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              BlocSelector<GitCubit, GitState, (bool, bool, String)>(
                selector: (state) => (
                  state.status.staged.isNotEmpty,
                  state.busy,
                  state.status.branch ?? 'HEAD',
                ),
                builder: (context, commit) {
                  final (hasStaged, busy, branch) = commit;
                  return _CommitBox(
                    controller: _commitController,
                    hint: l10n.gitCommitMessageHint(branch),
                    canCommit: hasStaged && !busy,
                    onChanged: _cubit.setCommitMessage,
                    onCommit: () async {
                      final ok = await _cubit.commit();
                      if (ok) _commitController.clear();
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: BlocSelector<
                  GitCubit,
                  GitState,
                  (bool, GitChangesTreeViewData, List<GitFileChange>, List<
                      GitFileChange>)
                >(
                  selector: (state) => (
                    state.status.hasChanges,
                    state.changesTreeView,
                    state.status.staged,
                    state.status.unstaged,
                  ),
                  builder: (context, data) {
                    final (hasChanges, treeView, staged, unstaged) = data;
                    if (!hasChanges) {
                      final cs = Theme.of(context).colorScheme;
                      return Center(
                        child: Text(
                          l10n.gitNoChanges,
                          style: TpTextStyles.of(
                            context,
                          ).smColored(cs.onSurfaceVariant),
                        ),
                      );
                    }
                    if (!_changesListReady) {
                      return const SizedBox.shrink();
                    }
                    final isFlat = viewMode == GitChangesViewMode.flat;
                    return GitChangesTreeList(
                      treeView: isFlat
                          ? visibleGitChangesFlatViewData(
                              staged: staged,
                              unstaged: unstaged,
                            )
                          : treeView,
                      cubit: _cubit,
                      flat: isFlat,
                      listScrollController: _changesScrollController,
                      horizontalScrollController: _horizontalScrollController,
                      onOpenDiff: (change) => unawaited(_openDiff(change)),
                      onConfirmDiscard: (change) =>
                          unawaited(_confirmDiscard(change)),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GitCenteredHint extends StatelessWidget {
  const _GitCenteredHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TpTextStyles.of(
                context,
              ).smColored(cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.branch,
    required this.ahead,
    required this.behind,
    required this.busy,
    required this.allFoldersExpanded,
    required this.viewMode,
    required this.onRefresh,
    required this.onPush,
    required this.onPull,
    required this.onBranch,
    required this.onToggleExpandAll,
    required this.onViewModeChanged,
  });

  final String branch;
  final int ahead;
  final int behind;
  final bool busy;
  final bool allFoldersExpanded;
  final GitChangesViewMode viewMode;
  final VoidCallback onRefresh;
  final VoidCallback onPush;
  final VoidCallback onPull;
  final VoidCallback onBranch;
  final VoidCallback onToggleExpandAll;
  final ValueChanged<GitChangesViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onBranch,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 16,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      branch,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TpTextStyles.of(
                        context,
                      ).smSemibold,
                    ),
                  ),
                  if (ahead > 0 || behind > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      l10n.gitAheadBehind(ahead, behind),
                      style: TpTextStyles.of(
                        context,
                      ).xsColored(cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        GitViewModePill(mode: viewMode, onModeChanged: onViewModeChanged),
        if (viewMode == GitChangesViewMode.tree)
          TpIconButton(
            icon: allFoldersExpanded ? Icons.unfold_less : Icons.unfold_more,
            compact: true,
            size: TpIconButton.kCompactSize,
            tooltip: allFoldersExpanded
                ? l10n.treeCollapseAllFolders
                : l10n.treeExpandAllFolders,
            onTap: onToggleExpandAll,
          ),
        TpIconButton(
          icon: Icons.download_outlined,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: l10n.gitPull,
          onTap: onPull,
        ),
        TpIconButton(
          icon: Icons.upload_outlined,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: l10n.gitPush,
          onTap: onPush,
        ),
        TpIconButton(
          icon: Icons.refresh,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: l10n.gitRefresh,
          onTap: onRefresh,
        ),
      ],
    );
  }
}

class _CommitBox extends StatelessWidget {
  const _CommitBox({
    required this.controller,
    required this.hint,
    required this.canCommit,
    required this.onChanged,
    required this.onCommit,
  });

  final TextEditingController controller;
  final String hint;
  final bool canCommit;
  final ValueChanged<String> onChanged;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Builder(
          builder: (context) {
            final bodyStyle = TpTextStyles.of(context).md;
            return TpTextarea(
              controller: controller,
              minHeight: tpTextareaHeightForLines(bodyStyle, lines: 2),
              maxHeight: tpTextareaHeightForLines(bodyStyle, lines: 6),
              decoration: InputDecoration(hintText: hint, isDense: true),
              onChanged: onChanged,
            );
          },
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: canCommit ? onCommit : null,
          icon: Icon(Icons.check, size: 16),
          label: Text(l10n.gitCommit),
        ),
      ],
    );
  }
}
