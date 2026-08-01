import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/mobile_toolbar_cubit.dart';
import 'mobile_composer_panel.dart';
import 'mobile_keyboard_toolbar.dart';

/// The mirror page's bottom slot: either the shortcut-key bar or the composer,
/// chosen by [MobileToolbarState.mode].
///
/// A widget of its own so the mode switch — and, crucially, its `buildWhen`
/// rebuild guard — can be mounted directly in a widget test. The mirror page
/// itself is untestable in isolation (it needs a live [PairingClientCubit],
/// `SharedPreferences`, and a terminal engine); pulling the switch out here lets
/// the guard be exercised against a real [MobileToolbarCubit] alone.
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
      // The state re-emits on every key tap; only the mode decides
      // which panel is mounted.
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
