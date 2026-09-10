import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/commands/shortcut_focus.dart';

/// Shows the go-to-line prompt over the current route.
///
/// Enter (or the button) moves [controller]'s collapsed cursor to the entered
/// 1-based line — clamped to the document, numbered as the gutter numbers it
/// (fold-aware) — and centers it in the viewport. Empty input just closes.
Future<void> showEditorGotoLineDialog(
  BuildContext context, {
  required CodeLineEditingController controller,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => EditorGotoLineDialog(controller: controller),
  );
}

class EditorGotoLineDialog extends StatefulWidget {
  const EditorGotoLineDialog({required this.controller, super.key});

  final CodeLineEditingController controller;

  @override
  State<EditorGotoLineDialog> createState() => _EditorGotoLineDialogState();
}

class _EditorGotoLineDialogState extends State<EditorGotoLineDialog> {
  late final TextEditingController _input = TextEditingController(
    text: _currentLineLabel(),
  );
  late final FocusNode _focusNode = FocusNode(onKeyEvent: _handleKey);

  int get _currentLine {
    final index = widget.controller.selection.extentIndex;
    if (index < 0) return 0;
    final line = widget.controller.index2lineIndex(index);
    return line < 0 ? 0 : line + 1;
  }

  String _currentLineLabel() {
    final line = _currentLine;
    return line <= 0 ? '' : '$line';
  }

  @override
  void initState() {
    super.initState();
    final text = _input.text;
    if (text.isNotEmpty) {
      // Pre-fill the cursor's line, selected — typing replaces it (VSCode-style).
      _input.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submit() {
    final line = int.tryParse(_input.text.trim());
    Navigator.of(context).pop();
    if (line == null) return;
    _jumpToLine(line);
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
    final lineCount = widget.controller.lineCount;
    return Align(
      alignment: const Alignment(0, -0.6),
      child: TpDialog(
        maxWidth: 420,
        contentPadding: EdgeInsets.zero,
        child: ShortcutFocus(
          kind: ShortcutFocusKind.text,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpDialogHeader(title: l10n.editorGotoLineTitle),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TpInput(
                      controller: _input,
                      focusNode: _focusNode,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.editorGotoLineRangeHint(lineCount),
                            style: TpTextStyles.of(context).xsColored(
                              Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TpButton(
                          onPressed: _submit,
                          child: Text(l10n.editorGotoLineSubmit),
                        ),
                      ],
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
}
