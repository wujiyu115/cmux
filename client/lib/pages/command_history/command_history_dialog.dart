import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/command_log_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/commands/reconciled_keyboard.dart';
import '../../services/commands/shortcut_focus.dart';

/// Loads the recent commands for [paneId] and shows the history picker over the
/// current route.
///
/// [onInsert] / [onRun] come from the hosting terminal panel (it owns the
/// active pane's PTY write path); when null the matching action is disabled
/// rather than hidden, so the picker reads the same everywhere. Per cmux the
/// history is pane-scoped: [paneId] empty falls back to every pane.
Future<void> showCommandHistoryDialog(
  BuildContext context, {
  required CommandLogCubit cubit,
  String? paneId,
  String? paneLabel,
  void Function(String command)? onInsert,
  void Function(String command)? onRun,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => CommandHistoryDialog(
      loader: () => cubit.recentCommands(paneId: paneId),
      paneLabel: paneLabel,
      onInsert: onInsert,
      onRun: onRun,
    ),
  );
}

/// Command history picker: a search field over a numbered, keyboard-navigable
/// list of the pane's distinct recent commands. Enter runs the selection,
/// Shift+Enter inserts it; the footer offers copy / insert / run / close.
class CommandHistoryDialog extends StatefulWidget {
  const CommandHistoryDialog({
    required this.loader,
    this.paneLabel,
    this.onInsert,
    this.onRun,
    super.key,
  });

  /// Fetches the distinct recent commands (newest first). Injected so tests can
  /// supply a fixed list without a repository.
  final Future<List<String>> Function() loader;

  /// Pane name shown in the title; null renders the unscoped title.
  final String? paneLabel;

  final void Function(String command)? onInsert;
  final void Function(String command)? onRun;

  @override
  State<CommandHistoryDialog> createState() => _CommandHistoryDialogState();
}

