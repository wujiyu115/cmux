import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:window_manager/window_manager.dart';

/// A mirror of [HardwareKeyboard.instance]'s pressed-key state that the app can
/// reset when the window changes focus.
///
/// ## Why this exists
///
/// The framework only removes a key from its pressed set when it sees a
/// matching key-up. On Windows, Alt+Tab delivers the Alt *key-down* to us and
/// the Alt *key-up* to whichever window took focus, so
/// `HardwareKeyboard.instance.isAltPressed` can stay `true` forever. Flutter
/// does not self-heal this, and the app has no way to clear the framework's own
/// state (`HardwareKeyboard.clearState` is test-only and would also drop the
/// handler list and the lock modes).
///
/// A phantom Alt then corrupts every modifier-sensitive path at once:
///
///   * `SingleActivator(digit1, alt: true)` — the `stripFocusTab` bindings —
///     starts matching a *bare* `1`, so typing a digit in a terminal hops tabs.
///   * `SingleActivator(keyV, control: true, shift: true)` — terminal paste —
///     stops matching, because a `SingleActivator` requires `alt == false`.
///   * `ImeKeyRouting.isDeferrablePrintableKeyEvent` bails on any Ctrl/Alt/Meta,
///     so printables stop being handed to the OS IME and CJK composition drops
///     its first commit.
///
/// ## How it works
///
/// [attach] installs a [HardwareKeyboard] handler that replays every event into
/// a private [HardwareKeyboard] instance **verbatim**. That makes the mirror
/// bit-identical to the real one except where we deliberately [clear] it — the
/// whole behavioral delta, in one sentence.
///
/// Callers that need "which modifiers are down?" read [state] and hand it to
/// `ShortcutActivator.accepts`, so no activator-matching logic is duplicated.
class ReconciledKeyboard extends ChangeNotifier {
  ReconciledKeyboard();

  /// Root instance, installed by `ShortcutDispatcherHost` in `main.dart`.
  static final ReconciledKeyboard instance = ReconciledKeyboard();

  final HardwareKeyboard _mirror = HardwareKeyboard();

  /// Timestamp of the last real event, reused for synthesized key-ups so this
  /// class never needs a clock (which would make it untestable).
  Duration _lastTimeStamp = Duration.zero;

  bool _attached = false;

  bool get isAttached => _attached;

  /// The keyboard to read modifier state from.
  ///
  /// Falls back to the live [HardwareKeyboard.instance] while unattached, so
  /// test harnesses and any code running before the host mounts behave exactly
  /// as they did before this class existed. Production attachment is enforced
  /// by an assert in `ShortcutDispatcher.attach`, not by asserting here — an
  /// assert here would fire in every widget test that pumps app chrome.
  HardwareKeyboard get state => _attached ? _mirror : HardwareKeyboard.instance;

  /// Starts mirroring. Idempotent.
  ///
  /// Must be registered BEFORE `ShortcutDispatcher.handle`: [HardwareKeyboard]
  /// dispatches handlers in registration order, and Flutter runs all
  /// [HardwareKeyboard] handlers before the focus dispatch path, so registering
  /// first is what guarantees the mirror is current by the time either the
  /// dispatcher or a `Focus.onKeyEvent` reads it.
  void attach() {
    if (_attached) return;
    _attached = true;
    HardwareKeyboard.instance.addHandler(_feed);
  }

  /// Stops mirroring and drops the mirrored state. Idempotent.
  void detach() {
    if (!_attached) return;
    _attached = false;
    HardwareKeyboard.instance.removeHandler(_feed);
    clear();
  }

  /// Replays [event] into the mirror. Deliberately does no sanitizing: an
  /// irregular sequence (the real Alt key-up finally arriving after we already
  /// cleared) only reaches a `debugPrint` inside an `assert`, never a throw.
  bool _feed(KeyEvent event) {
    _lastTimeStamp = event.timeStamp;
    _mirror.handleKeyEvent(event);
    return false;
  }

  /// Releases every key the mirror believes is held.
  ///
  /// Synthesizes a [KeyUpEvent] per pressed key rather than calling
  /// `HardwareKeyboard.clearState`, for two reasons: that method is
  /// `@visibleForTesting`, and it also wipes the lock modes — but CapsLock and
  /// NumLock are *toggles*, not held keys, so dropping them on every Alt+Tab
  /// would be a new bug. Only [KeyDownEvent] touches lock modes, so a
  /// synthesized up leaves them intact.
  void clear() {
    // `physicalKeysPressed` returns a fresh set, so mutating while iterating is
    // safe.
    final pressed = _mirror.physicalKeysPressed;
    if (pressed.isEmpty) return;
    for (final physicalKey in pressed) {
      final logicalKey = _mirror.lookUpLayout(physicalKey);
      if (logicalKey == null) continue;
      _mirror.handleKeyEvent(
        KeyUpEvent(
          physicalKey: physicalKey,
          logicalKey: logicalKey,
          timeStamp: _lastTimeStamp,
          synthesized: true,
        ),
      );
    }
    notifyListeners();
  }

  /// Lifecycle backstop for the window-focus clears: covers hosts where
  /// `window_manager`'s channel isn't live, and is a transition a widget test
  /// can drive without a method channel.
  ///
  /// Anything other than [AppLifecycleState.resumed] means we are not the
  /// window receiving keys, so nothing can still be held as far as we know.
  void handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    clear();
  }

  @visibleForTesting
  HardwareKeyboard get debugMirror => _mirror;
}

/// Clears [keyboard] whenever the window gains or loses focus.
///
/// Both directions matter. Blur is the direct fix: on Alt+Tab the window
/// deactivates while Alt is still physically down, so clearing here means the
/// state is already sane before anyone asks again. Focus is the backstop for
/// blur never arriving (occlusion, Win+L, a UAC prompt), for a modifier
/// released while we were in the background, and for the app being launched
/// with a modifier held.
class ReconciledKeyboardWindowListener extends WindowListener {
  ReconciledKeyboardWindowListener(this.keyboard);

  final ReconciledKeyboard keyboard;

  @override
  void onWindowBlur() => keyboard.clear();

  @override
  void onWindowFocus() => keyboard.clear();
}
