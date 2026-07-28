import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/terminal/terminal_theme_mapper.dart';
import '../../../theme/terminal/cmux_terminal_theme.dart';
import '../../../theme/terminal/terminal_theme_catalog.g.dart';
import '../../../theme/workspace_surface_layers.dart';

/// One selectable option in the terminal scheme picker.
class _SchemeOption {
  const _SchemeOption({
    required this.id,
    required this.name,
    required this.author,
    required this.swatches,
  });

  final String id;
  final String name;
  final String author;
  final List<Color> swatches;
}

/// Grouped picker for the 23 built-in terminal palettes plus the legacy
/// adaptive/classicDark/highContrast modes. Selecting a row writes the id back
/// via [onSelect] (`terminalThemeMode`).
class TerminalSchemePicker extends StatelessWidget {
  const TerminalSchemePicker({
    required this.selectedMode,
    required this.onSelect,
    super.key,
  });

  final String selectedMode;
  final ValueChanged<String> onSelect;

  static List<Color> _catalogSwatches(CmuxTerminalTheme t) => <Color>[
    t.background,
    t.foreground,
    t.accent ?? t.cursor,
    t.ansi[1],
    t.ansi[2],
    t.ansi[4],
  ];

  List<Color> _legacySwatches(ColorScheme cs, bool isDark, String mode) {
    final theme = teampilotTerminalTheme(
      cs,
      isDark: isDark,
      mode: mode,
      chrome: WorkspacePageChrome.workspace,
    );
    Color op(int v) => Color(0xFF000000 | v);
    return <Color>[
      op(theme.background),
      op(theme.foreground),
      op(theme.hintStart.bg),
      op(theme.ansi[1]),
      op(theme.ansi[2]),
      op(theme.ansi[4]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final dark = <_SchemeOption>[];
    final light = <_SchemeOption>[];
    for (final theme in kCmuxTerminalThemes) {
      final option = _SchemeOption(
        id: theme.id,
        name: theme.name,
        author: theme.author,
        swatches: _catalogSwatches(theme),
      );
      (theme.isDark ? dark : light).add(option);
    }

    final legacy = <_SchemeOption>[
      _SchemeOption(
        id: 'adaptive',
        name: l10n.workspaceTerminalThemeAdaptive,
        author: '',
        swatches: _legacySwatches(cs, isDark, 'adaptive'),
      ),
      _SchemeOption(
        id: 'classicDark',
        name: l10n.workspaceTerminalThemeClassicDark,
        author: '',
        swatches: _legacySwatches(cs, isDark, 'classicDark'),
      ),
      _SchemeOption(
        id: 'highContrast',
        name: l10n.workspaceTerminalThemeHighContrast,
        author: '',
        swatches: _legacySwatches(cs, isDark, 'highContrast'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _group(context, l10n.terminalColorSchemeGroupLegacy, legacy),
        _group(context, l10n.terminalColorSchemeGroupDark, dark),
        _group(context, l10n.terminalColorSchemeGroupLight, light),
      ],
    );
  }

  Widget _group(
    BuildContext context,
    String title,
    List<_SchemeOption> options,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpSectionHeader(title: title),
        for (final option in options)
          _SchemeRow(
            option: option,
            selected: option.id == selectedMode,
            onTap: () => onSelect(option.id),
          ),
      ],
    );
  }
}

class _SchemeRow extends StatelessWidget {
  const _SchemeRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _SchemeOption option;
  final bool selected;
  final VoidCallback onTap;

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
          for (final color in colors)
            Container(width: 16, height: 20, color: color),
        ],
      ),
    );
  }
}
