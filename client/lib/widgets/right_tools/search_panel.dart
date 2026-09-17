import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/editor_cubit.dart';
import '../../../cubits/search_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../services/search/search_result_models.dart';
import '../../../services/search/search_result_rows.dart';
import '../../../services/workbench/workbench_editor_opener.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import 'right_tools_lifecycle.dart';

/// "Search in files" tool view (VS Code Ctrl+Shift+F equivalent): query +
/// toggles + glob filters, streamed results grouped by file, click a match
/// to open it at the line.
///
/// The cubit is retained per workspace by [WorkspaceSearchStore] (via the
/// provider wired in the tool views); the fresh tools scope comes from
/// [RightToolsLifecycle] — not a widget param — so a late-resolving slice
/// rebinds the resolver without waiting on the cached view rebuild.
class SearchPanel extends StatefulWidget {
  const SearchPanel({
    required this.cubit,
    required this.workspaceId,
    super.key,
  });

  final SearchCubit cubit;
  final String workspaceId;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  final _queryController = TextEditingController();
  final _pathFilterController = TextEditingController();
  final _includeController = TextEditingController();
  final _excludeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _queryController.text = widget.cubit.state.query.text;
    _pathFilterController.text = widget.cubit.state.query.pathFilter;
    _includeController.text = widget.cubit.state.query.includeGlobs;
    _excludeController.text = widget.cubit.state.query.excludeGlobs;
    widget.cubit.scopeResolver = _currentScope;
  }

  @override
  void dispose() {
    widget.cubit.scopeResolver = null;
    _queryController.dispose();
    _pathFilterController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    super.dispose();
  }

  WorkspaceToolsScopeState? _currentScope() {
    try {
      return RightToolsLifecycle.of(context).scope;
    } on Object {
      return null;
    }
  }

  Future<void> _openMatch(SearchFileResult file, SearchMatch match) async {
    final scope = _currentScope();
    final fs = scope?.filesystemForTarget(file.targetId) ?? scope?.tools?.context.filesystem;
    final opener = context.read<WorkbenchEditorOpener>();
    await opener.openFile(widget.workspaceId, file.absolutePath, fs: fs);
    if (!mounted) return;
    final editor = context.read<EditorCubit>();
    // openFile returns once the controller exists, but a slow plane may race
    // the handle registration — bounded wait (same shape as tree reveal).
    for (var attempt = 0; attempt < 75 && mounted; attempt++) {
      if (editor.controllerFor(widget.workspaceId, file.absolutePath) != null) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (!mounted) return;
    editor.selectLines(
      widget.workspaceId,
      file.absolutePath,
      startLine: match.lineNo,
      endLine: match.lineNo,
      centerIfInvisible: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = widget.cubit;
    return BlocProvider.value(
      value: cubit,
      child: BlocBuilder<SearchCubit, SearchState>(
        bloc: cubit,
        builder: (context, state) {
          // Rebind on scope changes (late slice resolution) + rerun a
          // pending query that was blocked on resolving.
          RightToolsLifecycle.of(context);
          return Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildQueryRow(context, cubit),
                const SizedBox(height: 6),
                _buildToggleRow(context, cubit, state),
                const SizedBox(height: 6),
                _buildFilterRows(context, cubit),
                const SizedBox(height: 8),
                Expanded(child: _buildBody(context, state)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQueryRow(BuildContext context, SearchCubit cubit) {
    final l10n = context.l10n;
    return TextField(
      controller: _queryController,
      focusNode: cubit.queryFocusNode,
      decoration: InputDecoration(
        isDense: true,
        hintText: l10n.searchQueryPlaceholder,
        border: const OutlineInputBorder(),
      ),
      onChanged: cubit.setQuery,
      onSubmitted: (_) => cubit.rerun(),
    );
  }

  Widget _buildToggleRow(BuildContext context, SearchCubit cubit, SearchState state) {
    final l10n = context.l10n;
    return Row(
      children: [
        _SearchToggle(
          icon: Icons.sort_by_alpha,
          tooltip: l10n.searchCaseSensitiveTooltip,
          selected: state.query.caseSensitive,
          onTap: cubit.toggleCaseSensitive,
        ),
        _SearchToggle(
          icon: Icons.abc,
          tooltip: l10n.searchWholeWordTooltip,
          selected: state.query.wholeWord,
          onTap: cubit.toggleWholeWord,
        ),
        _SearchToggle(
          icon: Icons.code,
          tooltip: l10n.searchUseRegexTooltip,
          selected: state.query.useRegex,
          onTap: cubit.toggleUseRegex,
        ),
        const Spacer(),
        _StatusLine(state: state),
      ],
    );
  }

  Widget _buildFilterRows(BuildContext context, SearchCubit cubit) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _pathFilterController,
          decoration: InputDecoration(
            isDense: true,
            hintText: l10n.searchPathFilterPlaceholder,
            border: const OutlineInputBorder(),
          ),
          onChanged: cubit.setPathFilter,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _includeController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.searchIncludePlaceholder,
                  border: const OutlineInputBorder(),
                ),
                onChanged: cubit.setIncludeGlobs,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _excludeController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.searchExcludePlaceholder,
                  border: const OutlineInputBorder(),
                ),
                onChanged: cubit.setExcludeGlobs,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, SearchState state) {
    final l10n = context.l10n;
    if (state.status == SearchStatus.invalidPattern) {
      return _CenteredHint(text: l10n.searchInvalidRegex);
    }
    if (state.status == SearchStatus.running) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final results = state.results;
    if (results == null || results.files.isEmpty) {
      if (state.status == SearchStatus.done) {
        return _CenteredHint(text: l10n.searchNoResults);
      }
      return _CenteredHint(text: l10n.searchQueryPlaceholder);
    }
    final files = results.files;
    final rows = state.rows;
    return Scrollbar(
      thumbVisibility: true,
      child: ListView.builder(
        itemExtent: null,
        scrollCacheExtent: ScrollCacheExtent.pixels(400),
        itemCount: rows.length + 1,
        itemBuilder: (context, index) {
          if (index == rows.length) {
            // Footer: truncation / engine notices.
            return _ResultsFooter(results: results);
          }
          final row = rows[index];
          return switch (row) {
            SearchFileHeaderRow() => _FileHeaderRow(
              row: row,
              file: files[row.fileIndex],
              onTap: () =>
                  _openMatch(files[row.fileIndex], files[row.fileIndex].matches.first),
            ),
            SearchMatchRow() => _MatchRow(
              row: row,
              file: files[row.fileIndex],
              onTap: () => _openMatch(files[row.fileIndex], row.match),
            ),
          };
        },
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    String? text;
    if (state.status == SearchStatus.done && state.results != null) {
      text = l10n.searchResultsSummary(
        state.results!.totalMatches,
        state.results!.files.length,
      );
    } else if (state.status == SearchStatus.running) {
      text = l10n.searchScanning;
    }
    if (text == null) return const SizedBox.shrink();
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
    );
  }
}

class _ResultsFooter extends StatelessWidget {
  const _ResultsFooter({required this.results});

  final SearchResults results;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final notices = <String>[
      if (results.truncated) l10n.searchTruncated,
      if (results.engine == SearchEngineKind.builtin)
        l10n.searchBuiltinEngineNotice,
    ];
    if (notices.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        notices.join(' · '),
        style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
      ),
    );
  }
}

class _FileHeaderRow extends StatelessWidget {
  const _FileHeaderRow({required this.row, required this.file, this.onTap});

  final SearchFileHeaderRow row;
  final SearchFileResult file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Icon(Icons.description_outlined, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  row.displayPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).smSemibold,
                ),
              ),
              Text(
                '${row.matchCount}',
                style: TpTextStyles.of(
                  context,
                ).xsColored(cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.row, required this.file, this.onTap});

  final SearchMatchRow row;
  final SearchFileResult file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final match = row.match;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${match.lineNo}',
                    textAlign: TextAlign.right,
                    style: TpTextStyles.of(context).xsColored(cs.primary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HighlightedSnippet(
                  snippet: match.snippet,
                  spans: match.spans,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedSnippet extends StatelessWidget {
  const _HighlightedSnippet({required this.snippet, required this.spans});

  final String snippet;
  final List<SearchMatchSpan> spans;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = TpTextStyles.of(context).xs;
    final highlight = base.copyWith(
      color: cs.primary,
      fontWeight: FontWeight.w600,
    );
    final children = <TextSpan>[];
    var cursor = 0;
    for (final span in spans) {
      final start = span.start.clamp(0, snippet.length);
      final end = span.end.clamp(start, snippet.length);
      if (start > cursor) {
        children.add(TextSpan(text: snippet.substring(cursor, start)));
      }
      if (end > start) {
        children.add(
          TextSpan(text: snippet.substring(start, end), style: highlight),
        );
      }
      cursor = end;
    }
    if (cursor < snippet.length) {
      children.add(TextSpan(text: snippet.substring(cursor)));
    }
    return Text.rich(
      TextSpan(children: children.isEmpty ? [TextSpan(text: snippet)] : children),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TpTextStyles.of(context).smColored(cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Small on/off icon toggle (selected fill — same chrome as the diff
/// toolbar's icon toggles).
class _SearchToggle extends StatelessWidget {
  const _SearchToggle({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: selected
              ? cs.onSurface.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 26,
              height: 26,
              child: Icon(
                icon,
                size: context.tpIconSizes.sm,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

