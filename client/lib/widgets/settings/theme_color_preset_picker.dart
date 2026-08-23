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

class ThemeColorPresetPicker extends StatefulWidget {
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
  State<ThemeColorPresetPicker> createState() => _ThemeColorPresetPickerState();
}

class _ThemeColorPresetPickerState extends State<ThemeColorPresetPicker> {
  /// Width of the fade applied to whichever edge still hides chips.
  static const double _fadeWidth = 20;

  bool _fadeLeading = false;
  bool _fadeTrailing = false;
  bool _syncScheduled = false;

  /// `reverse: true` anchors offset 0 at the right edge, so the pixels still
  /// hidden past the left edge are whatever is left of [maxScrollExtent], and
  /// the ones hidden past the right edge are [pixels] itself.
  void _syncFades(ScrollMetrics metrics) {
    final leading = metrics.maxScrollExtent - metrics.pixels > 0.5;
    final trailing = metrics.pixels > 0.5;
    if (leading == _fadeLeading && trailing == _fadeTrailing) return;
    // Metrics notifications are dispatched from the viewport's layout pass, so
    // defer the rebuild instead of calling setState() mid-layout.
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      setState(() {
        _fadeLeading = leading;
        _fadeTrailing = trailing;
      });
    });
  }

  Shader _fadeShader(Rect bounds) {
    const opaque = Color(0xFF000000);
    const clear = Color(0x00000000);
    final inset = (_fadeWidth / bounds.width).clamp(0.0, 0.5);
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        _fadeLeading ? clear : opaque,
        opaque,
        opaque,
        _fadeTrailing ? clear : opaque,
      ],
      stops: [0, inset, 1 - inset, 1],
    ).createShader(bounds);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget scroller = SingleChildScrollView(
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
                  selected: id == widget.selected,
                  onTap: () => widget.onSelect(id),
                  terminalTheme: widget.terminalTheme,
                ),
              ),
            ),
        ],
      ),
    );
    // Skip the saveLayer entirely while every chip fits on screen.
    if (_fadeLeading || _fadeTrailing) {
      scroller = ShaderMask(
        shaderCallback: _fadeShader,
        blendMode: BlendMode.dstIn,
        child: scroller,
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          _syncFades(notification.metrics);
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _syncFades(notification.metrics);
            return false;
          },
          child: scroller,
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
