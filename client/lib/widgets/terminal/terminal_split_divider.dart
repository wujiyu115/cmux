import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../models/terminal_split.dart';

/// Draggable divider between the two children of a [SplitBranch].
///
/// A thin hairline sits centered inside a wider (4 logical px) transparent hit
/// area. The resize cursor follows the split [axis]. Gesture callbacks are
/// forwarded raw; the owning split view converts them into ratio changes.
class TerminalSplitDivider extends StatelessWidget {
  const TerminalSplitDivider({
    required this.axis,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onReset,
    this.lineColor,
    super.key,
  });

  final SplitAxis axis;
  final VoidCallback onDragStart;
  final void Function(DragUpdateDetails details) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  /// Double-tap: reset the branch ratio to 0.5.
  final VoidCallback onReset;
  final Color? lineColor;

  /// Total logical hit width/height of the divider.
  static const double hitExtent = 4;

  @override
  Widget build(BuildContext context) {
    final isVertical = axis == SplitAxis.vertical;
    final cursor = isVertical
        ? SystemMouseCursors.resizeColumn
        : SystemMouseCursors.resizeRow;
    final color = lineColor ?? Theme.of(context).dividerColor;
    final line = SizedBox(
      width: isVertical ? 1 : double.infinity,
      height: isVertical ? double.infinity : 1,
      child: ColoredBox(color: color),
    );
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => onDragStart(),
        onPanUpdate: onDragUpdate,
        onPanEnd: (_) => onDragEnd(),
        onPanCancel: onDragCancel,
        onDoubleTap: onReset,
        child: SizedBox(
          width: isVertical ? hitExtent : null,
          height: isVertical ? null : hitExtent,
          child: Center(child: line),
        ),
      ),
    );
  }
}
