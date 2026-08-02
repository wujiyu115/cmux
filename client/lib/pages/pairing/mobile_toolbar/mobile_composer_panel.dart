import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/mobile_toolbar_cubit.dart';
import '../../../cubits/voice_input_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../services/stt/stt_provider.dart';
import '../../../utils/ui/app_keys.dart';
import 'voice_failure_messenger.dart';

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
  /// Captured in [initState] so [dispose] can stop the mic without a
  /// `context.read` (which is illegal once the element is defunct). The cubit
  /// lives at the pairing shell; the panel only borrows it.
  late final VoiceInputCubit _voice;

  @override
  void initState() {
    super.initState();
    _voice = context.read<VoiceInputCubit>();
    // Taking focus here also drops the terminal's own IME client, so the two
    // never fight over the single soft keyboard.
    widget.focusNode.requestFocus();
  }

  @override
  void dispose() {
    // One of the four paths that must not leave the microphone hot: flipping
    // the bottom slot back to the key bar unmounts this panel, and a mic
    // outliving its panel is a privacy problem, not a cosmetic one.
    _voice.stopListening();
    super.dispose();
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
    return VoiceFailureMessenger(
      failures: _voice.failures,
      child: DecoratedBox(
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
                          // One of the four paths that must not leave the
                          // microphone hot. Fire-and-forget: the callback is
                          // synchronous and the stop is best-effort.
                          context.read<VoiceInputCubit>().stopListening();
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
                      BlocBuilder<VoiceInputCubit, VoiceInputState>(
                        // VoiceInputState has no value equality: without this
                        // guard every emit would rebuild — and restart — the
                        // pulse animation.
                        buildWhen: (a, b) =>
                            a.status != b.status ||
                            a.available != b.available ||
                            a.provider != b.provider,
                        builder: (context, voiceState) {
                          // No backend can run: a tap could only ever fail, so
                          // the mic is not offered.
                          if (!voiceState.available) {
                            return const SizedBox.shrink();
                          }
                          final voice = context.read<VoiceInputCubit>();
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _MicButton(
                              state: voiceState,
                              // An unconfigured cloud backend has no credentials,
                              // so startListening returns early and the tap is
                              // inert; routing that tap to settings is Task 10.
                              onStart: voice.startListening,
                              onStop: voice.stopListening,
                            ),
                          );
                        },
                      ),
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

/// The dictation control: a three-state mic (idle / starting / listening) with
/// a provider badge, and a pulse ring while a session is live.
///
/// Its own widget rather than a [_CircleButton] because the pulse needs an
/// [AnimationController], which a `StatelessWidget` cannot own.
class _MicButton extends StatefulWidget {
  const _MicButton({
    required this.state,
    required this.onStart,
    required this.onStop,
  });

  final VoiceInputState state;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(_MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.status != widget.state.status) _syncPulse();
  }

  /// Only run the ring while listening — no controller work happens in the
  /// other two states.
  void _syncPulse() {
    if (widget.state.status == VoiceInputStatus.listening) {
      _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final status = widget.state.status;

    final Widget control = switch (status) {
      VoiceInputStatus.idle => _CircleButton(
        buttonKey: AppKeys.mobileComposerMicButton,
        icon: Icons.mic_none,
        tooltip: l10n.voiceInputStart,
        onTap: widget.onStart,
      ),
      // Minting a token and shaking hands takes a beat; a spinner reads as
      // working, an idle-looking button reads as an unresponsive tap. Not
      // tappable.
      VoiceInputStatus.starting => Container(
        width: MobileComposerPanel._buttonSize,
        height: MobileComposerPanel._buttonSize,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(
            MobileComposerPanel._buttonSize / 2,
          ),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      VoiceInputStatus.listening => _CircleButton(
        buttonKey: AppKeys.mobileComposerMicButton,
        icon: Icons.mic,
        tooltip: l10n.voiceInputStop,
        filled: true,
        onTap: widget.onStop,
      ),
    };

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (status == VoiceInputStatus.listening)
          _PulseRing(animation: _pulse, color: cs.primary),
        control,
        Positioned(
          right: 0,
          top: 0,
          child: _ProviderBadge(provider: widget.state.provider),
        ),
      ],
    );
  }
}

/// Expanding, fading ring drawn behind the mic while a session is live.
class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          return Transform.scale(
            scale: lerpDouble(1.0, 1.8, t)!,
            child: Opacity(
              opacity: lerpDouble(0.4, 0.0, t)!,
              child: Container(
                width: MobileComposerPanel._buttonSize,
                height: MobileComposerPanel._buttonSize,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Three-character badge in the mic's top corner naming the active backend.
class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.provider});

  final SttProviderType provider;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final label = switch (provider) {
      SttProviderType.system => l10n.voiceInputBadgeSystem,
      SttProviderType.volcengine => l10n.voiceInputBadgeVolcengine,
      SttProviderType.aliyun => l10n.voiceInputBadgeAliyun,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          height: 1,
          fontWeight: FontWeight.w700,
          color: cs.onPrimary,
        ),
      ),
    );
  }
}
