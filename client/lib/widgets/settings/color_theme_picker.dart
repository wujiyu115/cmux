import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_theme.dart';
import '../../theme/color_theme.dart';
import '../../theme/terminal_derived_scheme.dart';
import '../../theme/terminal/cmux_terminal_theme.dart';
import '../../theme/terminal/terminal_theme_catalog.g.dart';

/// The unified colour-theme picker — the single place a theme is chosen, in
/// the VS Code `workbench.colorTheme` sense: one id decides the UI chrome, the
/// terminal palette, and the file-browser surface together.
///
/// Groups: interface palettes (light / dark), terminal themes (dark / light),
/// and user-imported themes. Selecting a row returns its theme id; the caller
/// writes it to the light or dark slot depending on which row was tapped.
///
/// [onDeleteImported] enables the delete affordance on imported rows (and must
/// also refresh the registry behind [importedThemes]).
class ColorThemePicker extends StatelessWidget {
  const ColorThemePicker({
    required this.selectedId,
    required this.onSelect,
    required this.brightness,
    this.importedThemes = const [],
    this.onDeleteImported,
    super.key,
  });

  final String selectedId;
  final ValueChanged<String> onSelect;

  /// The brightness slot being edited. Only themes of this brightness are
  /// offered — a light slot must not be able to hold a dark theme (and vice
  /// versa), since each slot's theme renders at its own brightness.
  final Brightness brightness;
  final List<CmuxTerminalTheme> importedThemes;
  final ValueChanged<CmuxTerminalTheme>? onDeleteImported;

  static List<Color> _catalogSwatches(CmuxTerminalTheme t) => <Color>[
    t.background,
    t.foreground,
    t.accent ?? t.cursor,
    t.ansi[1],
    t.ansi[2],
    t.ansi[4],
  ];

  /// Opens the picker as a dialog for the given brightness [slot] and returns
  /// the chosen id, or null on cancel.
  static Future<String?> show(
    BuildContext context, {
    required String selectedId,
    required Brightness brightness,
    List<CmuxTerminalTheme> importedThemes = const [],
    ValueChanged<CmuxTerminalTheme>? onDeleteImported,
  }) {
    return showTpDialog<String>(
      context: context,
      builder: (dialogContext) {
        return TpDialog(
          maxWidth: 560,
          maxHeight: 640,
          scrollable: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpDialogHeader(title: dialogContext.l10n.colorThemeDialogTitle),
              ColorThemePicker(
                selectedId: selectedId,
                brightness: brightness,
                importedThemes: importedThemes,
                onDeleteImported: onDeleteImported,
                onSelect: (id) => Navigator.of(dialogContext).pop(id),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final isLight = brightness == Brightness.light;

    // One merged group per brightness: interface palettes, catalog themes, and
    // imported themes all drive UI + terminal + file browser together, so they
    // are presented as a single list of "themes", split only by brightness.
    final options = <_ThemeOption>[
      for (final preset in kThemeColorPresetIds)
        if (preset != kTerminalDerivedPresetId)
          _ThemeOption(
            id: uiColorThemeId(preset, brightness),
            name: l10n.themeColorPresetName(preset),
            swatches: [
              themePresetSwatchPrimary(preset),
              themePresetSwatchSecondary(preset),
            ],
          ),
      for (final theme in kCmuxTerminalThemes)
        if (theme.isDark != isLight)
          _ThemeOption(
            id: theme.id,
            name: theme.name,
            author: theme.author,
            swatches: _catalogSwatches(theme),
          ),
      for (final theme in importedThemes)
        if (theme.isLightByLuminance == isLight)
          _ThemeOption(
            id: theme.id,
            name: theme.name,
            author: theme.author,
            swatches: _catalogSwatches(theme),
            imported: true,
          ),
    ];

    return _group(
      context,
      isLight ? l10n.colorThemeGroupLight : l10n.colorThemeGroupDark,
      options,
      onDelete: onDeleteImported == null
          ? null
          : (id) {
              final theme = importedThemes.firstWhere((t) => t.id == id);
              onDeleteImported!(theme);
            },
    );
  }

  Widget _group(
    BuildContext context,
    String title,
    List<_ThemeOption> options, {
    ValueChanged<String>? onDelete,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpSectionHeader(title: title),
        for (final option in options)
          _ThemeRow(
            option: option,
            selected: option.id == selectedId,
            onTap: () => onSelect(option.id),
            onDelete: option.imported && onDelete != null
                ? () => onDelete(option.id)
                : null,
          ),
      ],
    );
  }
}

class _ThemeOption {
  const _ThemeOption({
    required this.id,
    required this.name,
    required this.swatches,
    this.author = '',
    this.imported = false,
  });

  final String id;
  final String name;
  final String author;
  final List<Color> swatches;

  /// True for user-imported themes, which are the only deletable rows.
  final bool imported;
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({
    required this.option,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  final _ThemeOption option;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(option.name),
                  if (option.author.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      l10n.terminalColorSchemeByAuthor(option.author),
                      style: styles.mutedSm,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _SwatchStrip(colors: option.swatches),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              TpIconButton(
                icon: Icons.delete_outline,
                compact: true,
                size: TpIconButton.kCompactSize,
                tooltip: l10n.terminalThemeDeleteTooltip,
                onTap: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwatchStrip extends StatelessWidget {
  const _SwatchStrip({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final color in colors) Container(width: 16, height: 20, color: color),
        ],
      ),
    );
  }
}
