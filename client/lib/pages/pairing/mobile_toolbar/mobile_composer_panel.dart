import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/image_upload_cubit.dart';
import '../../../cubits/mobile_toolbar_cubit.dart';
import '../../../cubits/voice_input_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../services/stt/stt_provider.dart';
import '../../../theme/app_fonts.dart';
import '../../../utils/ui/app_keys.dart';
import '../voice/voice_settings_page.dart';
import 'upload_failure_messenger.dart';
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

  /// Prototype `.cmd-actions .ca` is a 40px circle with a 22px glyph and 16px
  /// gaps. Scaled down one step: the composer covers the mirrored terminal while
  /// it is open, so its own chrome should cost as little of that as it can.
  static const double _buttonSize = 34;

  /// Glyph inside the circular action buttons, sized with them.
  static const double _iconSize = 18;

  static const double _actionGap = 12;

  /// Caps the field at [_fieldLines] text lines with room to spare, so a boosted
  /// line height cannot clip; [minLines]/[maxLines] fix the visible count.
  static const double _fieldMaxHeight = 180;

  /// Visible rows of the empty field. Three rather than the prototype's four —
  /// one line of command is the common case, and the fourth row was buying
  /// nothing at the cost of terminal output behind the panel.
  static const int _fieldLines = 3;

  /// Prototype `.cmd-input` min-height is `calc(1.5em*lines + 26px)`, i.e.
  /// 16·1.5·3 + 26 = 98 at [_fieldLines]: the field stands that tall even when
  /// empty. Pinned as a floor because [TextField.minLines] alone renders a single
  /// line here — the composer's [Scrollbar]/[ConstrainedBox] wrapping collapses
  /// the intrinsic multi-line height back to one row.
  static const double _fieldMinHeight = 98;

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
    // Two messengers stacked, not merged: each stream maps to different copy,
    // and a shared messenger would have to erase the failure type to do both.
    return UploadFailureMessenger(
      failures: context.read<ImageUploadCubit>().failures,
      child: VoiceFailureMessenger(
        failures: _voice.failures,
        child: DecoratedBox(
          key: AppKeys.mobileComposerPanel,
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              top: BorderSide(color: cs.outlineVariant, width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: MobileComposerPanel._fieldMinHeight,
                      maxHeight: MobileComposerPanel._fieldMaxHeight,
                    ),
                    child: Scrollbar(
                      child: TextField(
                        key: AppKeys.mobileComposerField,
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        // Prototype `.cmd-input`: mono 16 / line 1.5.
                        style: appMonoTextStyle(
                          context,
                          fontSize: 16,
                          color: cs.onSurface,
                        ).copyWith(height: 1.5),
                        minLines: MobileComposerPanel._fieldLines,
                        maxLines: MobileComposerPanel._fieldLines,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: l10n.mobileComposerHint,
                          hintStyle: appMonoTextStyle(
                            context,
                            fontSize: 16,
                            color: cs.onSurfaceVariant,
                          ).copyWith(height: 1.5),
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          isDense: true,
                          // Prototype `.cmd-input` is 13/16, tightened with
                          // the rest of the panel.
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          // Prototype `.cmd-input`: 1.5px accent border, r14 —
                          // constant across focus so the field never reflows.
                          border: _fieldBorder(cs),
                          enabledBorder: _fieldBorder(cs),
                          focusedBorder: _fieldBorder(cs),
                        ),
                      ),
                    ),
                  ),
                  // Prototype `.cmd-actions` puts 12px above the action row; 6
                  // here. The circles carry their own visual padding, so a wide
                  // gap only pushed the terminal further off screen.
                  const SizedBox(height: 6),
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
                        const SizedBox(width: MobileComposerPanel._actionGap),
                        _CircleButton(
                          icon: Icons.keyboard_hide,
                          tooltip: l10n.mobileToolbarHideKeyboard,
                          onTap: () => FocusScope.of(context).unfocus(),
                        ),
                        const SizedBox(width: MobileComposerPanel._actionGap),
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
                        const SizedBox(width: MobileComposerPanel._actionGap),
                        BlocBuilder<ImageUploadCubit, ImageUploadState>(
                          // ImageUploadState has no value equality and progress
                          // emits on every ack, so this guard keeps the rest of
                          // the row out of the rebuild.
                          buildWhen: (before, after) =>
                              before.status != after.status ||
                              before.progress != after.progress,
                          builder: (context, upload) =>
                              _AttachButton(state: upload),
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
                            final voice = context.read<VoiceInputCubit>();
                            void openSettings() => Navigator.of(
                              context,
                            ).push(VoiceSettingsPage.route(voice));
                            // The mic always shows, matching the prototype's fixed
                            // action row — a hidden control would reflow the whole
                            // strip the moment a backend appears. When no backend
                            // can run yet, the tap routes to settings (its only
                            // useful outcome) instead of failing opaquely.
                            return Padding(
                              padding: const EdgeInsets.only(
                                right: MobileComposerPanel._actionGap,
                              ),
                              child: _MicButton(
                                state: voiceState,
                                // An unconfigured backend has no credentials, so a
                                // tap could only fail opaquely from here.
                                // Configuration is the tap's only useful outcome,
                                // so send it to the settings page.
                                onStart: voiceState.configured
                                    ? voice.startListening
                                    : openSettings,
                                onStop: voice.stopListening,
                                // A spare gesture: dictation is tap-to-toggle, so
                                // long-press is free to give the settings page a
                                // close-at-hand entry (it is otherwise several
                                // taps away on the home screen).
                                onSettings: openSettings,
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
      ),
    );
  }
}

