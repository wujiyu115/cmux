import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/command_log_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/command_log_entry.dart';
import '../../repositories/command_log_repository.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../services/io/system_folder_opener.dart';

/// Opens the command log window over the current route.
///
/// [onInsert] / [onRun] come from the hosting terminal panel (it owns the active
/// pane and its PTY write path); when null the matching footer button is
/// disabled rather than hidden, so the window reads the same everywhere.
Future<void> showCommandLogDialog(
  BuildContext context, {
  required CommandLogCubit cubit,
  void Function(String command)? onInsert,
  void Function(String command)? onRun,
  SystemFolderOpener? folderOpener,
}) async {
  // Refresh on open: rows recorded by other windows land on disk, not in this
  // cubit's in-memory day.
  unawaited(cubit.load());
  await showDialog<void>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: CommandLogDialog(
        onInsert: onInsert,
        onRun: onRun,
        folderOpener: folderOpener,
      ),
    ),
  );
}

/// Command log window: day picker, workspace / surface / pane filters, search,
/// the row table, and the copy / insert / run footer.
class CommandLogDialog extends StatefulWidget {
  const CommandLogDialog({
    this.onInsert,
    this.onRun,
    this.folderOpener,
    super.key,
  });

  final void Function(String command)? onInsert;
  final void Function(String command)? onRun;

  /// Injected in tests; defaults to the real file manager opener.
  final SystemFolderOpener? folderOpener;

  @override
  State<CommandLogDialog> createState() => _CommandLogDialogState();
}

class _CommandLogDialogState extends State<CommandLogDialog> {
  final TextEditingController _search = TextEditingController();

