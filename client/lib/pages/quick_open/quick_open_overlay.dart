import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../services/io/filesystem.dart';
import '../../services/quick_open/quick_open_index.dart';
import '../../services/quick_open/quick_open_mru_repository.dart';
import '../../services/storage/app_storage.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../utils/commands/fuzzy_match.dart';

/// Process-lifetime index cache so a second Ctrl+P serves the previous
/// listing instantly while a refresh runs in the background.
final QuickOpenIndexRegistry _sharedIndexRegistry = QuickOpenIndexRegistry();

/// Opens the quick-open dialog (Ctrl+P). Pops with the chosen absolute path;
/// the MRU touch and editor open run *after* the pop so the opening editor
/// does not fight the closing dialog (same ordering as the command palette).
///
/// [filesystem] must be the work-plane filesystem of the machine hosting the
/// workspace folders (WSL/SSH workspaces cannot be read through the app's
/// native home context).
Future<void> showQuickOpenDialog(
  BuildContext context, {
  required Workspace workspace,
  Filesystem? filesystem,
  QuickOpenIndexRegistry? indexRegistry,
  QuickOpenMruRepository? mruRepository,
}) async {
  if (_quickOpenDialogOpen) return;
  _quickOpenDialogOpen = true;
  try {
    final opener = context.read<WorkbenchEditorOpener>();
    final fs = filesystem ?? AppStorage.fs;
    final registry = indexRegistry ?? _sharedIndexRegistry;
    final mru = mruRepository ?? QuickOpenMruRepository(fs: fs);
    final path = await showDialog<String>(
      context: context,
      builder: (_) => QuickOpenOverlay(
        workspace: workspace,
        filesystem: fs,
        indexRegistry: registry,
        mruRepository: mru,
      ),
    );
    if (path == null) return;
    await mru.touch(workspace.firstFolderPath, path);
    if (!context.mounted) return;
    unawaited(
      opener.openFile(workspace.workspaceId, path, fs: fs, preview: true),
    );
  } finally {
    _quickOpenDialogOpen = false;
  }
}

var _quickOpenDialogOpen = false;

/// VS Code-style fuzzy filename launcher: a search field over a scrolling,
/// keyboard-navigable file list. Empty query lists recently opened files;
/// a query fuzzy-matches basenames across the workspace index. Pops the
/// enclosing route with the chosen file's absolute path (or `null`).
class QuickOpenOverlay extends StatefulWidget {
  const QuickOpenOverlay({
    super.key,
    required this.workspace,
    required this.filesystem,
    required this.indexRegistry,
    required this.mruRepository,
  });

  final Workspace workspace;
  final Filesystem filesystem;
  final QuickOpenIndexRegistry indexRegistry;
  final QuickOpenMruRepository mruRepository;

  @override
  State<QuickOpenOverlay> createState() => _QuickOpenOverlayState();
}

class _QuickOpenRow {
  const _QuickOpenRow(this.entry, this.matchedIndexes);

  final QuickOpenFileEntry entry;
  final List<int> matchedIndexes;
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
  static const double _rowExtent = 48;
  static const int _maxResultRows = 50;
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
    final relative = ctx.isWithin(root, path) ? ctx.relative(path, from: root) : path;
    return QuickOpenFileEntry(
      path: path,
      name: ctx.basename(path),
      relativePath: relative,
    );
  }

  List<_QuickOpenRow> _computeRows() {
    final query = _query.trim();
    if (query.isEmpty) {
      return [for (final entry in _recent) _QuickOpenRow(entry, const [])];
    }
    final lowerQuery = query.toLowerCase();
    final scored = <_ScoredRow>[];
    for (final entry in _index.files) {
      final match = fuzzyMatch(entry.name, lowerQuery);
      if (match == null) continue;
      scored.add(_ScoredRow(_QuickOpenRow(entry, match.indexes), match.score));
    }
    scored.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      final aLen = a.row.entry.relativePath.length;
      final bLen = b.row.entry.relativePath.length;
      if (aLen != bLen) return aLen.compareTo(bLen);
      return a.row.entry.relativePath.compareTo(b.row.entry.relativePath);
    });
    return [
      for (final s in scored.take(_maxResultRows)) s.row,
    ];
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
    Navigator.of(context).pop(_rows[_selectedIndex].entry.path);
  }

  void _openAt(int index) {
    if (index < 0 || index >= _rows.length) return;
    Navigator.of(context).pop(_rows[index].entry.path);
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
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
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
    final showRecentHeader = _query.trim().isEmpty && _recent.isNotEmpty;
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
          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
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
      child: Center(
        child: Text(text, style: TpTextStyles.of(context).mutedSm),
      ),
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
  const _ResultRow({required this.row, required this.selected, required this.onTap});

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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HighlightedTitle(
                        title: row.entry.name,
                        matchedIndexes: row.matchedIndexes,
                      ),
                      Text(
                        row.entry.relativePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TpTextStyles.of(context).xsColored(
                          cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders [title] with [matchedIndexes] emphasized (bolder + accent colour).
class _HighlightedTitle extends StatelessWidget {
  const _HighlightedTitle({required this.title, required this.matchedIndexes});

  final String title;
  final List<int> matchedIndexes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final base = styles.smColored(cs.onSurface);
    final highlight = styles.smSemiboldColored(cs.primary);
    final matched = matchedIndexes.toSet();

    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < title.length; i++)
            TextSpan(
              text: title[i],
              style: matched.contains(i) ? highlight : base,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
