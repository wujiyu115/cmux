import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/editor_cubit.dart';
import '../../cubits/git_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_blame.dart';
import '../../models/git_status.dart';
import '../../pages/workbench/blame_relative_time.dart';
import '../../services/git/git_repo_store.dart';
import '../../services/vcs/vcs_detector.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../utils/ui/app_keys.dart';
import 'file_diff_surface_toggle.dart';

/// The workspace's bottom status strip — one bar for the whole workbench
/// instead of per-surface chrome, so switching tabs does not reshuffle UI.
///
/// Content is the data the workbench actually has:
/// * branch (and change count) of the active file's repository,
/// * git blame of the caret line, VS Code style — `author (when), subject`,
///   with hash/email/exact date in the tooltip (gated by the Blame bar
///   preference, which used to mount a separate strip above the editor),
/// * caret position and the unsaved marker for the open file.
///
/// Mounted by [WorkspaceShell] for every workbench route (chat, split pane) so
/// the strip cannot drift between entry points.
class WorkspaceStatusBar extends StatefulWidget {
  const WorkspaceStatusBar({
    super.key,
    required this.workspaceId,
    this.directory,
  });

  final String workspaceId;

  /// Working directory of the active tab (workspace folder / worktree). Shown
  /// for tabs that have no file behind them — terminal, run, diff — so the bar
  /// is never an empty strip, and so its git segment still names the branch the
  /// terminals are running on.
  final String? directory;

  @override
  State<WorkspaceStatusBar> createState() => _WorkspaceStatusBarState();
}

class _WorkspaceStatusBarState extends State<WorkspaceStatusBar> {
  /// File whose blame/caret the bar reports; null for terminal, shell, run and
  /// diff tabs (a diff has two sides, so "the caret line" is ambiguous).
  String? _path;

  List<GitBlameEntry>? _entries;

  /// Monotonic token so a stale blame load (tab switched mid-flight) cannot
  /// land on the new file's bar.
  int _loadToken = 0;

