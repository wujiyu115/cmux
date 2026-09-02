import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../services/git/git_command_runner.dart';
import '../../services/io/filesystem.dart';
import '../../services/quick_open/quick_open_index.dart';
import '../../services/quick_open/quick_open_matcher.dart';
import '../../services/quick_open/quick_open_mru_repository.dart';
import '../../services/storage/app_storage.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../utils/commands/fuzzy_match.dart';
import '../../utils/session/workspace_sessions.dart';
import '../home_workspace/workspace/workspace_session_actions.dart';

/// Process-lifetime index cache so a second Ctrl+P serves the previous
/// listing instantly while a refresh runs in the background.
final QuickOpenIndexRegistry _sharedIndexRegistry = QuickOpenIndexRegistry();

/// Opens the quick-open dialog (Ctrl+P): sessions + files in one fuzzy
/// launcher. Pops with the chosen [QuickOpenResult]; the MRU touch and editor
/// open run *after* the pop (both unawaited, so the dialog returns immediately
/// and the closing dialog does not fight the opening editor — same ordering
/// as the command palette).
///
/// [filesystem] must be the work-plane filesystem of the machine hosting the
/// workspace folders (WSL/SSH workspaces cannot be read through the app's
/// native home context).
///
/// [gitRunner], when provided, is the work-plane git runner for the machine
/// hosting [workspace]'s folders; the index then prefers `git ls-files` so
/// .gitignore rules hold, falling back to the recursive listing otherwise.
Future<void> showQuickOpenDialog(
  BuildContext context, {
  required Workspace workspace,
  Filesystem? filesystem,
  GitCommandRunner? gitRunner,
  QuickOpenIndexRegistry? indexRegistry,
  QuickOpenMruRepository? mruRepository,
}) async {
  if (_quickOpenDialogOpen) return;
  _quickOpenDialogOpen = true;
  try {
    final opener = context.read<WorkbenchEditorOpener>();
    final fs = filesystem ?? AppStorage.fs;
    final registry = indexRegistry ?? _sharedIndexRegistry;
    if (gitRunner != null) {
      // The shared registry keeps its (fs, root) cache across dialogs, so the
      // runner is updated in place instead of replacing the registry.
      registry.gitRunner = gitRunner;
    }
    final mru = mruRepository ?? QuickOpenMruRepository(fs: fs);
    final chatCubit = context.read<ChatCubit>();
    final fallback = context.l10n.defaultNewChatSessionTitle;
    final sessions = sessionsForWorkspace(
      workspace,
      chatCubit.state.sessions,
    );
    final result = await showDialog<QuickOpenResult>(
      context: context,
      builder: (_) => QuickOpenOverlay(
        workspace: workspace,
        filesystem: fs,
        indexRegistry: registry,
        mruRepository: mru,
        sessions: sessions,
        emptyTitleFallback: fallback,
      ),
    );
    if (result == null) return;
    if (result is QuickOpenSessionResult) {
      if (!context.mounted) return;
      // Same open path as the sidebar (worktree sync, needs-you jump).
      await openWorkspaceSessionTab(context, workspace, result.session);
      return;
    }
    final path = (result as QuickOpenFileResult).path;
    // Fire-and-forget: the MRU rotation is a multi-spawn write on WSL/SSH and
    // must not delay the editor open. A lost update between overlapping
    // touches only reorders the recents list.
    unawaited(mru.touch(workspace.firstFolderPath, path));
    if (!context.mounted) return;
    unawaited(
      opener.openFile(workspace.workspaceId, path, fs: fs, preview: true),
    );
  } finally {
    _quickOpenDialogOpen = false;
  }
}

var _quickOpenDialogOpen = false;

/// What the user picked from the quick-open list.
sealed class QuickOpenResult {
  const QuickOpenResult();
}

/// A file to open in the editor.
class QuickOpenFileResult extends QuickOpenResult {
  const QuickOpenFileResult(this.path);

