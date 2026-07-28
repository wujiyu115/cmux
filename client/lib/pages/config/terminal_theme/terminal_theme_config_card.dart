import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/layout_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../repositories/user_terminal_theme_repository.dart';
import '../../../services/terminal/terminal_theme_mapper.dart';
import '../../../theme/terminal/cmux_terminal_theme.dart';
import '../../../theme/terminal/terminal_color_slots.dart';
import '../../../theme/terminal/user_terminal_theme_registry.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../../../widgets/app_toast/app_toast.dart';
import 'terminal_color_slot_editor.dart';
import 'terminal_scheme_picker.dart';
import 'terminal_theme_import_dialog.dart';
import 'terminal_theme_preview.dart';

/// Terminal colour-scheme settings section: scheme picker (23 catalog themes +
/// imported themes + legacy modes), theme import / delete, a live preview of the
/// effective theme, a custom-colours toggle, and the per-slot override editor.
/// Mounted as a card in the Layout settings scroll (`/config/layout`).
class TerminalThemeConfigCard extends StatefulWidget {
  const TerminalThemeConfigCard({this.repository, super.key});

  /// Injected in tests; defaults to the on-disk `{appDataRoot}/themes` store.
  final UserTerminalThemeRepository? repository;

  @override
  State<TerminalThemeConfigCard> createState() =>
      _TerminalThemeConfigCardState();
}

class _TerminalThemeConfigCardState extends State<TerminalThemeConfigCard> {
  late final UserTerminalThemeRepository _repository =
      widget.repository ?? UserTerminalThemeRepository();

  /// Mirrors [UserTerminalThemeRegistry.instance]; seeded from the cache the
  /// bootstrap already populated, so the card never blocks on IO to first paint.
  List<CmuxTerminalTheme> _imported = UserTerminalThemeRegistry.instance.themes;

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
              trailing: TpButton(
                key: const Key('terminal-theme-import-action'),
                variant: TpButtonVariant.secondary,
                onPressed: () => _import(controller),
                child: Text(l10n.terminalThemeImportAction),
              ),
              showDividerBelow: true,
            ),
            TerminalSchemePicker(
              selectedMode: mode,
              onSelect: controller.setTerminalThemeMode,
              importedThemes: _imported,
              onDeleteImported: (theme) => _delete(controller, theme),
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

  /// Import flow: parse in the dialog, persist, refresh the synchronous registry
  /// the theme mapper reads, then select the new theme so the effect is visible
  /// immediately.
  Future<void> _import(LayoutCubit controller) async {
    final result = await showTerminalThemeImportDialog(context);
    final theme = result?.theme;
    if (theme == null || !mounted) return;
    final l10n = context.l10n;

    final CmuxTerminalTheme saved;
    try {
      saved = await _repository.save(theme);
    } on Object {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.terminalThemeImportSaveFailed,
        variant: TpToastVariant.error,
      );
      return;
    }

    await _refreshRegistry();
    if (!mounted) return;
    controller.setTerminalThemeMode(saved.id);

    final warnings = result!.warnings;
    final derived = warnings.map(l10n.terminalColorSlotLabel).join(', ');
    final message = warnings.isEmpty
        ? l10n.terminalThemeImportSuccess(saved.name)
        : '${l10n.terminalThemeImportSuccess(saved.name)}\n'
              '${l10n.terminalThemeImportDerived(derived)}';
    AppToast.show(context, message: message);
  }

  Future<void> _delete(LayoutCubit controller, CmuxTerminalTheme theme) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => TpDialog(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(
              title: l10n.terminalThemeDeleteConfirmTitle,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.terminalThemeDeleteConfirmMessage(theme.name)),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  key: const Key('terminal-theme-delete-confirm'),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _repository.delete(theme.id);
    } on Object {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.terminalThemeDeleteFailed,
        variant: TpToastVariant.error,
      );
      return;
    }
    await _refreshRegistry();
    if (!mounted) return;
    // Never leave the preference pointing at a theme that no longer exists.
    // Read the mode now rather than capturing it at build time, so a selection
    // made while the confirm dialog was open still counts.
    if (controller.state.preferences.terminalThemeMode == theme.id) {
      controller.setTerminalThemeMode('adaptive');
    }
  }

  Future<void> _refreshRegistry() async {
    final themes = await _repository.loadAll();
    UserTerminalThemeRegistry.instance.replaceAll(themes);
    if (!mounted) return;
    setState(() => _imported = themes);
  }
}
