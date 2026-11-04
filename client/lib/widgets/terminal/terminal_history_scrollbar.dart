import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/input/term_mode.dart' show kModeAltScreen;

import 'terminal_scrollbar_geometry.dart';

/// History scrollbar mapped like VTE + GtkAdjustment.
///
/// Ported from flutter_alacritty's example (not library API).
///
/// Painted VS Code-style: the slider stays hidden until the pointer comes near
/// the right edge or the view scrolls, then fades out again. Colours come from
/// the app [ScrollbarThemeData] so the terminal bar matches the file tree and
/// the other panels.
class TerminalHistoryScrollbar extends StatefulWidget {
  const TerminalHistoryScrollbar({
    required this.engine,
    required this.controller,
    super.key,
  });

  final TerminalEngine engine;
  final TerminalController controller;

  @override
  State<TerminalHistoryScrollbar> createState() =>
      _TerminalHistoryScrollbarState();
}

class _TerminalHistoryScrollbarState extends State<TerminalHistoryScrollbar>
    with SingleTickerProviderStateMixin {
  bool _dragging = false;
  double? _dragPositionFraction;
  double _lastScrollPos = 0;
  int _lastHistorySize = 0;
  int _lastModeFlags = 0;

  /// Coalesce rapid drag events: only the latest target is applied.
  double? _pendingPositionFraction;
  bool _scrollInFlight = false;
  int _scrollGeneration = 0;

  /// Hover-reveal animation: 0 = hidden, 1 = fully faded in.
  ///
  /// Created in [initState] rather than lazily: a `late final` initializer would
  /// run inside [dispose] when the bar never faded in, and creating a ticker
  /// while the element is deactivated throws.
  late final AnimationController _reveal;
  Timer? _hideTimer;
  bool _pointerInside = false;

  /// Idle delay before the slider fades away after the last scroll activity.
  static const Duration _hideDelay = Duration(milliseconds: 700);

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 220),
    );
    final grid = widget.engine.grid;
    _lastScrollPos = grid.displayOffset + grid.scrollFraction;
    _lastHistorySize = grid.historySize;
    _lastModeFlags = grid.modeFlags;
    widget.engine.repaint.addListener(_onGridChanged);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _reveal.dispose();
    widget.engine.repaint.removeListener(_onGridChanged);
    super.dispose();
  }

  /// Fade the slider in and keep it on screen while the pointer is on it.
  void _revealNow() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_reveal.isAnimating || _reveal.status != AnimationStatus.forward) {
      _reveal.animateTo(1, curve: Curves.easeOut);
    }
  }

  /// Fade the slider out again once the pointer left and scrolling stopped.
  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_dragging || _pointerInside) return;
    _hideTimer = Timer(_hideDelay, () {
      _hideTimer = null;
      if (!mounted || _dragging || _pointerInside) return;
      _reveal.animateBack(0, curve: Curves.easeIn);
    });
  }

  @override
  void didUpdateWidget(covariant TerminalHistoryScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      oldWidget.engine.repaint.removeListener(_onGridChanged);
      widget.engine.repaint.addListener(_onGridChanged);
      final grid = widget.engine.grid;
      _lastScrollPos = grid.displayOffset + grid.scrollFraction;
      _lastHistorySize = grid.historySize;
      _lastModeFlags = grid.modeFlags;
    }
  }

  void _onGridChanged() {
    if (!mounted || _dragging) return;
    final grid = widget.engine.grid;
    final scrollPos = grid.displayOffset + grid.scrollFraction;
    if (scrollPos == _lastScrollPos &&
        grid.modeFlags == _lastModeFlags &&
        grid.historySize == _lastHistorySize) {
      return;
    }
    // Only real scrolling reveals the slider — new output at the live bottom
    // must not keep it on screen.
    final scrolled = scrollPos != _lastScrollPos;
    _lastScrollPos = scrollPos;
    _lastHistorySize = grid.historySize;
    _lastModeFlags = grid.modeFlags;
    if (scrolled) {
      _revealNow();
      _scheduleHide();
    }
    setState(() {});
  }

  TerminalScrollbarGeometry _geometry(double trackHeight) {
    final grid = widget.engine.grid;
    return TerminalScrollbarGeometry(
      historySize: grid.historySize,
      viewportRows: grid.rows,
      scrollOffsetLines: grid.displayOffset + grid.scrollFraction,
      trackHeight: trackHeight,
    );
  }

  Future<void> _scrollToPositionFraction(double positionFraction) async {
    final grid = widget.engine.grid;
    final historySize = grid.historySize;
    if (historySize <= 0) return;

    final geom = TerminalScrollbarGeometry(
      historySize: historySize,
      viewportRows: grid.rows,
      scrollOffsetLines: 0,
      trackHeight: 1,
    );

    if (geom.isNearLiveBottom(positionFraction)) {
      await widget.controller.scrollToBottom();
      return;
    }
    if (geom.isNearHistoryTop(positionFraction)) {
      await widget.controller.scrollToTop();
      return;
    }

    final target = geom.scrollOffsetForPosition(positionFraction);
    await widget.controller.scrollToOffset(target);
  }

  Future<void> _drainPendingScroll() async {
    if (_scrollInFlight) return;
    _scrollInFlight = true;
    try {
      while (_pendingPositionFraction != null) {
        final fraction = _pendingPositionFraction!;
        _pendingPositionFraction = null;
        final gen = ++_scrollGeneration;
        await _scrollToPositionFraction(fraction);
        if (gen != _scrollGeneration) return;
      }
    } finally {
      _scrollInFlight = false;
      if (_pendingPositionFraction != null) {
        await _drainPendingScroll();
      }
    }
  }

  void _onTrackPointer(double localDy, double trackHeight) {
    if (trackHeight <= 0) return;
    final geom = _geometry(trackHeight);
    if (!geom.visible) return;

    final positionFraction =
        TerminalScrollbarGeometry.positionFractionFromTrackDy(
          localDy: localDy,
          trackHeight: trackHeight,
          thumbHeight: geom.thumbHeight,
        );
    _pendingPositionFraction = positionFraction;
    if (_dragging) {
      _dragPositionFraction = positionFraction;
      setState(() {});
    }
    _drainPendingScroll();
  }

  @override
  Widget build(BuildContext context) {
    final grid = widget.engine.grid;
    if (grid.modeFlags & kModeAltScreen != 0) {
      return const SizedBox(width: 0);
    }
    if (grid.historySize <= 0) {
      return const SizedBox(width: 0);
    }

    final theme = ScrollbarTheme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final thickness = theme.thickness?.resolve({}) ?? 10.0;
    final radius = theme.radius ?? Radius.circular(thickness / 2);
    final trackColor = theme.trackColor?.resolve({}) ?? Colors.transparent;
    // Same state ramp as the Material [Scrollbar]s: the app theme owns the tone.
    final states = <WidgetState>{
      if (_dragging) WidgetState.dragged,
      if (_pointerInside) WidgetState.hovered,
    };
    final thumbColor =
        theme.thumbColor?.resolve(states) ??
        colorScheme.onSurface.withValues(alpha: _dragging ? 0.48 : 0.3);
    // Wide enough to aim at comfortably; the slider itself is [thickness] wide.
    final stripWidth = thickness + 4;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight;
        if (trackHeight <= 0) return const SizedBox(width: 0);

        final geom = _geometry(trackHeight);
        final thumbFraction = geom.positionFraction;
        final paintFraction = _dragPositionFraction ?? thumbFraction;
        final thumbTop = geom.thumbTopAt(paintFraction);

        return SizedBox(
          width: stripWidth,
          child: MouseRegion(
            onEnter: (_) {
              _pointerInside = true;
              _revealNow();
              setState(() {});
            },
            onExit: (_) {
              _pointerInside = false;
              _scheduleHide();
              setState(() {});
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) {
                _scrollGeneration++;
                widget.engine.cancelCoalescedScrollInput();
                _dragging = true;
                _dragPositionFraction = null;
                _revealNow();
              },
              onVerticalDragEnd: (_) {
                _dragging = false;
                _dragPositionFraction = null;
                _scheduleHide();
                setState(() {});
              },
              onVerticalDragCancel: () {
                _dragging = false;
                _dragPositionFraction = null;
                _scheduleHide();
                setState(() {});
              },
              onVerticalDragUpdate: (d) =>
                  _onTrackPointer(d.localPosition.dy, trackHeight),
              onTapDown: (d) {
                _scrollGeneration++;
                widget.engine.cancelCoalescedScrollInput();
                _onTrackPointer(d.localPosition.dy, trackHeight);
              },
              child: AnimatedBuilder(
                animation: _reveal,
                builder: (context, _) => CustomPaint(
                  painter: _ScrollbarPainter(
                    thumbTop: thumbTop,
                    thumbHeight: geom.thumbHeight,
                    trackWidth: thickness,
                    radius: radius,
                    trackColor: trackColor,
                    thumbColor: thumbColor,
                    opacity: _reveal.value,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScrollbarPainter extends CustomPainter {
  _ScrollbarPainter({
    required this.thumbTop,
    required this.thumbHeight,
    required this.trackWidth,
    required this.radius,
    required this.trackColor,
    required this.thumbColor,
    required this.opacity,
  });

  final double thumbTop;
  final double thumbHeight;
  final double trackWidth;
  final Radius radius;
  final Color trackColor;
  final Color thumbColor;

  /// Fade-in amount for the whole bar (0 = hidden).
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final right = size.width - trackWidth - 2;
    final trackR = RRect.fromRectAndRadius(
      Rect.fromLTWH(right, 0, trackWidth, size.height),
      radius,
    );
    final fadedTrack = trackColor.withValues(alpha: trackColor.a * opacity);
    if (fadedTrack.a > 0) {
      canvas.drawRRect(trackR, Paint()..color = fadedTrack);
    }

    final thumbR = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        right,
        thumbTop,
        trackWidth,
        thumbHeight.clamp(0, size.height),
      ),
      radius,
    );
    canvas.drawRRect(
      thumbR,
      Paint()..color = thumbColor.withValues(alpha: thumbColor.a * opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _ScrollbarPainter old) =>
      old.thumbTop != thumbTop ||
      old.thumbHeight != thumbHeight ||
      old.trackWidth != trackWidth ||
      old.thumbColor != thumbColor ||
      old.trackColor != trackColor ||
      old.opacity != opacity;
}
