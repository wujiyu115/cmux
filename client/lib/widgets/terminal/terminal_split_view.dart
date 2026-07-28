import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../models/terminal_split.dart';
import '../../models/terminal_surface.dart';
import '../../services/terminal/terminal_layout_coordinator.dart';
import 'terminal_pane_keys.dart';
import 'terminal_split_divider.dart';

/// Builds one pane's widget for [paneId], given its stable terminal-view [key]
/// and whether it is the surface's focused pane.
typedef TerminalPaneBuilder = Widget Function(
  BuildContext context,
  String paneId,
  GlobalKey<TerminalViewState> key,
  bool isFocused,
);

/// Recursive renderer for a [TerminalSurface]'s split tree.
///
/// Leaves become panes ([TerminalPaneBuilder]); branches become resizable
/// [Row]/[Column] splits with a [TerminalSplitDivider] between the children.
/// Divider drag resizes live (local state) while the PTYs stay held via
/// [coordinator]; the final ratio is written back through [onSurfaceChanged].
/// A zoomed pane fills the area while every other pane stays mounted (offstage)
/// so its engine keeps consuming PTY output.
class TerminalSplitView extends StatefulWidget {
  const TerminalSplitView({
    required this.surface,
    required this.paneKeys,
    required this.coordinator,
    required this.paneBuilder,
    required this.onSurfaceChanged,
    required this.onPaneFocused,
    this.focusBorderColor,
    super.key,
  });

  final TerminalSurface surface;
  final TerminalPaneKeys paneKeys;
  final TerminalLayoutCoordinator coordinator;
  final TerminalPaneBuilder paneBuilder;

  /// Called at drag end / double-tap reset with the surface holding the new ratio.
  final void Function(TerminalSurface surface) onSurfaceChanged;

  /// Called on pointer-down anywhere in a pane (without swallowing the event).
  final void Function(String paneId) onPaneFocused;

  /// Border color of the focused pane (default: colorScheme.primary).
  final Color? focusBorderColor;

  @override
  State<TerminalSplitView> createState() => _TerminalSplitViewState();
}

class _TerminalSplitViewState extends State<TerminalSplitView> {
  // Live drag state — a null [_dragPath] means no drag is in progress.
  List<int>? _dragPath;
  double? _dragRatio;
  double? _dragStartRatio;
  double? _dragExtent;
  double _dragDelta = 0;
  SplitAxis _dragAxis = SplitAxis.vertical;

  @override
  Widget build(BuildContext context) {
    final surface = widget.surface;
    final zoom = surface.zoomedPaneId;
    final zoomActive = zoom != null && containsPane(surface.root, zoom);
    final tree = _buildNode(context, surface.root, const [], zoomActive ? zoom : null);
    if (!zoomActive) return tree;
    // Keep the whole tree mounted (offstage, no ticks) so hidden PTYs stay live;
    // the zoomed pane paints on top. The offstage tree omits the zoomed leaf so
    // its GlobalKey is used exactly once.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: true,
          child: TickerMode(enabled: false, child: tree),
        ),
        _buildLeaf(context, zoom),
      ],
    );
  }

  Widget _buildNode(
    BuildContext context,
    SplitNode node,
    List<int> path,
    String? zoomSkip,
  ) {
    if (node is SplitLeaf) {
      if (zoomSkip != null && node.paneId == zoomSkip) {
        return const SizedBox.shrink();
      }
      return _buildLeaf(context, node.paneId);
    }
    final branch = node as SplitBranch;
    final isVertical = branch.axis == SplitAxis.vertical;
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = isVertical ? constraints.maxWidth : constraints.maxHeight;
        final ratio = (_dragPath != null && _listEquals(_dragPath!, path))
            ? _dragRatio!
            : branch.ratio;
        final firstFlex = (ratio * 1000).round().clamp(1, 999);
        final secondFlex = 1000 - firstFlex;
        final children = <Widget>[
          Flexible(
            flex: firstFlex,
            child: _buildNode(context, branch.first, [...path, 0], zoomSkip),
          ),
          TerminalSplitDivider(
            axis: branch.axis,
            onDragStart: () => _onDragStart(path, branch.ratio, branch.axis, extent),
            onDragUpdate: _onDragUpdate,
            onDragEnd: _onDragEnd,
            onDragCancel: _onDragCancel,
            onReset: () => _resetBranch(path),
          ),
          Flexible(
            flex: secondFlex,
            child: _buildNode(context, branch.second, [...path, 1], zoomSkip),
          ),
        ];
        return isVertical
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      },
    );
  }

  Widget _buildLeaf(BuildContext context, String paneId) {
    final key = widget.paneKeys.keyFor(paneId);
    final isFocused = paneId == widget.surface.focusedPaneId;
    final borderColor = isFocused
        ? (widget.focusBorderColor ?? Theme.of(context).colorScheme.primary)
        : Colors.transparent;
    return Listener(
      // Translucent so the terminal still receives the click for selection/focus.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onPaneFocused(paneId),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor),
        ),
        child: widget.paneBuilder(context, paneId, key, isFocused),
      ),
    );
  }

  void _onDragStart(List<int> path, double startRatio, SplitAxis axis, double extent) {
    widget.coordinator.beginAllTransactions();
    setState(() {
      _dragPath = List.of(path);
      _dragStartRatio = startRatio;
      _dragRatio = startRatio;
      _dragExtent = extent;
      _dragAxis = axis;
      _dragDelta = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final start = _dragStartRatio;
    final extent = _dragExtent;
    if (_dragPath == null || start == null || extent == null || extent <= 0) {
      return;
    }
    _dragDelta +=
        _dragAxis == SplitAxis.vertical ? details.delta.dx : details.delta.dy;
    final next = (start + _dragDelta / extent).clamp(0.1, 0.9).toDouble();
    setState(() => _dragRatio = next);
  }

  void _onDragEnd() {
    final path = _dragPath;
    final ratio = _dragRatio;
    widget.coordinator.endAllTransactions(flush: true);
    if (path != null && ratio != null) {
      widget.onSurfaceChanged(
        widget.surface.copyWith(
          root: setRatioAtPath(widget.surface.root, path, ratio),
        ),
      );
    }
    _clearDrag();
  }

  void _onDragCancel() {
    // A pan-down that never became a drag leaves [_dragPath] null — nothing to
    // release or discard.
    if (_dragPath == null) return;
    widget.coordinator.endAllTransactions(flush: true);
    _clearDrag(); // Discard the in-flight ratio without writing back.
  }

  void _resetBranch(List<int> path) {
    widget.onSurfaceChanged(
      widget.surface.copyWith(
        root: setRatioAtPath(widget.surface.root, path, 0.5),
      ),
    );
  }

  void _clearDrag() {
    setState(() {
      _dragPath = null;
      _dragRatio = null;
      _dragStartRatio = null;
      _dragExtent = null;
      _dragDelta = 0;
    });
  }
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