  /// Selected row id; null when nothing is selected (footer actions disabled).
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _search.text = context.read<CommandLogCubit>().state.query;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<CommandLogCubit, CommandLogState>(
      builder: (context, state) {
        final rows = state.visible;
        final selected = _selectionIn(rows);
        return TpDialog(
          maxWidth: 1040,
          maxHeight: 640,
          contentPadding: EdgeInsets.zero,
          child: ShortcutFocus(
            kind: ShortcutFocusKind.text,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopRow(
                  state: state,
                  onSelectDate: (date) =>
                      context.read<CommandLogCubit>().selectDate(date),
                  onRefresh: () =>
                      unawaited(context.read<CommandLogCubit>().load()),
                  onOpenFolder: () => unawaited(_openFolder(context)),
                ),
                const TpSeparator(),
                _FilterRow(state: state, searchController: _search),
                const TpSeparator(),
                const _TableHeader(),
                const TpSeparator(),
                Expanded(
                  child: rows.isEmpty
                      ? _EmptyState(hasFilters: state.hasFilters)
                      : _RowList(
                          rows: rows,
                          selectedId: selected?.id,
                          onSelect: (id) => setState(() => _selectedId = id),
                          onActivate: widget.onRun == null
                              ? null
                              : (entry) => _run(context, entry.command),
                        ),
                ),
                const TpSeparator(),
                _FooterRow(
                  count: rows.length,
                  skippedLines: state.skippedLines,
                  selected: selected,
                  onCopy: selected == null
                      ? null
                      : () => unawaited(_copy(context, selected.command)),
                  onInsert: widget.onInsert == null || selected == null
                      ? null
                      : () => _insert(context, selected.command),
                  onRun: widget.onRun == null || selected == null
                      ? null
                      : () => _run(context, selected.command),
                  closeLabel: l10n.commandLogClose,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Keeps the selection valid across filter / day changes.
  CommandLogEntry? _selectionIn(List<CommandLogEntry> rows) {
    final id = _selectedId;
    if (id == null) return null;
    for (final row in rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  Future<void> _copy(BuildContext context, String command) async {
    await Clipboard.setData(ClipboardData(text: command));
    if (!context.mounted) return;
    TpToast.show(context, message: context.l10n.commandLogCopied);
  }

  void _insert(BuildContext context, String command) {
    widget.onInsert?.call(command);
    Navigator.of(context).pop();
  }

  void _run(BuildContext context, String command) {
    widget.onRun?.call(command);
    Navigator.of(context).pop();
  }

  Future<void> _openFolder(BuildContext context) async {
    final cubit = context.read<CommandLogCubit>();
    final path = await cubit.prepareDirectory();
    await (widget.folderOpener ?? SystemFolderOpener()).reveal(path);
  }
}

/// Day picker + refresh + open-log-folder.
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.state,
    required this.onSelectDate,
    required this.onRefresh,
    required this.onOpenFolder,
  });

  final CommandLogState state;
  final void Function(DateTime date) onSelectDate;
  final VoidCallback onRefresh;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = state.selectedDate;
    final stems = <String>[
      for (final date in state.dates) formatLogDate(date),
    ];
    final selectedStem = selected == null ? '' : formatLogDate(selected);
    if (selectedStem.isNotEmpty && !stems.contains(selectedStem)) {
      // The current day has no file yet (nothing logged): still offer it.
      stems.insert(0, selectedStem);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Text(
            l10n.commandLogTitle,
            style: TpTextStyles.of(context).mdSemibold,
          ),
          const SizedBox(width: 12),
          if (stems.isNotEmpty)
            TpCompactSelect<String>(
              value: selectedStem.isEmpty ? stems.first : selectedStem,
              entries: [for (final stem in stems) (stem, stem)],
              minWidth: 132,
              onChanged: (stem) {
                final date = stem == null ? null : parseLogDate(stem);
                if (date != null) onSelectDate(date);
              },
            ),
          const Spacer(),
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          TpIconButton(
            icon: Icons.refresh,
            compact: true,
            size: TpIconButton.kCompactSize,
            tooltip: l10n.commandLogRefresh,
            onTap: onRefresh,
          ),
          TpIconButton(
            icon: Icons.folder_open,
            compact: true,
            size: TpIconButton.kCompactSize,
            tooltip: l10n.commandLogOpenFolder,
            onTap: onOpenFolder,
          ),
          TpIconButton(
            icon: Icons.close,
            compact: true,
            size: TpIconButton.kCompactSize,
            tooltip: l10n.commandLogClose,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Workspace / surface / pane dropdowns, the search field, and clear-filters.
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.state, required this.searchController});

  final CommandLogState state;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<CommandLogCubit>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          // The selects share the row flexibly: a long workspace name
          // ellipsises instead of pushing the search field off the edge.
          Flexible(
            flex: 2,
            child: _FilterSelect(
              value: state.workspaceFilter,
              allLabel: l10n.commandLogAllWorkspaces,
              options: state.workspaceOptions,
              onChanged: cubit.setWorkspaceFilter,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: _FilterSelect(
              value: state.surfaceFilter,
              allLabel: l10n.commandLogAllSurfaces,
              options: state.surfaceOptions,
              onChanged: cubit.setSurfaceFilter,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: _FilterSelect(
              value: state.paneFilter,
              allLabel: l10n.commandLogAllPanes,
              options: state.paneOptions,
              onChanged: cubit.setPaneFilter,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TpInput(
              controller: searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.commandLogSearchHint,
                prefixIcon: const Icon(Icons.search, size: 16),
              ),
              onChanged: cubit.setQuery,
            ),
          ),
          const SizedBox(width: 8),
          TpButton(
            variant: TpButtonVariant.ghost,
            onPressed: state.hasFilters
                ? () {
                    searchController.clear();
                    cubit.clearFilters();
                  }
                : null,
            child: Text(l10n.commandLogClearFilters),
          ),
        ],
      ),
    );
  }
}

/// One id filter: `''` selects everything.
class _FilterSelect extends StatelessWidget {
  const _FilterSelect({
    required this.value,
    required this.allLabel,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final String allLabel;
  final List<(String, String)> options;
  final void Function(String id) onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String)>[('', allLabel), ...options];
    // A stale id (its day is no longer loaded) would break TpSelect's value
    // lookup, so fall back to "all".
    final resolved = entries.any((e) => e.$1 == value) ? value : '';
    return TpCompactSelect<String>(
      value: resolved,
      entries: entries,
      minWidth: 128,
      onChanged: (id) => onChanged(id ?? ''),
    );
  }
}

/// Column widths shared by the header and the rows.
class _Columns {
  static const double time = 76;
  static const int workspace = 3;
  static const int surface = 3;
  static const int pane = 3;
  static const int command = 7;
  static const int directory = 5;
  static const double exitCode = 56;
  static const double duration = 64;
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = TpTextStyles.of(context).xsColored(
      Theme.of(context).colorScheme.onSurfaceVariant,
    );
    Widget cell(String text) => Text(
      text,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          SizedBox(width: _Columns.time, child: cell(l10n.commandLogColumnTime)),
          Expanded(
            flex: _Columns.workspace,
            child: cell(l10n.commandLogColumnWorkspace),
          ),
          Expanded(
            flex: _Columns.surface,
            child: cell(l10n.commandLogColumnSurface),
          ),
          Expanded(flex: _Columns.pane, child: cell(l10n.commandLogColumnPane)),
          Expanded(
            flex: _Columns.command,
            child: cell(l10n.commandLogColumnCommand),
          ),
          Expanded(
            flex: _Columns.directory,
            child: cell(l10n.commandLogColumnDirectory),
          ),
          SizedBox(
            width: _Columns.exitCode,
            child: cell(l10n.commandLogColumnExitCode),
          ),
          SizedBox(
            width: _Columns.duration,
            child: cell(l10n.commandLogColumnDuration),
          ),
        ],
      ),
    );
  }
}

