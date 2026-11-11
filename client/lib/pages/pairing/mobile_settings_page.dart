import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/voice_input_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../repositories/pairing_settings_repository.dart';
import '../../services/pairing/host_settings_client.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/settings/appearance_controls.dart';
import 'debug_log_page.dart';
import 'host_pane_defaults_page.dart';
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
///
/// With [embedded] the page renders as the settings *tab* inside the home shell
/// instead: no back affordance (the bottom bar owns switching) and no SafeArea,
/// because the home Scaffold already applied it.
class MobileSettingsPage extends StatelessWidget {
  const MobileSettingsPage({
    super.key,
    this.embedded = false,
    this.desktops = const [],
    this.hostSettings = const HostSettingsClient(),
  });

  final bool embedded;

  /// Desktops this phone has paired with. Their *own* settings (what a new
  /// window is) live on the desktop, so editing them means dialing it — which
  /// this page offers per host rather than reading local preferences that the
  /// desktop would never see.
  final List<PairedDesktop> desktops;

  /// Injectable so a widget test can answer without a live host.
  final HostSettingsClient hostSettings;

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

    final content = Column(
      children: [
        PairingNavBar.large(
          title: l10n.settings,
          onBack: embedded ? null : () => Navigator.of(context).maybePop(),
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
                    Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                    ListTile(
                      key: AppKeys.mobileSettingsVoiceRow,
                      // Explicit sizes: the app's icon scale is damped, so
                      // theme-sized glyphs render too small here.
                      leading: const Icon(Icons.mic_none, size: 22),
                      title: Text(l10n.voiceInputSettings),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => Navigator.of(context).push(
                        VoiceSettingsPage.route(
                          context.read<VoiceInputCubit>(),
                        ),
                      ),
                    ),
                    Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                    ListTile(
                      key: AppKeys.mobileSettingsDebugLogRow,
                      leading: const Icon(Icons.bug_report_outlined, size: 22),
                      title: Text(l10n.debugLogTitle),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () =>
                          Navigator.of(context).push(DebugLogPage.route()),
                    ),
                  ],
                ),
              ),
              if (desktops.isNotEmpty) ...[
                SizedBox(height: spacing.md),
                _HostSettingsCard(desktops: desktops, client: hostSettings),
              ],
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      key: AppKeys.mobileSettingsPage,
      backgroundColor: embedded ? Colors.transparent : null,
      body: embedded ? content : SafeArea(child: content),
    );
  }
}

/// The desktop-side settings a phone can reach: what that host makes of a new
/// window, and the command a conversation window runs there.
///
/// One row per paired desktop because the values are per machine — two desktops
/// can differ, and the row names the one being edited.
class _HostSettingsCard extends StatelessWidget {
  const _HostSettingsCard({required this.desktops, required this.client});

  final List<PairedDesktop> desktops;
  final HostSettingsClient client;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return TpCard.outlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              l10n.hostSettingsSectionTitle,
              style: TpTextStyles.of(context).smColored(cs.onSurfaceVariant),
            ),
          ),
          for (final (index, desktop) in desktops.indexed) ...[
            if (index > 0)
              Divider(height: 1, thickness: 1, color: cs.outlineVariant),
            ListTile(
              key: AppKeys.mobileSettingsHostRow(desktop.id),
              leading: const Icon(Icons.desktop_windows_outlined, size: 22),
              title: Text(desktop.name),
              subtitle: Text(
                l10n.hostSettingsRowSubtitle(desktop.displayUrl),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.of(
                context,
              ).push(HostPaneDefaultsPage.route(desktop, client: client)),
            ),
          ],
        ],
      ),
    );
  }
}
