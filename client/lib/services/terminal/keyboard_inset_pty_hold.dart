import 'dart:async';

import 'terminal_layout_coordinator.dart';

/// Collapses a soft-keyboard animation into a single PTY resize.
///
/// Android reports a growing bottom inset on *every frame* of the IME animation,
/// and each frame is a different cell grid. Forwarded as-is that is a SIGWINCH
/// per frame, and the reflowed repaints land interleaved over following frames —
/// the terminal visibly shudders. This holds the resize while the inset is still
/// moving and flushes one resize at the size it settled on, the same bracket
/// [TerminalLayoutCoordinator] applies to desktop chrome animations.
///
/// The hold target is resolved lazily on each call: it lives behind a
/// `GlobalKey<TerminalViewState>`, which is null before the first layout.
class KeyboardInsetPtyHold {
  KeyboardInsetPtyHold({
    required PtyResizeHoldTarget? Function() target,
    Duration settleDelay = const Duration(milliseconds: 120),
  })  : _target = target,
        _settleDelay = settleDelay;

  final PtyResizeHoldTarget? Function() _target;

  /// Longer than a frame (the animation reports an inset every frame) and
  /// shorter than a user could plausibly resize twice on purpose.
  final Duration _settleDelay;

  double? _lastInset;
  Timer? _settle;
  bool _holding = false;

  /// Whether a hold bracket is currently open — the inset is still moving.
  bool get isHolding => _holding;

  /// Feed the current bottom inset in logical pixels. Repeats are ignored, so a
  /// metrics change that leaves the keyboard alone (rotation of a page with no
  /// keyboard, a display cutout report) costs nothing.
  void onInsetChanged(double inset) {
    if (inset == _lastInset) return;
    _lastInset = inset;
    if (!_holding) {
      _holding = true;
      _target()?.beginPtyHold();
    }
    _settle?.cancel();
    _settle = Timer(_settleDelay, release);
  }

  /// Ends the bracket early, flushing the current grid unless [flush] is false —
  /// which is the teardown case, where a resize nobody will see is pointless.
  void release({bool flush = true}) {
    _settle?.cancel();
    _settle = null;
    if (!_holding) return;
    _holding = false;
    _target()?.endPtyHold(flush: flush);
  }

  void dispose() => release(flush: false);
}
