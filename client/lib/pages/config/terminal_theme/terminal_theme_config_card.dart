import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/layout_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../services/terminal/terminal_theme_mapper.dart';
import '../../../theme/terminal/terminal_color_slots.dart';
import '../../../theme/workspace_surface_layers.dart';
import 'terminal_color_slot_editor.dart';
import 'terminal_scheme_picker.dart';
import 'terminal_theme_preview.dart';

/// Terminal colour-scheme settings section: scheme picker (23 catalog themes +
/// legacy modes), a live preview of the effective theme, a custom-colours
/// toggle, and the per-slot override editor. Mounted as a card in the Layout
/// settings scroll (`/config/layout`).
class TerminalThemeConfigCard extends StatelessWidget {
  const TerminalThemeConfigCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocSelector<
      LayoutCubit,
      LayoutState,
      (String, bool, Map<String, int>)
    >(
      selector: (state) => (
        state.preferences.terminalThemeMode,
        state.preferences.useCustomTerminalColors,
        state.preferences.terminalColorOverrides,
      ),
      builder: (context, data) {
        final (mode, useCustomColors, overrides) = data;

        // Effective theme (scheme + overrides) drives the preview; the base
        // theme (no overrides) seeds the per-slot swatches / fields.
        final effective = teampilotTerminalTheme(
          cs,
          isDark: isDark,
          mode: mode,
          chrome: WorkspacePageChrome.workspace,
          useCustomColors: useCustomColors,
          colorOverrides: overrides,
        );
        final base = teampilotTerminalTheme(
          cs,
          isDark: isDark,
          mode: mode,
          chrome: WorkspacePageChrome.workspace,
        );
        final baseSlotValues = terminalThemeSlotValues(base);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpPreferenceRow(
              title: l10n.terminalColorSchemeTitle,
              subtitle: l10n.terminalColorSchemeDescription,
              trailing: const SizedBox.shrink(),
              showDividerBelow: true,
            ),
            TerminalSchemePicker(
              selectedMode: mode,
              onSelect: controller.setTerminalThemeMode,
            ),
            const TpSeparator(),
            TerminalThemePreview(theme: effective),
            const TpSeparator(),
            TpPreferenceRow(
              title: l10n.terminalUseCustomColorsTitle,
              subtitle: l10n.terminalUseCustomColorsDescription,
              trailing: Switch(
                value: useCustomColors,
                onChanged: controller.setUseCustomTerminalColors,
              ),
              showDividerBelow: true,
            ),
            TerminalColorSlotEditor(
              enabled: useCustomColors,
              baseSlotValues: baseSlotValues,
              overrides: overrides,
              onSetOverride: controller.setTerminalColorOverride,
              onClearOverride: controller.clearTerminalColorOverride,
              onResetAll: controller.clearTerminalColorOverrides,
            ),
          ],
        );
      },
    );
  }
}
