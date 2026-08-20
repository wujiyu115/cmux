import 'package:flutter/services.dart';

import 'command_bus.dart';
import 'command_catalog.dart';
import 'command_definition.dart';
import 'double_shift_detector.dart';
import 'key_chord.dart';
import 'keybinding_resolver.dart';
import 'reconciled_keyboard.dart';
import 'shortcut_context.dart';

/// Matches every [KeyDownEvent] against the effective keybindings and, on a
/// match, invokes the corresponding command id on [CommandBus] — regardless
/// of whether a handler is currently registered for it.
///
/// One instance is installed near the app root via [attach] (see
/// `ShortcutDispatcherHost` in `main.dart`) and lives for the app's lifetime.
/// See docs/superpowers/specs/2026-07-11-keyboard-shortcuts-platform-design.md.
class ShortcutDispatcher {
  ShortcutDispatcher({
    required CommandBus bus,
    required List<KeyChord> Function(String commandId) effectiveChords,
    required ShortcutContext Function() context,
    required bool Function() isMacOS,
    List<CommandDefinition>? catalog,
    DoubleShiftDetector? doubleShiftDetector,
    ReconciledKeyboard? keyboard,
  }) : _bus = bus,
       _effectiveChords = effectiveChords,
       _context = context,
       _isMacOS = isMacOS,
       _catalog = catalog ?? CommandCatalog.v1,
       _doubleShiftDetector = doubleShiftDetector ?? DoubleShiftDetector(),
       _keyboard = keyboard ?? ReconciledKeyboard.instance;

  final CommandBus _bus;
  final List<KeyChord> Function(String commandId) _effectiveChords;
  final ShortcutContext Function() _context;
  final bool Function() _isMacOS;
  final List<CommandDefinition> _catalog;
  final DoubleShiftDetector _doubleShiftDetector;
  final ReconciledKeyboard _keyboard;

  /// Set to `false` to temporarily suspend all shortcut matching (e.g. while
  /// a modal keyboard grab, such as a rebind-capture dialog, is active).
  bool enabled = true;

  /// The current app focus/state snapshot used for shortcut matching.
  ///
  /// Exposed so app-level features (e.g. the command palette) can decide
  /// which commands are available under the same `when` state as the keyboard
  /// dispatcher, without threading the context builder through every caller.
  ShortcutContext get currentContext => _context();

  /// Returns `true` if [event] matched a command and was forwarded to the
  /// bus, `false` if it should keep propagating normally.
  bool handle(KeyEvent event) {
    if (!enabled) return false;

    if (_doubleShiftDetector.feed(event)) {
      final commandId = _matchDoubleTapShift();
      if (commandId != null) {
        _bus.invoke(commandId);
        return true;
      }
    }

    if (event is! KeyDownEvent) return false;

    final effectiveByCommand = <String, List<KeyChord>>{
      for (final def in _catalog) def.id: _effectiveChords(def.id),
    };

    final commandId = KeybindingResolver.match(
      event: event,
      effectiveByCommand: effectiveByCommand,
      context: _context(),
      isMacOS: _isMacOS(),
      catalog: _catalog,
      keyboardState: _keyboard.state,
    );
    if (commandId == null) return false;

    // Silent no-op when nothing is registered — still counts as handled so
    // the key doesn't fall through to e.g. a terminal PTY while chrome that
    // will eventually own this command is still mounting.
    _bus.invoke(commandId);
    return true;
  }

  String? _matchDoubleTapShift() {
    final context = _context();
    for (final def in _catalog) {
      final chords = _effectiveChords(def.id);
      if (!chords.any((c) => c.doubleTap && c.key == 'shift')) continue;
      if (!def.when.isSatisfiedBy(context)) continue;
      if (context.inTerminal && !def.terminalPassthrough) continue;
      return def.id;
    }
    return null;
  }

  void attach() {
    // The mirror must already be listening, or it will miss the events that
    // happen before it attaches and report stale modifiers to [handle]. Owning
    // the mirror's lifecycle here instead would hide that ordering from the
    // host, which also needs it for the window-focus clears.
    assert(
      _keyboard.isAttached,
      'ReconciledKeyboard must be attached before the dispatcher so the mirror '
      'is current when handle() runs',
    );
    HardwareKeyboard.instance.addHandler(handle);
  }

  void detach() {
    HardwareKeyboard.instance.removeHandler(handle);
  }
}
