import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/voice_input_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/settings/appearance_controls.dart';
import 'voice/voice_settings_page.dart';

/// Post-onboarding appearance settings for the mobile pairing client.
///
/// The phone build has no full settings route — theme mode / colour / language
/// are otherwise only reachable during first-launch onboarding. This sheet, off
/// the paired-hosts header, reuses the same [AppearanceControls] so they stay
/// editable afterwards, and carries the voice-input entry point.
///
/// [voiceCubit] is re-provided into the sheet because a modal route mounts in
/// the root navigator — above the pairing shell's [BlocProvider] — so the
/// sheet's own context cannot read it. Callers on the paired-hosts screen
/// (under the shell) pass `context.read<VoiceInputCubit>()`.
Future<void> showMobileSettingsSheet(
  BuildContext context, {
  required VoiceInputCubit voiceCubit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BlocProvider<VoiceInputCubit>.value(
      value: voiceCubit,
      child: const _MobileSettingsSheet(),
    ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TpCard.outlined(child: const AppearanceControls()),
                    SizedBox(height: spacing.md),
                    TpCard.outlined(
                      child: ListTile(
                        key: AppKeys.mobileSettingsVoiceRow,
                        leading: const Icon(Icons.mic_none),
                        title: Text(l10n.voiceInputSettings),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          VoiceSettingsPage.route(
                            context.read<VoiceInputCubit>(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
