import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../theme/app_theme.dart';
import '../../utils/ui/app_keys.dart';
import 'theme_color_preset_picker.dart';

/// The theme-mode / theme-colour / language trio, wired to [LayoutCubit].
///
/// Shared between first-launch onboarding ([OnboardingAppearanceStep]) and the
/// mobile settings sheet — the two places a phone user can reach appearance
/// prefs. Renders the three [TpPreferenceRow]s; the caller supplies the card.
class AppearanceControls extends StatelessWidget {
  const AppearanceControls({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<LayoutCubit, LayoutState, (String, String, String)>(
      selector: (state) {
        var themeMode = state.preferences.themeMode;
        if (themeMode != 'light' &&
            themeMode != 'dark' &&
            themeMode != 'system') {
          themeMode = 'system';
        }
        return (
          themeMode,
          normalizeThemeColorPreset(state.preferences.themeColorPreset),
          languagePreferenceUiValue(state.preferences.locale),
        );
      },
      builder: (context, appearance) {
        final (themeMode, colorPreset, langValue) = appearance;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpPreferenceRow(
              title: l10n.themeModeTitle,
              subtitle: l10n.themeModeDescription,
              trailing: TpSegmentedPicker<String>(
                segments: [
                  TpSegmentedOption<String>(
                    value: 'light',
                    label: l10n.themeLight,
                    icon: Icons.light_mode_outlined,
                  ),
                  TpSegmentedOption<String>(
                    value: 'dark',
                    label: l10n.themeDark,
                    icon: Icons.dark_mode_outlined,
                  ),
                  TpSegmentedOption<String>(
                    value: 'system',
                    label: l10n.themeSystem,
                    icon: Icons.desktop_windows_outlined,
                  ),
                ],
                selected: themeMode,
                onChanged: controller.setThemeMode,
              ),
              showDividerBelow: true,
            ),
            TpPreferenceRow(
              title: l10n.themeColorPresetTitle,
              subtitle: l10n.themeColorPresetDescription,
              trailing: ConnectedThemeColorPresetPicker(
                selected: colorPreset,
                onSelect: controller.setThemeColorPreset,
              ),
              showDividerBelow: true,
            ),
            TpPreferenceRow(
              title: l10n.language,
              subtitle: l10n.languageDescription,
              trailing: TpCompactSelect<String>(
                value: langValue,
                entries: [
                  ('system', l10n.languageSystem),
                  ('en', l10n.languageEnglish),
                  ('zh', l10n.languageChinese),
                ],
                itemKeys: const {
                  'system': AppKeys.languageSystemButton,
                  'en': AppKeys.languageEnButton,
                  'zh': AppKeys.languageZhButton,
                },
                onChanged: (v) {
                  if (v != null) {
                    controller.setLocale(languagePreferenceStoredLocale(v));
                  }
                },
              ),
              showDividerBelow: false,
            ),
          ],
        );
      },
    );
  }
}