class _CommandHistoryDialogState extends State<CommandHistoryDialog> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late final FocusNode _searchFocus = FocusNode(onKeyEvent: _handleKey);

  static const double _rowExtent = 30;

  List<String> _all = const [];
  String _query = '';
  int _selectedIndex = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final commands = await widget.loader();
    if (!mounted) return;
    setState(() {
      _all = commands;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Commands matching the current query, in list (newest-first) order.
  List<String> get _visible {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return _all;
    return [
      for (final command in _all)
        if (command.toLowerCase().contains(needle)) command,
    ];
  }

  String? get _selected {
    final rows = _visible;
    if (_selectedIndex < 0 || _selectedIndex >= rows.length) return null;
    return rows[_selectedIndex];
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _selectedIndex = 0;
    });
  }

  void _moveSelection(int delta) {
    final count = _visible.length;
    if (count == 0) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, count - 1);
    });
    _scrollSelectedIntoView();
  }

  void _scrollSelectedIntoView() {
    if (!_scroll.hasClients) return;
    final target = _selectedIndex * _rowExtent;
    final viewport = _scroll.position.viewportDimension;
    final current = _scroll.offset;
    double? next;
    if (target < current) {
      next = target;
    } else if (target + _rowExtent > current + viewport) {
      next = target + _rowExtent - viewport;
    }
    if (next != null) {
      _scroll.jumpTo(next.clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      // Shift+Enter inserts, plain Enter runs — the picker's whole shortcut.
      if (ReconciledKeyboard.instance.state.isShiftPressed) {
        _insert();
      } else {
        _run();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _copy() async {
    final command = _selected;
    if (command == null) return;
    await Clipboard.setData(ClipboardData(text: command));
    if (!mounted) return;
    TpToast.show(context, message: context.l10n.commandHistoryCopied);
  }

  void _insert() {
    final command = _selected;
    if (command == null || widget.onInsert == null) return;
    widget.onInsert!(command);
    Navigator.of(context).pop();
  }

  void _run() {
    final command = _selected;
    if (command == null || widget.onRun == null) return;
    widget.onRun!(command);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = _visible;
    if (_selectedIndex >= rows.length) {
      _selectedIndex = rows.isEmpty ? 0 : rows.length - 1;
    }
    final label = widget.paneLabel?.trim() ?? '';
    final title = label.isEmpty
        ? l10n.commandHistoryTitle
        : l10n.commandHistoryPaneTitle(label);
    return Align(
      alignment: const Alignment(0, -0.6),
      child: TpDialog(
        maxWidth: 620,
        maxHeight: 520,
        contentPadding: EdgeInsets.zero,
        child: ShortcutFocus(
          kind: ShortcutFocusKind.text,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SearchRow(
                controller: _search,
                focusNode: _searchFocus,
                title: title,
                hintText: l10n.commandHistorySearchHint,
                onChanged: _onQueryChanged,
                onClose: () => Navigator.of(context).pop(),
              ),
              const TpSeparator(),
              Expanded(
                child: _loading
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : rows.isEmpty
                    ? _EmptyState(hasQuery: _query.trim().isNotEmpty)
                    : _CommandList(
                        rows: rows,
                        selectedIndex: _selectedIndex,
                        scrollController: _scroll,
                        rowExtent: _rowExtent,
                        onSelect: (index) =>
                            setState(() => _selectedIndex = index),
                        onActivate: widget.onRun == null ? null : (_) => _run(),
                      ),
              ),
              const TpSeparator(),
              _FooterRow(
                count: rows.length,
                hasSelection: _selected != null,
                onCopy: _copy,
                onInsert: widget.onInsert == null ? null : _insert,
                onRun: widget.onRun == null ? null : _run,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title + search field + close button. The Enter / Shift+Enter hint sits under
/// the field so the shortcut is discoverable without a tooltip.
class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.focusNode,
    required this.title,
    required this.hintText,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String title;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: styles.mdSemibold,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TpIconButton(
                icon: Icons.close,
                compact: true,
                size: TpIconButton.kCompactSize,
                tooltip: l10n.commandHistoryClose,
                onTap: onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TpInput(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(Icons.search, size: 16),
            ),
            onChanged: onChanged,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.commandHistoryHint,
            style: styles.xsColored(cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CommandList extends StatelessWidget {
  const _CommandList({
    required this.rows,
    required this.selectedIndex,
    required this.scrollController,
    required this.rowExtent,
    required this.onSelect,
    required this.onActivate,
  });

  final List<String> rows;
  final int selectedIndex;
  final ScrollController scrollController;
  final double rowExtent;
  final ValueChanged<int> onSelect;

  /// Double-click handler; null when the host cannot run commands.
  final void Function(int index)? onActivate;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      itemCount: rows.length,
      itemExtent: rowExtent,
      itemBuilder: (context, index) => _CommandRow(
        ordinal: index + 1,
        command: rows[index],
        selected: index == selectedIndex,
        onTap: () => onSelect(index),
        onDoubleTap: onActivate == null ? null : () => onActivate!(index),
      ),
    );
  }
}

/// One `# command` row. Owns its hover so a single detector carries both
/// select (tap) and run (double tap), like the command log rows.
class _CommandRow extends StatefulWidget {
  const _CommandRow({
    required this.ordinal,
    required this.command,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
  });

  final int ordinal;
  final String command;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<_CommandRow> createState() => _CommandRowState();
}

class _CommandRowState extends State<_CommandRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: (_) => widget.onTap(),
        child: GestureDetector(
          onDoubleTap: widget.onDoubleTap,
          child: Container(
            color: widget.selected
                ? cs.primary.withValues(alpha: 0.16)
                : (_hovered ? cs.onSurface.withValues(alpha: 0.05) : null),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '${widget.ordinal}',
                    style: styles.xsColored(cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.command,
                    style: styles.smColored(cs.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          hasQuery ? l10n.commandHistoryNoMatches : l10n.commandHistoryEmpty,
          textAlign: TextAlign.center,
          style: TpTextStyles.of(
            context,
          ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Command count on the left, actions on the right.
class _FooterRow extends StatelessWidget {
  const _FooterRow({
    required this.count,
    required this.hasSelection,
    required this.onCopy,
    required this.onInsert,
    required this.onRun,
  });

  final int count;
  final bool hasSelection;
  final VoidCallback? onCopy;
  final VoidCallback? onInsert;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          Flexible(
            child: Text(
              l10n.commandHistoryCount(count),
              style: styles.xsColored(cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 5,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [
                TpButton(
                  variant: TpButtonVariant.ghost,
                  onPressed: hasSelection ? onCopy : null,
                  child: Text(l10n.commandHistoryCopy),
                ),
                TpButton(
                  variant: TpButtonVariant.outline,
                  onPressed: hasSelection ? onInsert : null,
                  child: Text(l10n.commandHistoryInsert),
                ),
                TpButton(
                  onPressed: hasSelection ? onRun : null,
                  child: Text(l10n.commandHistoryRun),
                ),
                TpButton(
                  variant: TpButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commandHistoryClose),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
