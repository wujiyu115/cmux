import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/settings/appearance_controls.dart';
import 'onboarding_step_scaffold.dart';

class OnboardingAppearanceStep extends StatelessWidget {
  const OnboardingAppearanceStep({super.key, this.isActive = true});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return OnboardingStepScaffold(
      title: l10n.onboardingAppearanceTitle,
      subtitle: l10n.onboardingAppearanceSubtitle,
      body: TpCard.outlined(child: const AppearanceControls()),
    );
  }
}
