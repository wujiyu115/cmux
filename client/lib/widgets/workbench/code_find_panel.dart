import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// Tp-styled find/replace panel rendered by [CodeEditor]'s `findBuilder` as an
/// overlay above the content (top-right, VS Code style). Collapses to zero
/// height when the controller is closed.
///
/// The editor's own shortcut layer only covers the editing surface, so the
/// panel carries its own key handling for the inputs: Enter / Shift+Enter /
/// F3 step matches, Esc closes, Ctrl/Cmd+F refocuses the find input.
class CodeFindPanel extends StatelessWidget implements PreferredSizeWidget {
  const CodeFindPanel({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  static const double _rowHeight = 48;
  static const double _panelWidth = 400;
  static const EdgeInsetsGeometry _margin = EdgeInsets.only(top: 8, right: 12);
  static const double _chipWidth = 34;
  static const double _leadingControlWidth =
      TpIconButton.kCompactSize + 6;

  final CodeFindController controller;
  final bool readOnly;

  int get _rowCount {
    final value = controller.value;
    if (value == null) return 0;
    return !readOnly && value.replaceMode ? 2 : 1;
  }

  @override
  Size get preferredSize => Size(
    double.infinity,
    _rowCount * _rowHeight + _margin.vertical,
  );

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox(width: 0, height: 0);
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: _margin,
      alignment: Alignment.topRight,
      height: _rowCount * _rowHeight,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: cs.surfaceContainerHighest,
        child: Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.escape):
                const _CodeFindCloseIntent(),
            const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                const _CodeFindPreviousIntent(),
            const SingleActivator(LogicalKeyboardKey.f3):
                const _CodeFindNextIntent(),
            const SingleActivator(LogicalKeyboardKey.f3, shift: true):
                const _CodeFindPreviousIntent(),
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                const _CodeFindFocusIntent(),
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                const _CodeFindFocusIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _CodeFindCloseIntent: CallbackAction<_CodeFindCloseIntent>(
                onInvoke: (_) {
                  controller.close();
                  return null;
                },
              ),
              _CodeFindPreviousIntent:
                  CallbackAction<_CodeFindPreviousIntent>(
                    onInvoke: (_) {
                      controller.previousMatch();
                      return null;
                    },
                  ),
              _CodeFindNextIntent: CallbackAction<_CodeFindNextIntent>(
                onInvoke: (_) {
                  controller.nextMatch();
                  return null;
                },
              ),
              _CodeFindFocusIntent: CallbackAction<_CodeFindFocusIntent>(
                onInvoke: (_) {
                  controller.findMode();
                  return null;
                },
              ),
            },
            child: SizedBox(
              width: _panelWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildFindRow(context, value),
                  if (!readOnly && value.replaceMode)
                    _buildReplaceRow(context, value),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFindRow(BuildContext context, CodeFindValue value) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final result = value.result;
    final hasMatches = result != null && result.matches.isNotEmpty;
    return SizedBox(
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (!readOnly)
              TpIconButton(
                icon: value.replaceMode
                    ? Icons.expand_less
                    : Icons.expand_more,
                tooltip: l10n.editorFindToggleReplace,
                compact: true,
                onTap: controller.toggleMode,
              ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: controller.findInputController,
                focusNode: controller.findInputFocusNode,
                maxLines: 1,
                style: TpTextStyles.of(context).sm,
                decoration: _inputDecoration(
                  context,
                  hint: l10n.editorFindHint,
                  suffix: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ToggleChip(
                        label: 'Aa',
                        tooltip: l10n.editorFindCaseSensitive,
                        checked: value.option.caseSensitive,
                        onTap: controller.toggleCaseSensitive,
                      ),
                      _ToggleChip(
                        label: '.*',
                        tooltip: l10n.editorFindRegex,
                        checked: value.option.regex,
                        onTap: controller.toggleRegex,
                      ),
                    ],
                  ),
                ),
                onSubmitted: (_) => controller.nextMatch(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Text(
                _resultLabel(value, l10n.editorFindNoResults),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TpTextStyles.of(context).sm.copyWith(
                  color: hasMatches ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ),
            TpIconButton(
              icon: Icons.keyboard_arrow_up,
              tooltip: l10n.editorFindPrevious,
              compact: true,
              enabled: hasMatches,
              onTap: controller.previousMatch,
            ),
            TpIconButton(
              icon: Icons.keyboard_arrow_down,
              tooltip: l10n.editorFindNext,
              compact: true,
              enabled: hasMatches,
              onTap: controller.nextMatch,
            ),
            TpIconButton(
              icon: Icons.close,
              tooltip: l10n.editorFindClose,
              compact: true,
              onTap: controller.close,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplaceRow(BuildContext context, CodeFindValue value) {
    final l10n = context.l10n;
    final hasMatches = value.result != null && value.result!.matches.isNotEmpty;
    return SizedBox(
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const SizedBox(width: _leadingControlWidth),
            Expanded(
              child: TextField(
                controller: controller.replaceInputController,
                focusNode: controller.replaceInputFocusNode,
                maxLines: 1,
                style: TpTextStyles.of(context).sm,
                decoration: _inputDecoration(
                  context,
                  hint: l10n.editorReplaceHint,
                ),
                onSubmitted: (_) => controller.replaceMatch(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: TpIconButton(
                icon: Icons.done,
                tooltip: l10n.editorFindReplace,
                compact: true,
                enabled: hasMatches,
                onTap: controller.replaceMatch,
              ),
            ),
            TpIconButton(
              icon: Icons.done_all,
              tooltip: l10n.editorFindReplaceAll,
              compact: true,
              enabled: hasMatches,
              onTap: controller.replaceAllMatches,
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      border: const OutlineInputBorder(),
      suffixIcon: suffix,
    );
  }

  String _resultLabel(CodeFindValue value, String noResults) {
    final result = value.result;
    if (result == null) return '';
    if (result.matches.isEmpty) return noResults;
    return '${result.index + 1}/${result.matches.length}';
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.tooltip,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = checked ? cs.primary : cs.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: CodeFindPanel._chipWidth,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: checked ? cs.primary.withValues(alpha: 0.14) : null,
            ),
            child: Text(
              label,
              style: TpTextStyles.of(context).xsSemibold.copyWith(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeFindCloseIntent extends Intent {
  const _CodeFindCloseIntent();
}

class _CodeFindPreviousIntent extends Intent {
  const _CodeFindPreviousIntent();
}

class _CodeFindNextIntent extends Intent {
  const _CodeFindNextIntent();
}

class _CodeFindFocusIntent extends Intent {
  const _CodeFindFocusIntent();
}