/// Prototype `.cmd-input` border: 1.5px accent, 14px radius. Colors stay
/// theme-driven — the accent maps to [ColorScheme.primary].
OutlineInputBorder _fieldBorder(ColorScheme cs) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(14),
  borderSide: BorderSide(color: cs.primary, width: 1.5),
);

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
    final button = TpIconButton(
      key: buttonKey,
      icon: icon,
      tooltip: tooltip,
      onTap: onTap,
      size: MobileComposerPanel._buttonSize,
      iconSize: MobileComposerPanel._iconSize,
      borderRadius: MobileComposerPanel._buttonSize / 2,
      color: filled ? cs.onPrimary : cs.onSurfaceVariant,
      backgroundColor: filled ? cs.primary : cs.surfaceContainerHighest,
    );
    // Prototype `.ca`: 1px border on the non-amber chips; the amber ones drop it.
    if (filled) return button;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: button,
    );
  }
}

/// The attach-image control: a `+` when idle, a spinner while picking or
/// uploading.
///
/// The uploading spinner is *determinate* — deliberately unlike every other
/// progress indicator in the pairing UI, which all spin indeterminately. During
/// an upload the byte count is genuinely known, and an indeterminate ring would
/// throw that information away. While picking there is no byte count yet, so the
/// ring falls back to indeterminate.
class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.state});

  final ImageUploadState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    if (state.status == ImageUploadStatus.idle) {
      return _CircleButton(
        buttonKey: AppKeys.mobileComposerAttachButton,
        icon: Icons.add,
        tooltip: l10n.mobileComposerAttach,
        onTap: () => context.read<ImageUploadCubit>().pickAndUpload(),
      );
    }

    // Picking or uploading: a non-tappable chip matching [_CircleButton]'s look.
    return Container(
      width: MobileComposerPanel._buttonSize,
      height: MobileComposerPanel._buttonSize,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(
          MobileComposerPanel._buttonSize / 2,
        ),
      ),
      child: Center(
        child: SizedBox(
          width: MobileComposerPanel._iconSize,
          height: MobileComposerPanel._iconSize,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            // Determinate only while uploading; picking has no bytes yet.
            value: state.status == ImageUploadStatus.uploading
                ? state.progress
                : null,
          ),
        ),
      ),
    );
  }
}

