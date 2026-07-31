import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/settings/appearance_controls.dart';

/// Post-onboarding appearance settings for the mobile pairing client.
///
/// The phone build has no full settings route — theme mode / colour / language
/// are otherwise only reachable during first-launch onboarding. This sheet, off
/// the paired-hosts header, reuses the same [AppearanceControls] so they stay
/// editable afterwards.
Future<void> showMobileSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _MobileSettingsSheet(),
  );
}

class _MobileSettingsSheet extends StatelessWidget {
  const _MobileSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;

    return SafeArea(
      key: AppKeys.mobileSettingsSheet,
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.lg,
          spacing.lg,
          spacing.lg,
          spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.settings, style: styles.lgSemibold),
                ),
                TpIconButton(
                  key: AppKeys.mobileSettingsCloseButton,
                  icon: Icons.close,
                  tooltip: l10n.close,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: TpCard.outlined(child: const AppearanceControls()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
