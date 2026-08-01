import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/mobile_toolbar_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/toolbar_key.dart';
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

  static const double barHeight = 44;

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
                  builder: (context, state) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(children: _caps(context, state)),
                  ),
                ),
              ),
              TpIconButton(
                key: AppKeys.mobileToolbarComposerButton,
                icon: Icons.chat_bubble_outline,
                tooltip: context.l10n.mobileComposerOpen,
                size: barHeight,
                onTap: context.read<MobileToolbarCubit>().toggleComposer,
              ),
              TpIconButton(
                key: AppKeys.mobileToolbarCustomizeButton,
                icon: Icons.tune,
                tooltip: context.l10n.mobileToolbarCustomize,
                size: barHeight,
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

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 24,
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
      child: Container(
        constraints: const BoxConstraints(minWidth: 40),
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.active ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          widget.toolbarKey.label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1,
            color: widget.active ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
  }
}
