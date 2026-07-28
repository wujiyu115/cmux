import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/shortcut_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../repositories/command_mru_repository.dart';
import '../../services/commands/command_bus.dart';
import '../../services/commands/command_catalog.dart';
import '../../services/commands/command_definition.dart';
import '../../services/commands/command_l10n.dart';
import '../../services/commands/key_chord.dart';
import '../../services/commands/key_chord_formatter.dart';
import '../../services/commands/shortcut_context.dart';
import '../../services/commands/shortcut_dispatcher_handle.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../utils/commands/command_palette_filter.dart';

/// Opens the command palette (`Ctrl+Shift+P`). Loads the MRU order, shows the
/// overlay, and — after the route pops with the chosen id — records it in the
/// MRU list and invokes it on [bus]. Invoking *after* the pop keeps the
/// command's own focus/dialog work from fighting the closing palette.
///
/// [shortcutContext] defaults to the live app snapshot from the root
/// [ShortcutDispatcher] so availability tracks the same `when` state as the
/// keyboard dispatcher.
Future<void> showCommandPalette(
  BuildContext context, {
  required CommandBus bus,
  required CommandMruRepository mruRepository,
  ShortcutContext? shortcutContext,
}) async {
  final mru = await mruRepository.load();
  if (!context.mounted) return;
  final resolvedContext =
      shortcutContext ??
      ShortcutDispatcherHandle.instance?.currentContext ??
      const ShortcutContext();

  final selectedId = await showDialog<String>(
    context: context,
    builder: (_) => CommandPaletteOverlay(
      bus: bus,
      mru: mru,
      shortcutContext: resolvedContext,
    ),
  );
  if (selectedId == null) return;

  await mruRepository.touch(selectedId);
  bus.invoke(selectedId);
}

/// Centred, width-capped command launcher: a search field over a scrolling,
/// keyboard-navigable result list. Pops the enclosing route with the chosen
/// command id (or `null` on dismiss); the caller invokes it.
class CommandPaletteOverlay extends StatefulWidget {
  const CommandPaletteOverlay({
    super.key,
    required this.bus,
    required this.mru,
    required this.shortcutContext,
  });

  final CommandBus bus;
  final List<String> mru;
  final ShortcutContext shortcutContext;

  @override
  State<CommandPaletteOverlay> createState() => _CommandPaletteOverlayState();
}

class _CommandPaletteOverlayState extends State<CommandPaletteOverlay> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _searchFocus = FocusNode(onKeyEvent: _handleKey);
  static const double _rowExtent = 44;

  String _query = '';
  int _selectedIndex = 0;

  /// Latest filtered matches, cached from [build] so the search field's
  /// [FocusNode.onKeyEvent] can act on the current list without a context.
  List<CommandPaletteMatch> _matchesCache = const [];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool _isAvailable(CommandDefinition def) {
    return def.when.isSatisfiedBy(widget.shortcutContext) &&
        widget.bus.hasHandler(def.id);
  }

  List<CommandPaletteMatch> _matches(AppLocalizations l10n) {
    return filterCommandPalette(
      catalog: CommandCatalog.v1,
      query: _query,
      titleOf: (def) => titleForCommand(l10n, def.id),
      isAvailable: _isAvailable,
      mru: widget.mru,
      categoryTitleOf: (def) => titleForCategory(l10n, def.category),
    );
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
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

  void _invoke() {
    if (_selectedIndex < 0 || _selectedIndex >= _matchesCache.length) return;
    Navigator.of(context).pop(_matchesCache[_selectedIndex].command.id);
  }

  void _invokeAt(int index) {
    if (index < 0 || index >= _matchesCache.length) return;
    Navigator.of(context).pop(_matchesCache[index].command.id);
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
      _moveSelection(1, _matchesCache.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1, _matchesCache.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _invoke();
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
    return BlocBuilder<ShortcutCubit, ShortcutState>(
      builder: (context, shortcutState) {
        final matches = _matches(l10n);
        _matchesCache = matches;
        if (_selectedIndex >= matches.length) {
          _selectedIndex = matches.isEmpty ? 0 : matches.length - 1;
        }
        return Align(
          alignment: const Alignment(0, -0.6),
          child: TpDialog(
            maxWidth: 560,
            maxHeight: 480,
            contentPadding: EdgeInsets.zero,
            child: ShortcutFocus(
              kind: ShortcutFocusKind.text,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SearchRow(
                    controller: _controller,
                    focusNode: _searchFocus,
                    hintText: l10n.commandPaletteSearchHint,
                    onChanged: _onQueryChanged,
                    onSubmitted: _invoke,
                  ),
                  const TpSeparator(),
                  Flexible(
                    child: matches.isEmpty
                        ? _EmptyState(text: l10n.commandPaletteEmpty)
                        : _ResultList(
                            matches: matches,
                            selectedIndex: _selectedIndex,
                            scrollController: _scrollController,
                            rowExtent: _rowExtent,
                            effective: shortcutState.effective,
                            onTap: _invokeAt,
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Search field row with a leading search icon.
class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hintText,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
              onSubmitted: (_) => onSubmitted(),
            ),
          ),
        ],
      ),
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
    required this.matches,
    required this.selectedIndex,
    required this.scrollController,
    required this.rowExtent,
    required this.effective,
    required this.onTap,
  });

  final List<CommandPaletteMatch> matches;
  final int selectedIndex;
  final ScrollController scrollController;
  final double rowExtent;
  final Map<String, List<KeyChord>> effective;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final isMacOS = defaultIsMacOS();
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemExtent: rowExtent,
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final match = matches[index];
        final chords = effective[match.command.id] ?? const [];
        return _ResultRow(
          match: match,
          selected: index == selectedIndex,
          chordLabel: chords.isEmpty
              ? null
              : formatKeyChord(chords.first, isMacOS: isMacOS),
          onTap: () => onTap(index),
        );
      },
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.match,
    required this.selected,
    required this.chordLabel,
    required this.onTap,
  });

  final CommandPaletteMatch match;
  final bool selected;
  final String? chordLabel;
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
                  _iconForCategory(match.command.category),
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HighlightedTitle(
                    title: match.title,
                    matchedIndexes: match.matchedIndexes,
                  ),
                ),
                if (chordLabel != null) ...[
                  const SizedBox(width: 12),
                  _ChordBadge(label: chordLabel!),
                ],
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

class _ChordBadge extends StatelessWidget {
  const _ChordBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TpTextStyles.of(context).xsSemiboldColored(cs.onSurfaceVariant),
      ),
    );
  }
}

/// Maps a [CommandCategory] to a representative icon (the definition carries
/// no icon of its own).
IconData _iconForCategory(CommandCategory category) {
  return switch (category) {
    CommandCategory.navigation => Icons.explore_outlined,
    CommandCategory.tabs => Icons.tab_outlined,
    CommandCategory.view => Icons.view_sidebar_outlined,
    CommandCategory.zoom => Icons.zoom_in_outlined,
    CommandCategory.compose => Icons.edit_outlined,
    CommandCategory.run => Icons.play_arrow_outlined,
    CommandCategory.meta => Icons.tune_outlined,
    CommandCategory.terminal => Icons.terminal_outlined,
  };
}
