import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/reconciled_keyboard.dart';

PhysicalKeyboardKey _physicalFor(LogicalKeyboardKey logicalKey) {
  return switch (logicalKey) {
    LogicalKeyboardKey.altLeft => PhysicalKeyboardKey.altLeft,
    LogicalKeyboardKey.controlLeft => PhysicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.shiftLeft => PhysicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.capsLock => PhysicalKeyboardKey.capsLock,
    LogicalKeyboardKey.digit1 => PhysicalKeyboardKey.digit1,
    _ => throw UnsupportedError('Add mapping for $logicalKey'),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  KeyDownEvent keyDown(LogicalKeyboardKey logicalKey) => KeyDownEvent(
    physicalKey: _physicalFor(logicalKey),
    logicalKey: logicalKey,
    timeStamp: Duration.zero,
  );

  KeyUpEvent keyUp(LogicalKeyboardKey logicalKey) => KeyUpEvent(
    physicalKey: _physicalFor(logicalKey),
    logicalKey: logicalKey,
    timeStamp: Duration.zero,
  );

  /// Drives the real keyboard, which is what feeds an attached mirror.
  void press(LogicalKeyboardKey key) =>
      HardwareKeyboard.instance.handleKeyEvent(keyDown(key));

  void release(LogicalKeyboardKey key) =>
      HardwareKeyboard.instance.handleKeyEvent(keyUp(key));

  late ReconciledKeyboard keyboard;

  setUp(() {
    keyboard = ReconciledKeyboard();
  });

  tearDown(() {
    keyboard.detach();
    // Never leave a phantom modifier behind for the next test.
    for (final key in [
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.digit1,
    ]) {
      if (HardwareKeyboard.instance.isLogicalKeyPressed(key)) release(key);
    }
  });

  group('mirroring', () {
    test('state falls back to the real keyboard while unattached', () {
      expect(keyboard.isAttached, isFalse);
      expect(keyboard.state, same(HardwareKeyboard.instance));
    });

    test('state is the mirror once attached', () {
      keyboard.attach();

      expect(keyboard.state, same(keyboard.debugMirror));
    });

    test('mirror tracks key down and key up verbatim', () {
      keyboard.attach();

      press(LogicalKeyboardKey.altLeft);
      expect(keyboard.state.isAltPressed, isTrue);

      release(LogicalKeyboardKey.altLeft);
      expect(keyboard.state.isAltPressed, isFalse);
    });

    test('attach is idempotent — one handler, so one mirrored press', () {
      keyboard.attach();
      keyboard.attach();

      press(LogicalKeyboardKey.altLeft);
      // A second registration would replay the same event twice. The pressed
      // set would still report Alt, so assert on the physical key count.
      expect(keyboard.debugMirror.physicalKeysPressed, hasLength(1));

      release(LogicalKeyboardKey.altLeft);
      expect(keyboard.debugMirror.physicalKeysPressed, isEmpty);
    });

    test('detach stops mirroring and drops the mirrored state', () {
      keyboard.attach();
      press(LogicalKeyboardKey.altLeft);

      keyboard.detach();

      expect(keyboard.debugMirror.isAltPressed, isFalse);

      // Further real events no longer reach the mirror.
      press(LogicalKeyboardKey.controlLeft);
      expect(keyboard.debugMirror.isControlPressed, isFalse);
    });
  });

  group('clear', () {
    test('releases a stuck modifier the real keyboard still reports', () {
      keyboard.attach();
      press(LogicalKeyboardKey.altLeft);

      keyboard.clear();

      // The divergence IS the fix: the framework still believes Alt is held
      // (that is the bug we cannot reach into), the mirror does not.
      expect(HardwareKeyboard.instance.isAltPressed, isTrue);
      expect(keyboard.state.isAltPressed, isFalse);
    });

    test('a late real key-up for an already-cleared key does not throw', () {
      keyboard.attach();
      press(LogicalKeyboardKey.altLeft);
      keyboard.clear();

      // This is exactly what happens when the stranded Alt key-up finally
      // arrives after the user returns to the window.
      expect(() => release(LogicalKeyboardKey.altLeft), returnsNormally);
      expect(keyboard.state.isAltPressed, isFalse);
    });

    test('preserves lock modes — CapsLock is a toggle, not a held key', () {
      keyboard.attach();
      press(LogicalKeyboardKey.capsLock);
      expect(
        keyboard.debugMirror.lockModesEnabled,
        contains(KeyboardLockMode.capsLock),
      );

      keyboard.clear();

      // Regression pin for using synthesized key-ups instead of
      // HardwareKeyboard.clearState(), which also wipes lock modes.
      expect(
        keyboard.debugMirror.lockModesEnabled,
        contains(KeyboardLockMode.capsLock),
      );
      expect(keyboard.debugMirror.physicalKeysPressed, isEmpty);

      release(LogicalKeyboardKey.capsLock);
    });

    test('clears every held key, not just modifiers', () {
      keyboard.attach();
      press(LogicalKeyboardKey.altLeft);
      press(LogicalKeyboardKey.digit1);

      keyboard.clear();

      expect(keyboard.debugMirror.physicalKeysPressed, isEmpty);
    });

    test('is a no-op that does not notify when nothing is held', () {
      keyboard.attach();
      var notifications = 0;
      keyboard.addListener(() => notifications++);

      keyboard.clear();

      expect(notifications, 0);
    });

    test('notifies listeners when it releases something', () {
      keyboard.attach();
      var notifications = 0;
      keyboard.addListener(() => notifications++);
      press(LogicalKeyboardKey.altLeft);

      keyboard.clear();

      expect(notifications, 1);
    });
  });

  group('handleAppLifecycleState', () {
    test('clears on every state except resumed', () {
      for (final state in AppLifecycleState.values.where(
        (s) => s != AppLifecycleState.resumed,
      )) {
        keyboard.attach();
        press(LogicalKeyboardKey.altLeft);

        keyboard.handleAppLifecycleState(state);

        expect(
          keyboard.state.isAltPressed,
          isFalse,
          reason: 'should clear on $state',
        );
        release(LogicalKeyboardKey.altLeft);
        keyboard.detach();
      }
    });

    test('resumed does not clear — a held modifier stays held', () {
      keyboard.attach();
      press(LogicalKeyboardKey.altLeft);

      keyboard.handleAppLifecycleState(AppLifecycleState.resumed);

      expect(keyboard.state.isAltPressed, isTrue);
    });
  });

  group('ReconciledKeyboardWindowListener', () {
    test('onWindowBlur clears — the Alt+Tab case', () {
      keyboard.attach();
      final listener = ReconciledKeyboardWindowListener(keyboard);
      press(LogicalKeyboardKey.altLeft);

      listener.onWindowBlur();

      expect(keyboard.state.isAltPressed, isFalse);
    });

    test('onWindowFocus clears — backstop when blur never arrived', () {
      keyboard.attach();
      final listener = ReconciledKeyboardWindowListener(keyboard);
      press(LogicalKeyboardKey.altLeft);

      listener.onWindowFocus();

      expect(keyboard.state.isAltPressed, isFalse);
    });
  });
}
