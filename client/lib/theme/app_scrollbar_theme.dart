import 'package:flutter/material.dart';

/// Slider thickness for every scrollable surface, in logical pixels.
///
/// Matches VS Code's `editor.scrollbar.verticalScrollbarSize` default (14) so
/// the bar is easy to grab and the hover/click strip is comfortable.
const double kAppScrollbarThickness = 14;

/// Shortest the slider may shrink to when the scrollable content is huge.
const double kAppScrollbarMinThumbLength = 28;

/// VS Code-style overlay scrollbar theme shared by all [Scrollbar]s.
///
/// * Hover-driven: the thumb is hidden until the pointer comes near the bar or
///   a scroll is in flight, then it fades back out — no permanent track sitting
///   in every panel.
/// * Theme-toned: the slider is derived from [ColorScheme.onSurface] (so it
///   follows the active preset / terminal-derived scheme) instead of a fixed
///   gray, and stays translucent so it never competes with the content.
/// * Rounded, inset from both edges, with a minimum thumb length so short
///   slivers stay visible.
ScrollbarThemeData buildAppScrollbarTheme({required ColorScheme colorScheme}) {
  final bool isDark = colorScheme.brightness == Brightness.dark;
  // Narrow alpha ramp mirroring VS Code's slider idle → hover → drag states.
  final double idleAlpha = isDark ? 0.20 : 0.22;
  final double hoverAlpha = isDark ? 0.34 : 0.36;
  final double dragAlpha = isDark ? 0.48 : 0.50;
  final Color slider = colorScheme.onSurface;

  return ScrollbarThemeData(
    thickness: const WidgetStatePropertyAll(kAppScrollbarThickness),
    radius: const Radius.circular(kAppScrollbarThickness / 2),
    crossAxisMargin: 2,
    mainAxisMargin: 2,
    minThumbLength: kAppScrollbarMinThumbLength,
    interactive: true,
    thumbVisibility: const WidgetStatePropertyAll(false),
    trackVisibility: const WidgetStatePropertyAll(false),
    thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.dragged)) {
        return slider.withValues(alpha: dragAlpha);
      }
      if (states.contains(WidgetState.hovered)) {
        return slider.withValues(alpha: hoverAlpha);
      }
      return slider.withValues(alpha: idleAlpha);
    }),
    trackColor: const WidgetStatePropertyAll(Colors.transparent),
    trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
  );
}