  CodeLineEditingController? _controller;
  int _caretLine = 1;
  int _caretColumn = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribing here (rather than in build) keeps the side effects — blame
    // fetch, controller listener — out of layout, while still re-running when
    // the active tab changes: [context.select] registers the dependency and
    // the cubit's emit brings us back through this method.
    final path = _activeEditorPath();
    if (path != _path) {
      _path = path;
      _entries = null;
      _attachController();
      unawaited(_loadBlame());
      return;
    }
    _attachController();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onSelectionChanged);
    super.dispose();
  }

  /// Only file tabs feed the bar. Guarded: lightweight harnesses mount
  /// [WorkspaceShell] without a [WorkbenchCubit].
  String? _activeEditorPath() {
    try {
      final tab = context.select<WorkbenchCubit, String?>(
        (c) => c.activeTabId(widget.workspaceId)?.filePath,
      );
      return tab;
    } on Object {
      return null;
    }
  }

  void _attachController() {
    final path = _path;
    if (path == null) {
      _controller?.removeListener(_onSelectionChanged);
      _controller = null;
      return;
    }
    final controller = context.read<EditorCubit>().controllerFor(
      widget.workspaceId,
      path,
    );
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_onSelectionChanged);
    _controller = controller;
    controller?.addListener(_onSelectionChanged);
    if (controller != null) _readCaret(controller);
  }

  void _readCaret(CodeLineEditingController controller) {
    _caretLine = controller.selection.extentIndex + 1;
    _caretColumn = controller.selection.extentOffset + 1;
  }

  void _onSelectionChanged() {
    final controller = _controller;
    if (controller == null) return;
    final line = controller.selection.extentIndex + 1;
    final column = controller.selection.extentOffset + 1;
    if (line == _caretLine && column == _caretColumn) return;
    _caretLine = line;
    _caretColumn = column;
    // setState during a controller notification is not allowed — defer.
    scheduleMicrotask(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadBlame() async {
    final token = ++_loadToken;
    final path = _path;
    if (path == null) return;
    final scope = WorkspaceToolsScope.maybeOf(context);
    final tools = scope?.tools;
    if (scope == null || tools == null) {
      _entries = const [];
      _setStateIfMounted();
      return;
    }
    // Read the store before the async gap: a tab switch during the probe may
    // unmount this bar, and using a BuildContext after awaiting would throw.
    final store = context.read<GitRepoStore>();
    final probe = await VcsDetector().probe(
      _folderOf(path),
      tools.context.filesystem,
    );
    final area = probe.areaForPath(path);
    if (area == null) {
      _entries = const [];
      _setStateIfMounted();
      return;
    }
    List<GitBlameEntry>? blame;
    switch (area.kind) {
      case VcsKind.git:
        final git = store.cubitFor(area.root, workContext: tools.context);
        blame = await git.serviceBlame(_relativeTo(path, area.root));
      case VcsKind.svn:
        final svn = store.svnCubitFor(area.root, workContext: tools.context);
        blame = await svn.serviceBlame(_relativeTo(path, area.root));
    }
    if (token != _loadToken || !mounted) return;
    _entries = blame;
    _setStateIfMounted();
  }

  /// Path math must use the target's own style: a POSIX SSH/WSL path run
  /// through the host default context (Windows on a Windows host) resolves
  /// roots to `\home\…`, breaking root matching and `git -C` arguments.
  String _relativeTo(String path, String root) =>
      _pathContext().relative(path, from: root).replaceAll('\\', '/');

  String _folderOf(String path) => _pathContext().dirname(path);

  p.Context _pathContext() {
    final tools = WorkspaceToolsScope.maybeOf(context)?.tools;
    return tools?.context.filesystem.pathContext ?? p.Context();
  }

  void _setStateIfMounted() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final path = _path;
    final contextPath = path ?? widget.directory;
    final status = _gitStatus(context, contextPath);
    final dirty = path != null && _isDirty(context, path);

    return TpStatusBar(
      key: AppKeys.workspaceStatusBar,
      start: [
        if (status != null && status.isRepository && status.branch != null)
          TpStatusBarItem(
            key: AppKeys.workspaceStatusBarBranch,
            icon: Icons.call_split,
            label: status.branch!,
            tooltip: status.hasChanges
                ? l10n.workspaceStatusBarChanges(
                    status.staged.length + status.unstaged.length,
                  )
                : null,
          )
        else if (contextPath != null && contextPath.isNotEmpty)
          // No repository here: the directory is the only useful context.
          TpStatusBarItem(
            icon: Icons.folder_outlined,
            label: _shortPath(contextPath),
            tooltip: contextPath,
            maxWidth: 320,
          ),
        if (path != null && _showBlame(context))
          TpStatusBarItem(
            key: AppKeys.workspaceStatusBarBlame,
            icon: Icons.person_outline,
            label: _blameLabel(context),
            tooltip: _blameTooltip(context),
            maxWidth: 420,
          ),
      ],
      end: [
        if (path != null && _controller != null)
          TpStatusBarItem(
            key: AppKeys.workspaceStatusBarCaret,
            label: l10n.workspaceStatusBarCaret(_caretLine, _caretColumn),
          ),
        if (dirty)
          TpStatusBarItem(
            key: AppKeys.workspaceStatusBarDirty,
            label: l10n.workspaceStatusBarUnsaved,
            color: cs.onSurfaceVariant,
          ),
      ],
    );
  }

  /// Git state for [path]'s repository; null when the bar is mounted outside a
  /// repository-aware workbench (harnesses, non-repo folders).
  GitRepoStatus? _gitStatus(BuildContext context, String? path) {
    if (path == null) return null;
    try {
      final cubit = gitCubitForAbsolutePath(context, path);
      if (cubit == null) return null;
      return context.select<GitCubit, GitRepoStatus>((c) => c.state.status);
    } on Object {
      return null;
    }
  }

  /// Last two path segments, so a deep worktree path still fits the strip.
  String _shortPath(String path) {
    final ctx = _pathContext();
    final parent = ctx.basename(ctx.dirname(path));
    return '$parent${ctx.separator}${ctx.basename(path)}';
  }

  bool _isDirty(BuildContext context, String path) {
    try {
      return context.select<EditorCubit, bool>(
        (c) => c.state.bucket(widget.workspaceId).isDirty(path),
      );
    } on Object {
      return false;
    }
  }

  bool _showBlame(BuildContext context) {
    try {
      return context.select<LayoutCubit, bool>(
        (c) => c.state.preferences.editorShowBlameBar,
      );
    } on Object {
      // No layout cubit (harness): the bar is a diagnostic surface, so default
      // to showing it rather than an empty strip.
      return true;
    }
  }

  String _blameLabel(BuildContext context) {
    final l10n = context.l10n;
    final entries = _entries;
    if (entries == null) return l10n.workspaceStatusBarBlameLoading;
    final entry = _entryForLine(entries);
    if (entry == null) return l10n.blameNoHistory;
    if (entry.isUncommitted) return l10n.blameNotCommittedYet;
    final time = entry.authorTime == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(entry.authorTime! * 1000);
    return l10n.blameLineSummary(
      entry.authorName ?? l10n.blameUnknownAuthor,
      time == null
          ? l10n.blameUnknownDate
          : formatBlameRelativeTime(l10n, time),
      entry.subject ?? '',
    );
  }

  String? _blameTooltip(BuildContext context) {
    final entry = _entryForLine(_entries ?? const []);
    if (entry == null || entry.isUncommitted) return null;
    final l10n = context.l10n;
    final time = entry.authorTime == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(entry.authorTime! * 1000);
    return l10n.blameLineTooltip(
      entry.hash.substring(0, 8),
      entry.authorName ?? l10n.blameUnknownAuthor,
      entry.authorEmail ?? '',
      time == null ? '' : DateFormat.yMd().add_Hm().format(time),
    );
  }

  GitBlameEntry? _entryForLine(List<GitBlameEntry> entries) {
    for (final entry in entries) {
      final hit = entry.forLine(_caretLine);
      if (hit != null) return hit;
    }
    return null;
  }
}
