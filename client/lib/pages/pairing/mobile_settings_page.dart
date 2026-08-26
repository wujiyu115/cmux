import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/voice_input_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/settings/appearance_controls.dart';
import 'debug_log_page.dart';
import 'pairing_nav_bar.dart';
import 'voice/voice_settings_page.dart';

/// Post-onboarding appearance settings for the mobile pairing client.
///
/// The phone build has no full desktop settings route — theme mode / colour /
/// language are otherwise only reachable during first-launch onboarding. This
/// page, off the paired-hosts header, reuses the same [AppearanceControls] so
/// they stay editable afterwards, and carries the voice-input entry point.
///
/// A full route (not a bottom sheet) so the controls get the whole screen and
/// the standard back navigation. [voiceCubit] is re-provided across the route
/// boundary because the route mounts in the root navigator — above the pairing
/// shell's [BlocProvider] — so the page's own context cannot read it. Callers
/// on the paired-hosts screen (under the shell) pass
/// `context.read<VoiceInputCubit>()`.
class MobileSettingsPage extends StatelessWidget {
  const MobileSettingsPage({super.key});

  /// Route helper so callers cannot forget to re-provide the cubit across the
  /// route boundary.
  static Route<void> route(VoiceInputCubit voiceCubit) => MaterialPageRoute(
    builder: (_) => BlocProvider<VoiceInputCubit>.value(
      value: voiceCubit,
      child: const MobileSettingsPage(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;

    return Scaffold(
      key: AppKeys.mobileSettingsPage,
      body: SafeArea(
        child: Column(
          children: [
            PairingNavBar.large(
              title: l10n.settings,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(spacing.lg),
                children: [
                  // One card grouping appearance rows + the voice entry, matching
                  // the prototype's single settings card.
                  TpCard.outlined(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AppearanceControls(),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: cs.outlineVariant,
                        ),
                        ListTile(
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
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: cs.outlineVariant,
                        ),
                        ListTile(
                          key: AppKeys.mobileSettingsDebugLogRow,
                          leading: const Icon(Icons.bug_report_outlined),
                          title: Text(l10n.debugLogTitle),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              Navigator.of(context).push(DebugLogPage.route()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