  final String path;
}

/// A conversation session to open as a workbench tab.
class QuickOpenSessionResult extends QuickOpenResult {
  const QuickOpenSessionResult(this.session);

  final AppSession session;
}

/// VS Code-style fuzzy launcher over the workspace's sessions and files: a
/// search field over a scrolling, keyboard-navigable list. Empty query lists
/// recent sessions then recently opened files; a query fuzzy-matches session
/// titles and file basenames first, then workspace-relative paths so
/// same-named files can be told apart. Pops the enclosing route with the
/// chosen [QuickOpenResult] (or `null`).
class QuickOpenOverlay extends StatefulWidget {
  const QuickOpenOverlay({
    super.key,
    required this.workspace,
    required this.filesystem,
    required this.indexRegistry,
    required this.mruRepository,
    required this.sessions,
    required this.emptyTitleFallback,
  });

  final Workspace workspace;
  final Filesystem filesystem;
  final QuickOpenIndexRegistry indexRegistry;
  final QuickOpenMruRepository mruRepository;
  final List<AppSession> sessions;
  final String emptyTitleFallback;

  @override
  State<QuickOpenOverlay> createState() => _QuickOpenOverlayState();
}

/// One selectable row: either a session or a file entry.
class _QuickOpenRow {
  const _QuickOpenRow.session(this.session, this.label, this.sessionMatch)
    : entry = null,
      match = null;
  const _QuickOpenRow.file(this.entry, this.match)
    : session = null,
      label = null,
      sessionMatch = null;

  final AppSession? session;
  final QuickOpenFileEntry? entry;

  /// Session rows: resolved display title. File rows: null.
  final String? label;

  /// File match (null for MRU rows); session title highlight indexes.
  final QuickOpenMatch? match;
  final List<int>? sessionMatch;

  bool get isSession => session != null;

  /// Single label for scoring / sorting regardless of row kind.
  String get sortLabel => isSession ? label! : entry!.name;

  List<int> matchedIndexesFor(QuickOpenMatchTarget target) =>
      match?.target == target ? match!.indexes : const [];
}

class _ScoredRow {
  const _ScoredRow(this.row, this.score);

  final _QuickOpenRow row;
  final int score;
}