/// The dictation control: a three-state mic (idle / starting / listening) with
/// a provider badge, and a pulse ring while a session is live.
///
/// Its own widget rather than a [_CircleButton] because the pulse needs an
/// [AnimationController], which a `StatelessWidget` cannot own. It also owns its
/// own tap and long-press through a single [GestureDetector] rather than a
/// [TpIconButton]: a tooltip's long-press recognizer would win the gesture
/// arena and swallow [onSettings], and long-press-to-settings and a long-press
/// tooltip cannot coexist anyway.
class _MicButton extends StatefulWidget {
  const _MicButton({
    required this.state,
    required this.onStart,
    required this.onStop,
    required this.onSettings,
  });

  final VoiceInputState state;
  final VoidCallback onStart;
  final VoidCallback onStop;

  /// Opens the voice settings page — the long-press action, and the tap action
  /// when the selected backend is unconfigured.
  final VoidCallback onSettings;

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

    // The tap action, or null while starting — that window shows a spinner and
    // must not be tappable.
    final VoidCallback? onTap = switch (status) {
      VoiceInputStatus.idle => widget.onStart,
      VoiceInputStatus.starting => null,
      VoiceInputStatus.listening => widget.onStop,
    };

    final Widget control = switch (status) {
      VoiceInputStatus.idle => _circle(cs, icon: Icons.mic_none),
      // Minting a token and shaking hands takes a beat; a spinner reads as
      // working, an idle-looking button reads as an unresponsive tap.
      VoiceInputStatus.starting => _circle(
        cs,
        child: const SizedBox(
          width: MobileComposerPanel._iconSize,
          height: MobileComposerPanel._iconSize,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      VoiceInputStatus.listening => _circle(cs, icon: Icons.mic, filled: true),
    };

    return GestureDetector(
      // A single detector owns tap and long-press so the two never contend in
      // the gesture arena the way a nested tooltip's long-press would.
      key: status == VoiceInputStatus.starting
          ? null
          : AppKeys.mobileComposerMicButton,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: widget.onSettings,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (status == VoiceInputStatus.listening)
            _PulseRing(animation: _pulse, color: cs.primary),
          // The mic supplies its own accessibility label rather than borrowing
          // [TpIconButton]'s tooltip: a tooltip's long-press recognizer would
          // win the gesture arena and swallow the long-press-to-settings
          // gesture the enclosing [GestureDetector] owns. Do not "simplify"
          // this into a Tooltip — that silently breaks long-press.
          Semantics(
            button: true,
            label: status == VoiceInputStatus.listening
                ? l10n.voiceInputStop
                : l10n.voiceInputStart,
            child: control,
          ),
          // The prototype's mic is a plain circle. The badge earns its corner
          // only for a cloud backend, where which one is live is worth knowing;
          // the on-device recognizer is the implicit default, so it stays bare.
          if (widget.state.provider != SttProviderType.system)
            Positioned(
              right: 0,
              top: 0,
              child: _ProviderBadge(provider: widget.state.provider),
            ),
        ],
      ),
    );
  }

  /// The mic's circular chip. Mirrors [_CircleButton]'s look without its
  /// [TpIconButton] gestures, which the enclosing [GestureDetector] replaces.
  Widget _circle(
    ColorScheme cs, {
    IconData? icon,
    Widget? child,
    bool filled = false,
  }) {
    return Container(
      width: MobileComposerPanel._buttonSize,
      height: MobileComposerPanel._buttonSize,
      decoration: BoxDecoration(
        color: filled ? cs.primary : cs.surfaceContainerHighest,
        border: filled ? null : Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(
          MobileComposerPanel._buttonSize / 2,
        ),
      ),
      child: Center(
        child:
            child ??
            Icon(
              icon,
              size: MobileComposerPanel._iconSize,
              color: filled ? cs.onPrimary : cs.onSurfaceVariant,
            ),
      ),
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
          // Fixed, not typography-scaled: this badge sits in the corner of the
          // fixed circular chip ([MobileComposerPanel._buttonSize]) and would
          // overflow it if it grew with the text scale. Leave it literal so the
          // chip stays intact.
          fontSize: 9,
          height: 1,
          fontWeight: FontWeight.w700,
          color: cs.onPrimary,
        ),
      ),
    );
  }
}
