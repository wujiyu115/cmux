import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_theme.dart';
import '../../theme/terminal/cmux_terminal_theme.dart';
import '../../theme/terminal_derived_scheme.dart';
import '../../theme/workspace_surface_layers.dart';

/// [ThemeColorPresetPicker] wired to the live terminal colour-scheme prefs, so
/// the `terminal` chip previews the colours the UI would actually take on.
class ConnectedThemeColorPresetPicker extends StatelessWidget {
  const ConnectedThemeColorPresetPicker({
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<LayoutCubit, LayoutState, (String, bool)>(
      selector: (state) => (
        state.preferences.terminalThemeMode,
        state.preferences.useCustomTerminalColors,
      ),
      builder: (context, data) {
        final (mode, useCustomColors) = data;
        return ThemeColorPresetPicker(
          selected: selected,
          onSelect: onSelect,
          terminalTheme: resolveUiTerminalTheme(
            mode: mode,
            useCustomColors: useCustomColors,
            colorOverrides: context
                .read<LayoutCubit>()
                .state
                .preferences
                .terminalColorOverrides,
          ),
        );
      },
    );
  }
}

class ThemeColorPresetPicker extends StatelessWidget {
  const ThemeColorPresetPicker({
    required this.selected,
    required this.onSelect,
    this.terminalTheme,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelect;

  /// Active terminal theme; supplies the swatches for the `terminal` preset.
  /// When null (legacy terminal modes) that chip shows the default palette.
  final CmuxTerminalTheme? terminalTheme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Align(
      alignment: Alignment.centerRight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final id in kThemeColorPresetIds)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: RepaintBoundary(
                  child: ThemeColorPresetChip(
                    id: id,
                    label: l10n.themeColorPresetName(id),
                    selected: id == selected,
                    onTap: () => onSelect(id),
                    terminalTheme: terminalTheme,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ThemeColorPresetChip extends StatefulWidget {
  const ThemeColorPresetChip({
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
    this.terminalTheme,
    super.key,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final CmuxTerminalTheme? terminalTheme;

  @override
  State<ThemeColorPresetChip> createState() => _ThemeColorPresetChipState();
}

class _ThemeColorPresetChipState extends State<ThemeColorPresetChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = themePresetSwatchPrimary(widget.id, widget.terminalTheme);
    final secondary = themePresetSwatchSecondary(
      widget.id,
      widget.terminalTheme,
    );
    final borderColor = widget.selected
        ? cs.primary
        : _hovered
        ? cs.primary.withValues(alpha: 0.55)
        : cs.outlineVariant;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: cs.workspaceInset,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: borderColor,
              width: widget.selected ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: secondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(widget.label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
