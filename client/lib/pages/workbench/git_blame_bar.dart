import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:re_editor/re_editor.dart';
import 'package:path/path.dart' as p;

import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_blame.dart';
import '../../services/git/git_repo_store.dart';
import '../../widgets/workbench/file_diff_surface_toggle.dart';
import 'blame_relative_time.dart';

/// Bottom bar showing the blame of the caret line, VS Code status-bar style:
/// `author (relative time), commit subject` for the owning commit; the short
/// hash in a tooltip with author email and the exact date.
///
/// Opt-in per workspace via the file tab context menu (GitRepoStore's
/// [GitRepoStore.blameVisibleWorkspaces]); mounted only when that flag is on.
/// Blame runs once per file load and is cached in memory; dirty buffers show
/// the "not committed yet" state because blame covers HEAD content only.
class GitBlameBar extends StatefulWidget {
  const GitBlameBar({
    super.key,
    required this.workspaceId,
    required this.path,
  });

  final String workspaceId;
  final String path;

  @override
  State<GitBlameBar> createState() => _GitBlameBarState();
}

class _GitBlameBarState extends State<GitBlameBar> {
  List<GitBlameEntry>? _entries;

  /// Monotonic token so a stale blame load (file switched mid-flight) can't
  /// land on the new file's bar.
  int _loadToken = 0;

  CodeLineEditingController? _controller;
  Timer? _debounce;

  int _caretLine = 1;

  @override
  void initState() {
    super.initState();
    _attachController();
    unawaited(_loadBlame());
  }

  @override
  void didUpdateWidget(GitBlameBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _attachController();
      _entries = null;
      unawaited(_loadBlame());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller?.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _attachController() {
    final controller = context
        .read<EditorCubit>()
        .controllerFor(widget.workspaceId, widget.path);
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_onSelectionChanged);
    _controller = controller;
    controller?.addListener(_onSelectionChanged);
    if (controller != null) {
      _caretLine = controller.selection.extentIndex + 1;
    }
  }

  void _onSelectionChanged() {
    final controller = _controller;
    if (controller == null) return;
    final line = controller.selection.extentIndex + 1;
    if (line == _caretLine) return;
    _caretLine = line;
    // The bar is a single Text; rebuilding it per keystroke is cheap, but
    // setState during a controller notification is not allowed — defer.
    scheduleMicrotask(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadBlame() async {
    final token = ++_loadToken;
    final git = gitCubitForAbsolutePath(context, widget.path);
    final root = git?.state.repoRoot ?? '';
    if (git == null || root.isEmpty) {
      _entries = const [];
      _setStateIfMounted();
      return;
    }
    final relative = p.Context().relative(widget.path, from: root);
    if (relative.startsWith('..')) {
      _entries = const [];
      _setStateIfMounted();
      return;
    }
    final blame = await git.serviceBlame(relative);
    if (token != _loadToken || !mounted) return;
    _entries = blame;
    _setStateIfMounted();
  }

  void _setStateIfMounted() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final entries = _entries;

    // Still loading: keep a fixed-height blank bar so the layout doesn't
    // jump when the blame lands.
    if (entries == null) {
      return const SizedBox(height: 26);
    }

    final dirty = context.select<EditorCubit, bool>(
      (c) => c.state.bucket(widget.workspaceId).isDirty(widget.path),
    );

    final String text;
    final String? tooltip;
    if (entries.isEmpty) {
      text = l10n.blameNoHistory;
      tooltip = null;
    } else {
      final entry = _entryForLine(entries);
      if (entry == null) {
        text = l10n.blameNoHistory;
        tooltip = null;
      } else if (entry.isUncommitted || dirty) {
        text = l10n.blameNotCommittedYet;
        tooltip = null;
      } else {
        final time = entry.authorTime == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(entry.authorTime! * 1000);
        text = l10n.blameLineSummary(
          entry.authorName ?? l10n.blameUnknownAuthor,
          time == null
              ? l10n.blameUnknownDate
              : formatBlameRelativeTime(l10n, time),
          entry.subject ?? '',
        );
        tooltip = l10n.blameLineTooltip(
          entry.hash.substring(0, 8),
          entry.authorName ?? l10n.blameUnknownAuthor,
          entry.authorEmail ?? '',
          time == null ? '' : DateFormat.yMd().add_Hm().format(time),
        );
      }
    }

    return SizedBox(
      height: 26,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: tooltip ?? '',
            waitDuration: const Duration(milliseconds: 400),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
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
