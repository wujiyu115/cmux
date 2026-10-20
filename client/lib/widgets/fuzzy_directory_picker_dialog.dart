import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../l10n/l10n_extensions.dart';
import '../services/storage/remote_directory_browser.dart';
import '../services/storage/workspace_directory_picker.dart';
import '../utils/commands/fuzzy_match.dart';

/// Filesystem-backed directory picker with fuzzy folder search: a filter field
/// above the listing narrows the current directory's subfolders via the shared
/// [fuzzyMatch] (same ranking/highlight as quick-open and the command palette).
///
/// A local alternative to the native `FilePicker` directory dialog (which has
/// no filtering); remote targets (SSH/WSL) work identically because the
/// browser is fs-injected. Falls back to the native picker on failure via the
/// caller (`pickWorkspaceDirectoryPath` keeps the old path as fallback).
Future<String?> showFuzzyDirectoryPickerDialog(
  BuildContext context, {
  required String targetId,
  String? initialPath,
  String? title,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        FuzzyDirectoryPickerDialog(targetId: targetId, initialPath: initialPath, title: title),
  );
}

class FuzzyDirectoryPickerDialog extends StatefulWidget {
  const FuzzyDirectoryPickerDialog({
    super.key,
    required this.targetId,
    this.initialPath,
    this.title,
  });

  final String targetId;
  final String? initialPath;
  final String? title;

  @override
  State<FuzzyDirectoryPickerDialog> createState() =>
      _FuzzyDirectoryPickerDialogState();
}

class _FuzzyDirectoryPickerDialogState
    extends State<FuzzyDirectoryPickerDialog> {
  final _filterController = TextEditingController();
  final _filterFocus = FocusNode();
  RemoteDirectoryBrowser? _browser;
  RemoteDirectoryListing? _listing;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _filterController.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final picker = context.read<WorkspaceDirectoryPicker>();
    try {
      final fs = await picker.filesystemFor(widget.targetId);
      final browser = RemoteDirectoryBrowser(fs);
      final start =
          widget.initialPath ?? await picker.homeFor(widget.targetId);
      final initial = await browser.resolveInitial(start);
      final listing = await browser.list(initial);
      if (!mounted) return;
      setState(() {
        _browser = browser;
        _listing = listing;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.fuzzyDirectoryPickerError;
      });
    }
  }

  Future<void> _open(String path) async {
    final browser = _browser;
    if (browser == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await browser.list(path);
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _loading = false;
        _filterController.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.fuzzyDirectoryPickerError;
      });
    }
  }

  /// Fuzzy-filtered view of the current listing, best score first.
  List<(String, FuzzyMatch)> get _filtered {
    final listing = _listing;
    if (listing == null) return const [];
    final query = _filterController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return [
        for (final name in listing.directories) (name, const FuzzyMatch([], 0)),
      ];
    }
    final scored = <(String, FuzzyMatch)>[];
    for (final name in listing.directories) {
      final match = fuzzyMatch(name, query);
      if (match != null) scored.add((name, match));
    }
    scored.sort((a, b) => b.$2.score.compareTo(a.$2.score));
    return scored;
  }

  void _useCurrent() {
    final path = _listing?.path;
    if (path == null) return;
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final listing = _listing;
    final entries = _filtered;
    final query = _filterController.text.trim();

    return TpDialog(
      maxWidth: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: widget.title ?? l10n.fuzzyDirectoryPickerTitle),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.remoteDirectoryBrowserUpOneLevel,
                  icon: Icon(
                    Icons.arrow_upward_rounded,
                    size: context.tpIconSizes.md,
                  ),
                  onPressed:
                      listing != null && listing.parent != null && !_loading
                      ? () => _open(listing.parent!)
                      : null,
                ),
                Expanded(
                  child: SelectableText(
                    listing?.path ?? '…',
                    maxLines: 1,
                    style: styles.md,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TpInput(
              controller: _filterController,
              focusNode: _filterFocus,
              onChanged: (_) => setState(() {}),
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: context.tpIconSizes.md),
                hintText: l10n.fuzzyDirectoryPickerFilterHint,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            // Fills available dialog height up to 264px; smaller viewports
            // (or low-resolution desktops) shrink the list instead of
            // overflowing the dialog.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 264),
                child: _buildBody(cs, styles, entries, query, l10n),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: styles.smColored(cs.error)),
          ],
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: listing != null && !_loading ? _useCurrent : null,
                child: Text(l10n.remoteDirectoryBrowserUseThisDirectory),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    ColorScheme cs,
    TpTextStyles styles,
    List<(String, FuzzyMatch)> entries,
    String query,
    AppLocalizations l10n,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (query.isEmpty && (_listing?.directories.isEmpty ?? true)) {
      return Center(
        child: Text(l10n.remoteDirectoryBrowserEmpty, style: styles.mutedSm),
      );
    }
    if (entries.isEmpty) {
      return Center(
        child: Text(l10n.fuzzyDirectoryPickerNoMatch, style: styles.mutedSm),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final (name, match) = entries[index];
          return ListTile(
            leading: Icon(Icons.folder_outlined, size: context.tpIconSizes.md),
            title: query.isEmpty
                ? Text(name)
                : _HighlightedName(name: name, match: match),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: context.tpIconSizes.md,
            ),
            onTap: () => _open(_browser!.child(_listing!.path, name)),
          );
        },
      ),
    );
  }
}

/// Name with the fuzzy-matched characters emphasized, same convention as
/// quick-open results.
class _HighlightedName extends StatelessWidget {
  const _HighlightedName({required this.name, required this.match});

  final String name;
  final FuzzyMatch match;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spans = <TextSpan>[];
    final indexes = match.indexes;
    var cursor = 0;
    for (var i = 0; i < indexes.length; i++) {
      final hit = indexes[i];
      if (hit > cursor) {
        spans.add(TextSpan(text: name.substring(cursor, hit)));
      }
      final end = hit + 1;
      spans.add(
        TextSpan(
          text: name.substring(hit, end),
          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
        ),
      );
      cursor = end;
    }
    if (cursor < name.length) {
      spans.add(TextSpan(text: name.substring(cursor)));
    }
    return Text.rich(TextSpan(style: styles.md, children: spans));
  }
}
