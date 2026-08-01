import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/mobile_toolbar_cubit.dart';
import 'mobile_composer_panel.dart';
import 'mobile_keyboard_toolbar.dart';

/// The mirror page's bottom slot: either the shortcut-key bar or the composer,
/// chosen by [MobileToolbarState.mode].
///
/// A widget of its own so the mode switch can be mounted in a widget test: the
/// mirror page is untestable in isolation, needing a live `PairingClientCubit`,
/// `SharedPreferences` and a terminal engine, while this needs nothing but a
/// [MobileToolbarCubit].
class MobileBottomSlot extends StatelessWidget {
  const MobileBottomSlot({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  /// Owned by the caller (the mirror page): the slot never creates or disposes
  /// these — it only forwards them to the composer.
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MobileToolbarCubit, MobileToolbarState>(
      // The state re-emits on every key tap and has no value equality, so this
      // guard keeps a keypress from rebuilding the whole panel. It is a
      // rebuild-count and on-device IME optimization — not what preserves a
      // half-typed draft, which the caller-owned controller does.
      buildWhen: (before, after) => before.mode != after.mode,
      builder: (context, state) => switch (state.mode) {
        MobileInputMode.keys => const MobileKeyboardToolbar(),
        MobileInputMode.composer => MobileComposerPanel(
          controller: controller,
          focusNode: focusNode,
        ),
      },
    );
  }
}
