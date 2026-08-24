import 'package:flutter/foundation.dart';

/// The last startup stage `buildAppShell` announced, plus how long ago.
///
/// A global rather than a cubit: it is written from `buildAppShell`, which runs
/// before any provider exists, and read by the bootstrap gate, which is the only
/// thing on screen at the time.
///
/// This exists because a *stalled* startup and a *crashed* startup looked
/// identical: [AppBootstrapLoadingPage] is a white Scaffold with a logo, so a
/// bootstrap that never completes renders as a blank screen with no way to tell
/// which await is hanging. On iOS that was the whole diagnostic surface — no
/// native splash, no reachable log file on a stock device.
class BootProgress {
  const BootProgress._();

  /// Notifies on every [mark]; the gate rebuilds its status line from it.
  static final stage = ValueNotifier<String>('starting');

  static final _clock = Stopwatch()..start();

  /// Milliseconds since the process began recording stages.
  static int get elapsedMs => _clock.elapsedMilliseconds;

  /// When the current [stage] was entered, in [elapsedMs] terms. A large gap
  /// between this and now is exactly the "stuck here" signal.
  static int enteredAtMs = 0;

  static void mark(String phase) {
    enteredAtMs = _clock.elapsedMilliseconds;
    stage.value = phase;
  }

  @visibleForTesting
  static void reset() {
    enteredAtMs = 0;
    stage.value = 'starting';
  }
}