class _RowList extends StatelessWidget {
  const _RowList({
    required this.rows,
    required this.selectedId,
    required this.onSelect,
    required this.onActivate,
  });

  final List<CommandLogEntry> rows;
  final String? selectedId;
  final void Function(String id) onSelect;

  /// Double-click handler; null when the host cannot run commands.
  final void Function(CommandLogEntry entry)? onActivate;

  static const double kRowHeight = 26;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: rows.length,
      itemExtent: kRowHeight,
      itemBuilder: (context, index) {
        final entry = rows[index];
        return _Row(
          entry: entry,
          selected: entry.id == selectedId,
          onTap: () => onSelect(entry.id),
          onDoubleTap: onActivate == null ? null : () => onActivate!(entry),
        );
      },
    );
  }
}

/// One table row. Owns its hover state instead of using [TpHover] so a single
/// gesture detector can carry both select (tap) and run (double tap).
class _Row extends StatefulWidget {
  const _Row({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
  });

  final CommandLogEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final base = styles.xsColored(cs.onSurface);
    final muted = styles.xsColored(cs.onSurfaceVariant);
    final exit = entry.exitCode;
    final exitStyle = exit == null
        ? muted
        : styles.xsColored(exit == 0 ? cs.onSurfaceVariant : cs.error);
    final duration = entry.duration;
    Widget cell(String text, TextStyle style) => Text(
      text,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // Select straight off the pointer: a tap recognizer sharing the arena
      // with the double-tap one only reports after the 300ms double-tap
      // window, which would lag the highlight and the footer actions.
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
                  width: _Columns.time,
                  child: cell(commandLogTimeLabel(entry.startedAt), muted),
                ),
                Expanded(
                  flex: _Columns.workspace,
                  child: cell(entry.workspaceLabel, muted),
                ),
                Expanded(
                  flex: _Columns.surface,
                  child: cell(entry.surfaceLabel, muted),
                ),
                Expanded(
                  flex: _Columns.pane,
                  child: cell(entry.paneLabel, muted),
                ),
                Expanded(
                  flex: _Columns.command,
                  child: cell(entry.command, base),
                ),
                Expanded(
                  flex: _Columns.directory,
                  child: cell(entry.workingDirectory, muted),
                ),
                SizedBox(
                  width: _Columns.exitCode,
                  child: cell(exit?.toString() ?? '—', exitStyle),
                ),
                SizedBox(
                  width: _Columns.duration,
                  child: cell(
                    duration == null ? '—' : commandDurationLabel(duration),
                    muted,
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
  const _EmptyState({required this.hasFilters});

  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          hasFilters ? l10n.commandLogNoMatches : l10n.commandLogEmpty,
          textAlign: TextAlign.center,
          style: TpTextStyles.of(
            context,
          ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Row count / skipped-line notice on the left, actions on the right.
class _FooterRow extends StatelessWidget {
  const _FooterRow({
    required this.count,
    required this.skippedLines,
    required this.selected,
    required this.onCopy,
    required this.onInsert,
    required this.onRun,
    required this.closeLabel,
  });

  final int count;
  final int skippedLines;
  final CommandLogEntry? selected;
  final VoidCallback? onCopy;
  final VoidCallback? onInsert;
  final VoidCallback? onRun;
  final String closeLabel;

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
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.commandLogEntryCount(count),
                  style: styles.xsColored(cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (skippedLines > 0)
                  Text(
                    l10n.commandLogSkippedLines(skippedLines),
                    style: styles.xsColored(cs.error),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Actions wrap to a second run on narrow windows / wide locales
          // instead of overflowing the footer.
          Flexible(
            flex: 5,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [
                TpButton(
                  variant: TpButtonVariant.ghost,
                  onPressed: onCopy,
                  child: Text(l10n.commandLogCopyCommand),
                ),
                TpButton(
                  variant: TpButtonVariant.outline,
                  onPressed: onInsert,
                  child: Text(l10n.commandLogInsertIntoPane),
                ),
                TpButton(
                  onPressed: onRun,
                  child: Text(l10n.commandLogRunInPane),
                ),
                TpButton(
                  variant: TpButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(closeLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Local `HH:mm:ss` for a row's start instant (locale-independent, like the
/// duration label).
String commandLogTimeLabel(DateTime startedAt) {
  final local = startedAt.isUtc ? startedAt.toLocal() : startedAt;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
