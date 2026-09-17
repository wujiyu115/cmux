import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../theme/terminal/user_terminal_theme_registry.dart';
import '../../utils/ui/app_keys.dart';
import 'color_theme_picker.dart';

/// The theme-mode / colour-theme / language trio, wired to [LayoutCubit].
///
/// Shared between first-launch onboarding ([OnboardingAppearanceStep]) and the
/// mobile settings sheet — the two places a phone user can reach appearance
/// prefs. Renders three [TpPreferenceRow]s; the caller supplies the card.
class AppearanceControls extends StatelessWidget {
  const AppearanceControls({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<
      LayoutCubit,
      LayoutState,
      (String, String, String, String)
    >(
      selector: (state) {
        var themeMode = state.preferences.themeMode;
        if (themeMode != 'light' &&
            themeMode != 'dark' &&
            themeMode != 'system') {
          themeMode = 'system';
        }
        return (
          themeMode,
          state.preferences.lightThemeId,
          state.preferences.darkThemeId,
          languagePreferenceUiValue(state.preferences.locale),
        );
      },
      builder: (context, appearance) {
        final (themeMode, lightThemeId, darkThemeId, langValue) = appearance;
        final platformDark = MediaQuery.platformBrightnessOf(context) ==
            Brightness.dark;
        final activeThemeId = switch (themeMode) {
          'light' => lightThemeId,
          'dark' => darkThemeId,
          _ => platformDark ? darkThemeId : lightThemeId,
        };
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
              title: l10n.colorThemeDialogTitle,
              subtitle: l10n.lightThemeDescription,
              trailing: TpButton(
                variant: TpButtonVariant.secondary,
                onPressed: () async {
                  final selected = await ColorThemePicker.show(
                    context,
                    selectedId: activeThemeId,
                    importedThemes:
                        UserTerminalThemeRegistry.instance.themes,
                  );
                  if (selected == null) return;
                  await controller.setActiveColorTheme(
                    selected,
                    platformDark: platformDark,
                  );
                },
                child: Text(l10n.colorThemeName(activeThemeId)),
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
