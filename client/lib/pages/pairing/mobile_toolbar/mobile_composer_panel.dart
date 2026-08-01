import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/mobile_toolbar_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../utils/ui/app_keys.dart';

/// Multi-line composer for the mirrored terminal.
///
/// Typing straight into a terminal over a phone keyboard is unforgiving — the
/// PTY echoes every character and a typo means retyping the line. Here the text
/// is local until the send button, so it can be edited, and Return inserts a
/// newline instead of submitting (the deliberate opposite of the terminal, where
/// Return submits).
///
/// [controller] and [focusNode] belong to the caller: the panel is unmounted
/// whenever the user flips to the key bar, and the draft has to survive that.
class MobileComposerPanel extends StatefulWidget {
  const MobileComposerPanel({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  static const double _buttonSize = 34;
  static const double _fieldMaxHeight = 120;

  @override
  State<MobileComposerPanel> createState() => _MobileComposerPanelState();
}

class _MobileComposerPanelState extends State<MobileComposerPanel> {
  @override
  void initState() {
    super.initState();
    // Taking focus here also drops the terminal's own IME client, so the two
    // never fight over the single soft keyboard.
    widget.focusNode.requestFocus();
  }

  void _send(bool submit) {
    context.read<MobileToolbarCubit>().sendText(
      widget.controller.text,
      submit: submit,
    );
    widget.controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final cubit = context.read<MobileToolbarCubit>();
    return DecoratedBox(
      key: AppKeys.mobileComposerPanel,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: MobileComposerPanel._fieldMaxHeight,
                ),
                child: Scrollbar(
                  child: TextField(
                    key: AppKeys.mobileComposerField,
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    style: TextStyle(color: cs.onSurface, fontSize: 15),
                    minLines: 3,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: l10n.mobileComposerHint,
                      hintStyle: TextStyle(color: cs.onSurfaceVariant),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              BlocBuilder<MobileToolbarCubit, MobileToolbarState>(
                // Only the Return-mode flag changes anything in this row, and
                // the state re-emits on every key tap.
                buildWhen: (before, after) =>
                    before.chatMode != after.chatMode,
                builder: (context, state) => Row(
                  children: [
                    _CircleButton(
                      buttonKey: AppKeys.mobileComposerCloseButton,
                      icon: Icons.close,
                      tooltip: l10n.mobileComposerClose,
                      onTap: () {
                        // Drop the keyboard before the field disappears —
                        // otherwise the focus node stays focused with no
                        // TextField mounted and the keyboard hangs around over
                        // the key bar.
                        FocusScope.of(context).unfocus();
                        cubit.setMode(MobileInputMode.keys);
                      },
                    ),
                    const SizedBox(width: 8),
                    _CircleButton(
                      icon: Icons.keyboard_hide,
                      tooltip: l10n.mobileToolbarHideKeyboard,
                      onTap: () => FocusScope.of(context).unfocus(),
                    ),
                    const SizedBox(width: 8),
                    _CircleButton(
                      buttonKey: AppKeys.mobileComposerSubmitToggle,
                      icon: state.chatMode
                          ? Icons.keyboard_return
                          : Icons.text_fields,
                      tooltip: state.chatMode
                          ? l10n.mobileComposerSubmitOn
                          : l10n.mobileComposerSubmitOff,
                      filled: state.chatMode,
                      onTap: cubit.toggleChatMode,
                    ),
                    const Spacer(),
                    _CircleButton(
                      buttonKey: AppKeys.mobileComposerSendButton,
                      icon: Icons.arrow_upward,
                      tooltip: l10n.mobileComposerSend,
                      filled: true,
                      onTap: () => _send(state.chatMode),
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

/// Round variant of [TpIconButton] — the composer's controls read as chips
/// rather than as toolbar squares.
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.filled = false,
  });

  final Key? buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TpIconButton(
      key: buttonKey,
      icon: icon,
      tooltip: tooltip,
      onTap: onTap,
      size: MobileComposerPanel._buttonSize,
      iconSize: 18,
      borderRadius: MobileComposerPanel._buttonSize / 2,
      color: filled ? cs.onPrimary : cs.onSurfaceVariant,
      backgroundColor: filled ? cs.primary : cs.surfaceContainerHighest,
    );
  }
}
