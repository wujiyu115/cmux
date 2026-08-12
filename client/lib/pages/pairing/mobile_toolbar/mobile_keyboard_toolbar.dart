import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/mobile_toolbar_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/toolbar_key.dart';
import '../../../theme/app_fonts.dart';
import '../../../utils/ui/app_keys.dart';
import 'mobile_toolbar_customize_page.dart';

/// Shortcut-key strip that sits between the mirrored terminal and the soft
/// keyboard, giving a phone the keys iOS/Android simply do not have: Esc, Tab,
/// arrows, signals, F-keys.
///
/// Keys write through [MobileToolbarCubit], never through the terminal's focus
/// node, so the bar keeps working after the soft keyboard is dismissed.
class MobileKeyboardToolbar extends StatelessWidget {
  const MobileKeyboardToolbar({super.key});

  /// The strip sits between the terminal and the soft keyboard, so every pixel
  /// it takes is a row of output the user cannot see. 44 keeps the caps at the
  /// 34px the platform still considers a comfortable target while giving one more
  /// terminal line back than the prototype's 52.
  static const double barHeight = 44;

  /// Slightly above the icon-button default (`sizes.md` ≈ 24) rather than the 28
  /// it was: at 28 the three trailing glyphs read heavier than the key caps they
  /// sit beside.
  static const double _iconSize = 22;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: AppKeys.mobileToolbar,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: [
              Expanded(
                child: BlocBuilder<MobileToolbarCubit, MobileToolbarState>(
                  // The state carries a tap counter that changes on every
                  // keypress, and it has no value equality, so an unfiltered
                  // builder would rebuild all sixty-odd caps per tap. Only the
                  // four fields the strip actually draws matter here.
                  buildWhen: (before, after) =>
                      before.ctrl != after.ctrl ||
                      before.alt != after.alt ||
                      before.visibleGroupCount != after.visibleGroupCount ||
                      !identical(before.groupOrder, after.groupOrder),
                  builder: (context, state) =>
                      _CapStrip(children: _caps(context, state)),
                ),
              ),
              TpIconButton(
                key: AppKeys.mobileToolbarComposerButton,
                icon: Icons.chat_bubble_outline,
                tooltip: context.l10n.mobileComposerOpen,
                size: barHeight,
                iconSize: _iconSize,
                onTap: context.read<MobileToolbarCubit>().toggleComposer,
              ),
              TpIconButton(
                key: AppKeys.mobileToolbarCustomizeButton,
                icon: Icons.tune,
                tooltip: context.l10n.mobileToolbarCustomize,
                size: barHeight,
                iconSize: _iconSize,
                onTap: () => Navigator.of(context).push(
                  MobileToolbarCustomizePage.route(
                    context.read<MobileToolbarCubit>(),
                  ),
                ),
              ),
              TpIconButton(
                key: AppKeys.mobileToolbarHideKeyboardButton,
                icon: Icons.keyboard_hide,
                tooltip: context.l10n.mobileToolbarHideKeyboard,
                size: barHeight,
                iconSize: _iconSize,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _caps(BuildContext context, MobileToolbarState state) {
    final cubit = context.read<MobileToolbarCubit>();
    final caps = <Widget>[];
    for (final group in state.visibleGroups) {
      if (caps.isNotEmpty) caps.add(const _GroupDivider());
      for (final key in group.keys) {
        caps.add(
          _ToolbarKeyCap(
            key: AppKeys.mobileToolbarKey(key.id),
            toolbarKey: key,
            active: switch (key.special) {
              ToolbarKeySpecial.ctrl => state.ctrl,
              ToolbarKeySpecial.alt => state.alt,
              _ => false,
            },
            onPress: () {
              // A key cap has no travel and no click, so the tap needs some
              // physical confirmation or held arrows feel like nothing happened.
              HapticFeedback.lightImpact();
              cubit.tapKey(key);
            },
          ),
        );
      }
    }
    return caps;
  }
}

/// The horizontally scrolling key caps, with a fade at whichever edge still has
/// caps beyond it.
///
/// Without the fade a wide cap (`Paste`, `Enter`) is sliced clean through by the
/// viewport edge and reads as a rendering bug rather than as "there is more if
/// you swipe" — the strip has no scrollbar on a phone, so the fade is the only
/// affordance it gets.
class _CapStrip extends StatefulWidget {
  const _CapStrip({required this.children});

  final List<Widget> children;

  @override
  State<_CapStrip> createState() => _CapStripState();
}

class _CapStripState extends State<_CapStrip> {
  /// Width of the fade. Wide enough to read as a gradient, narrow enough that a
  /// cap sitting under it is still legible.
  static const _fadeWidth = 20.0;

  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strip = SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: widget.children),
    );
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // No attached position on the first frame: assume nothing is clipped
          // rather than guessing, and let the first scroll notification correct
          // it.
          final position = _controller.hasClients ? _controller.position : null;
          final fadeStart = (position?.pixels ?? 0) > 0;
          final fadeEnd = position != null &&
              position.hasContentDimensions &&
              position.pixels < position.maxScrollExtent;
          // The ShaderMask is unconditional and the gradient degenerates instead:
          // inserting or removing a layer above the strip would rebuild every cap
          // element, which cancels the auto-repeat timer a held arrow key owns
          // and drops the gesture a tap is in the middle of.
          final fade = _fadeWidth / constraints.maxWidth;
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                fadeStart ? Colors.transparent : Colors.white,
                Colors.white,
                Colors.white,
                fadeEnd ? Colors.transparent : Colors.white,
              ],
              stops: [
                0,
                fadeStart ? fade : 0,
                fadeEnd ? 1 - fade : 1,
                1,
              ],
            ).createShader(bounds),
            child: strip,
          );
        },
      ),
    );
  }
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// One key cap. Owns the auto-repeat timer for held arrow keys — a TUI is
/// unusable if moving five lines up needs five taps.
class _ToolbarKeyCap extends StatefulWidget {
  const _ToolbarKeyCap({
    super.key,
    required this.toolbarKey,
    required this.active,
    required this.onPress,
  });

  final ToolbarKey toolbarKey;
  final bool active;
  final VoidCallback onPress;

  @override
  State<_ToolbarKeyCap> createState() => _ToolbarKeyCapState();
}

class _ToolbarKeyCapState extends State<_ToolbarKeyCap> {
  static const _repeatInterval = Duration(milliseconds: 80);

  Timer? _repeat;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _startRepeat() {
    widget.onPress();
    _repeat = Timer.periodic(_repeatInterval, (_) => widget.onPress());
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final repeatable = widget.toolbarKey.repeatable;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPress,
      onLongPressStart: repeatable ? (_) => _startRepeat() : null,
      onLongPressEnd: repeatable ? (_) => _stopRepeat() : null,
      onLongPressCancel: repeatable ? _stopRepeat : null,
      // Prototype `.keycap` scaled down with the bar: min-width 34, height 34
      // (44-bar minus 5+5 margin), padding 0 10, radius 8, 1px border, mono 14.
      child: Container(
        constraints: const BoxConstraints(minWidth: 34),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.active ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.active ? cs.primary : cs.outlineVariant,
          ),
        ),
        child: Text(
          widget.toolbarKey.label,
          style: appMonoTextStyle(
            context,
            fontSize: 14,
            color: widget.active ? cs.onPrimary : cs.onSurface,
          ).copyWith(height: 1),
        ),
      ),
    );
  }
}
