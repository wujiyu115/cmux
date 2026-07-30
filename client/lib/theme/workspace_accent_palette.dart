import 'package:flutter/material.dart';

import '../models/workspace_accent.dart';

/// Theme-adaptive accent swatches for workspaces and groups. A
/// [WorkspaceAccentPreset.index] indexes into this palette (wrapping on
/// overflow); `null` accents fall back to the theme primary.
const List<Color> _lightSwatches = [
  Color(0xFF3B82F6), // blue
  Color(0xFF8B5CF6), // violet
  Color(0xFFEC4899), // pink
  Color(0xFFEF4444), // red
  Color(0xFFF59E0B), // amber
  Color(0xFF10B981), // emerald
  Color(0xFF06B6D4), // cyan
  Color(0xFF64748B), // slate
];

const List<Color> _darkSwatches = [
  Color(0xFF60A5FA),
  Color(0xFFA78BFA),
  Color(0xFFF472B6),
  Color(0xFFF87171),
  Color(0xFFFBBF24),
  Color(0xFF34D399),
  Color(0xFF22D3EE),
  Color(0xFF94A3B8),
];

/// Number of selectable accent presets (light/dark share the same count).
int get workspaceAccentPresetCount => _lightSwatches.length;

/// Resolves the display color for [accent] under the current theme brightness.
/// Returns [fallback] (or the theme primary) when [accent] is `null`.
Color workspaceAccentColor(
  BuildContext context,
  WorkspaceAccentPreset? accent, {
  Color? fallback,
}) {
  if (accent == null) {
    return fallback ?? Theme.of(context).colorScheme.primary;
  }
  return workspaceAccentColorForIndex(context, accent.index);
}

/// Resolves the swatch for a raw preset [index] under the current brightness.
Color workspaceAccentColorForIndex(BuildContext context, int index) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final swatches = dark ? _darkSwatches : _lightSwatches;
  return swatches[index.abs() % swatches.length];
}
