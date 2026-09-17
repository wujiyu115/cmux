import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../services/editor/editor_symbols.dart';

/// Go-to-symbol picker (VSCode Ctrl+Shift+O): fuzzy-filtered symbol list for
/// one open document; picking a symbol pops the sheet and jumps the editor
/// to its line (centered).
Future<void> showEditorSymbolSheet(
  BuildContext context, {
  required CodeLineEditingController controller,
  required String path,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => EditorSymbolSheet(controller: controller, path: path),
  );
}

class EditorSymbolSheet extends StatefulWidget {
  const EditorSymbolSheet({
    required this.controller,
    required this.path,
    super.key,
  });

  final CodeLineEditingController controller;
  final String path;

  @override
  State<EditorSymbolSheet> createState() => _EditorSymbolSheetState();
}

class _EditorSymbolSheetState extends State<EditorSymbolSheet> {
  final _input = TextEditingController();
  late final FocusNode _inputFocus = FocusNode(onKeyEvent: _handleKey);
  late final List<EditorSymbol> _symbols =
      extractEditorSymbols(widget.path, widget.controller.text);

  List<EditorSymbol> get _filtered {
    final query = _input.text.trim().toLowerCase();
    if (query.isEmpty) return _symbols;
    return [
      for (final symbol in _symbols)
        if (symbol.name.toLowerCase().contains(query)) symbol,
    ];
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _select(EditorSymbol symbol) {
    Navigator.of(context).pop();
    _jumpToLine(symbol.line + 1);
  }

  void _jumpToLine(int line) {
    final controller = widget.controller;
    final lineCount = controller.lineCount;
    if (lineCount <= 0) return;
    final clamped = line.clamp(1, lineCount);
    // Gutter numbering is line-index based; map back through the fold-aware
    // code index so collapsed regions land on their parent line.
    final index = controller.lineIndex2Index(clamped - 1).index;
    controller.selection = CodeLineSelection.collapsed(
      index: index < 0 ? 0 : index,
      offset: 0,
    );
    controller.makeCursorCenterIfInvisible();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filtered = _filtered;
    return Align(
      alignment: const Alignment(0, -0.6),
      child: TpDialog(
        maxWidth: 460,
        contentPadding: EdgeInsets.zero,
        child: ShortcutFocus(
          kind: ShortcutFocusKind.text,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpDialogHeader(title: l10n.editorGotoSymbolTitle),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TpInput(
                      controller: _input,
                      focusNode: _inputFocus,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (filtered.isNotEmpty) _select(filtered.first);
                      },
                      decoration: InputDecoration(
                        hintText: l10n.editorGotoSymbolHint,
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_symbols.isEmpty)
                      Text(
                        l10n.editorGotoSymbolNone,
                        style: TpTextStyles.of(context).smColored(
                          Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    else if (filtered.isEmpty)
                      Text(
                        l10n.quickOpenNoResults,
                        style: TpTextStyles.of(context).smColored(
                          Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      SizedBox(
                        height: 280,
                        child: ListView.builder(
                          itemExtent: 34,
                          scrollCacheExtent: ScrollCacheExtent.pixels(300),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final symbol = filtered[index];
                            return InkWell(
                              onTap: () => _select(symbol),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: 16.0 + symbol.depth * 12,
                                    right: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _iconFor(symbol.kind),
                                        size: 14,
                                        color:
                                            Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          symbol.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TpTextStyles.of(context).sm,
                                        ),
                                      ),
                                      Text(
                                        '${symbol.line + 1}',
                                        style: TpTextStyles.of(
                                          context,
                                        ).xsColored(
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(EditorSymbolKind kind) => switch (kind) {
    EditorSymbolKind.heading => Icons.tag,
    EditorSymbolKind.type => Icons.account_balance_outlined,
    EditorSymbolKind.callable => Icons.functions,
    EditorSymbolKind.key => Icons.vpn_key_outlined,
  };
}
