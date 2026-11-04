import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../theme/app_scrollbar_theme.dart';

/// VS Code-style scrollbar chrome for the built-in code editor and diff views.
///
/// re-editor ships its own [RawScrollbar] that is always visible, hard-coded to
/// 8 px and unaware of the app [ScrollbarThemeData]. Handing it this builder
/// instead routes the editor's two scrollables through [TpOverlayScrollbar], so
/// the thumb fades in only when the pointer is near the editor edge and shares
/// the app-wide thickness, radius and theme-derived colors.
///
/// Pass the same width to [CodeEditor.verticalScrollbarWidth] /
/// [CodeEditor.horizontalScrollbarHeight] (see [kAppCodeScrollbarExtent]) so the
/// editor reserves exactly the strip it paints the bar in.
Widget buildAppCodeScrollbar(
  BuildContext context,
  Widget child,
  ScrollableDetails details,
) {
  final controller = details.controller;
  if (controller == null) return child;
  final horizontal =
      details.direction == AxisDirection.right ||
      details.direction == AxisDirection.left;
  return TpOverlayScrollbar(
    controller: controller,
    axis: horizontal ? Axis.horizontal : Axis.vertical,
    child: child,
  );
}

/// Width/height reserved for the editor scrollbars, in logical pixels.
const double kAppCodeScrollbarExtent = kAppScrollbarThickness;