class _QuickOpenOverlayState extends State<QuickOpenOverlay> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _searchFocus = FocusNode(onKeyEvent: _handleKey);
  static const double _rowExtent = 64;
  static const int _maxResultRows = 50;
  static const int _maxRecentSessions = 8;
  static const Duration _debounce = Duration(milliseconds: 100);

  String _query = '';
  int _selectedIndex = 0;
  bool _indexLoading = true;
  QuickOpenIndex _index = const QuickOpenIndex.empty();
  List<QuickOpenFileEntry> _recent = const [];
  List<_QuickOpenRow> _rows = const [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadIndex();
    _loadRecent();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadIndex() async {
    QuickOpenIndex index;
    try {
      index = await widget.indexRegistry.load(
        widget.filesystem,
        widget.workspace.firstFolderPath,
      );
    } on Object {
      index = const QuickOpenIndex.empty();
    }
    if (!mounted) return;
    setState(() {
      _index = index;
      _indexLoading = false;
      _rows = _computeRows();
    });
  }

  Future<void> _loadRecent() async {
    final paths = await widget.mruRepository.load(
      widget.workspace.firstFolderPath,
    );
    if (!mounted) return;
    setState(() {
      _recent = [for (final path in paths) _entryForPath(path)];
      _rows = _computeRows();
    });
  }

  QuickOpenFileEntry _entryForPath(String path) {
    final ctx = widget.filesystem.pathContext;
    final root = widget.workspace.firstFolderPath;
    final relative = ctx.isWithin(root, path)
        ? ctx.relative(path, from: root)
        : path;
    return QuickOpenFileEntry(
      path: path,
      name: ctx.basename(path),
      relativePath: relative,
    );
  }

  /// Empty query: recent sessions first, then recently opened files. Query:
  /// sessions + files fuzzy-matched and ranked together (sessions compete on
  /// title, files on basename then path).
  List<_QuickOpenRow> _computeRows() {
    final query = _query.trim();
    if (query.isEmpty) {
      final recentSessions = widget.sessions.take(_maxRecentSessions);
      return [
        for (final session in recentSessions)
          _QuickOpenRow.session(
            session,
            session.resolveDisplayTitle(widget.emptyTitleFallback),
            null,
          ),
        for (final entry in _recent) _QuickOpenRow.file(entry, null),
      ];
    }
    final lowerQuery = query.toLowerCase();
    final scored = <_ScoredRow>[];
    for (final session in widget.sessions) {
      final title = session.resolveDisplayTitle(widget.emptyTitleFallback);
      final match = fuzzyMatch(title, lowerQuery);
      if (match == null) continue;
      scored.add(
        _ScoredRow(_QuickOpenRow.session(session, title, match.indexes), match.score),
      );
    }
    for (final entry in _index.files) {
      final match = quickOpenMatch(entry, lowerQuery);
      if (match == null) continue;
      scored.add(_ScoredRow(_QuickOpenRow.file(entry, match), match.score));
    }
    scored.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      final aLen = a.row.sortLabel.length;
      final bLen = b.row.sortLabel.length;
      if (aLen != bLen) return aLen.compareTo(bLen);
      return a.row.sortLabel.compareTo(b.row.sortLabel);
    });
    return [for (final s in scored.take(_maxResultRows)) s.row];
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _applyRecompute);
  }

  void _applyRecompute() {
    if (!mounted) return;
    setState(() {
      _rows = _computeRows();
      _selectedIndex = 0;
    });
  }

  void _moveSelection(int delta, int count) {
    if (count == 0) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, count - 1);
    });
    _scrollSelectedIntoView();
  }

  void _scrollSelectedIntoView() {
    if (!_scrollController.hasClients) return;
    final target = _selectedIndex * _rowExtent;
    final viewport = _scrollController.position.viewportDimension;
    final current = _scrollController.offset;
    double? next;
    if (target < current) {
      next = target;
    } else if (target + _rowExtent > current + viewport) {
      next = target + _rowExtent - viewport;
    }
    if (next != null) {
      _scrollController.jumpTo(
        next.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    }
  }

  void _openSelected() {
    if (_selectedIndex < 0 || _selectedIndex >= _rows.length) return;
    _openAt(_selectedIndex);
  }

  void _openAt(int index) {
    if (index < 0 || index >= _rows.length) return;
    final row = _rows[index];
    final QuickOpenResult result = row.isSession
        ? QuickOpenSessionResult(row.session!)
        : QuickOpenFileResult(row.entry!.path);
    Navigator.of(context).pop(result);
  }

  /// Runs on the search field's own focus node, so arrow / Enter / Escape are
  /// intercepted before the [TextField]'s built-in editing shortcuts consume
  /// them (which would move the caret instead of the selection).
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1, _rows.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1, _rows.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _openSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final emptyQuery = _query.trim().isEmpty;
    final showSessionHeader = emptyQuery && widget.sessions.isNotEmpty;
    final showRecentHeader = emptyQuery && _recent.isNotEmpty;
    if (_selectedIndex >= _rows.length) {
      _selectedIndex = _rows.isEmpty ? 0 : _rows.length - 1;
    }
    return Align(
      alignment: const Alignment(0, -0.6),
      child: TpDialog(
        maxWidth: 640,
        maxHeight: 560,
        child: ShortcutFocus(
          kind: ShortcutFocusKind.text,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SearchField(
                controller: _controller,
                focusNode: _searchFocus,
                hintText: l10n.quickOpenSearchHint,
                onChanged: _onQueryChanged,
                onSubmitted: _openSelected,
                onClear: () {
                  _controller.clear();
                  _onQueryChanged('');
                },
              ),
              const SizedBox(height: 12),
              if (showSessionHeader)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 6),
                  child: Text(
                    l10n.quickOpenRecentSessions,
                    style: TpTextStyles.of(context).xsSemiboldColored(
                      Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (showRecentHeader)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 6),
                  child: Text(
                    l10n.quickOpenRecent,
                    style: TpTextStyles.of(context).xsSemiboldColored(
                      Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Flexible(
                child: _rows.isEmpty
                    ? _EmptyState(text: _emptyStateText(l10n))
                    : _ResultList(
                        rows: _rows,
                        selectedIndex: _selectedIndex,
                        scrollController: _scrollController,
                        rowExtent: _rowExtent,
                        onTap: _openAt,
                      ),
              ),
              if (_index.truncated)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.quickOpenTruncated(_index.files.length),
                    style: TpTextStyles.of(context).mutedSm,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _emptyStateText(AppLocalizations l10n) {
    if (_query.trim().isNotEmpty) return l10n.quickOpenNoResults;
    if (_indexLoading) return l10n.quickOpenIndexing;
    return l10n.quickOpenEmptyRecent;
  }
}

/// Boxed search field mirroring the command palette's input, so both
/// overlays read as the same family.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        filled: true,
        fillColor: cs.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: context.tpIconSizes.md,
          color: cs.onSurfaceVariant,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.never,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.primary),
        ),
        suffixIcon: controller.text.isNotEmpty
            ? TpIconButton(
                icon: Icons.clear,
                compact: true,
                size: TpIconButton.kCompactSize,
                onTap: onClear,
              )
            : null,
      ),
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(child: Text(text, style: TpTextStyles.of(context).mutedSm)),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.rows,
    required this.selectedIndex,
    required this.scrollController,
    required this.rowExtent,
    required this.onTap,
  });

  final List<_QuickOpenRow> rows;
  final int selectedIndex;
  final ScrollController scrollController;
  final double rowExtent;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemExtent: rowExtent,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        return _ResultRow(
          row: rows[index],
          selected: index == selectedIndex,
          onTap: () => onTap(index),
        );
      },
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final _QuickOpenRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: selected
            ? cs.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(
                  row.isSession
                      ? Icons.terminal_rounded
                      : Icons.insert_drive_file_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: row.isSession
                      ? _SessionRowContent(row: row)
                      : _FileRowContent(row: row),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionRowContent extends StatelessWidget {
  const _SessionRowContent({required this.row});

  final _QuickOpenRow row;

  @override
  Widget build(BuildContext context) {
    return _HighlightedText(
      text: row.label!,
      matchedIndexes: row.sessionMatch ?? const [],
    );
  }
}

class _FileRowContent extends StatelessWidget {
  const _FileRowContent({required this.row});

  final _QuickOpenRow row;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HighlightedText(
          text: row.entry!.name,
          matchedIndexes: row.matchedIndexesFor(QuickOpenMatchTarget.name),
        ),
        _HighlightedText(
          text: row.entry!.relativePath,
          matchedIndexes: row.matchedIndexesFor(
            QuickOpenMatchTarget.relativePath,
          ),
          small: true,
        ),
      ],
    );
  }
}

/// Renders [text] with [matchedIndexes] emphasized (bolder + accent colour).
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.matchedIndexes,
    this.small = false,
  });

  final String text;
  final List<int> matchedIndexes;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final base = small
        ? styles.xsColored(cs.onSurfaceVariant)
        : styles.smColored(cs.onSurface);
    final highlight = small
        ? styles.xsSemiboldColored(cs.primary)
        : styles.smSemiboldColored(cs.primary);
    final matched = matchedIndexes.toSet();

    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < text.length; i++)
            TextSpan(
              text: text[i],
              style: matched.contains(i) ? highlight : base,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
