import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_definition.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/reconciled_keyboard.dart';
import 'package:teampilot/services/commands/shortcut_context.dart';
import 'package:teampilot/services/commands/shortcut_dispatcher.dart';

PhysicalKeyboardKey _physicalFor(LogicalKeyboardKey logicalKey) {
  return switch (logicalKey) {
    LogicalKeyboardKey.keyK => PhysicalKeyboardKey.keyK,
    LogicalKeyboardKey.keyZ => PhysicalKeyboardKey.keyZ,
    LogicalKeyboardKey.metaLeft => PhysicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.altLeft => PhysicalKeyboardKey.altLeft,
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

  void pressModifier(LogicalKeyboardKey key) {
    HardwareKeyboard.instance.handleKeyEvent(keyDown(key));
  }

  void releaseModifier(LogicalKeyboardKey key) {
    HardwareKeyboard.instance.handleKeyEvent(keyUp(key));
  }

  tearDown(() {
    for (final key in [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.altLeft,
    ]) {
      if (HardwareKeyboard.instance.isLogicalKeyPressed(key)) {
        releaseModifier(key);
      }
    }
  });

  final testCommandId = 'test.command';
  final testCatalog = [
    CommandDefinition(
      id: testCommandId,
      category: CommandCategory.meta,
      defaultChords: [KeyChord(key: 'k', mods: [KeyChordMod.mod])],
      when: ShortcutWhen.always,
      terminalPassthrough: true,
      titleL10nKey: 'x',
    ),
  ];

  ShortcutDispatcher buildDispatcher(CommandBus bus) {
    return ShortcutDispatcher(
      bus: bus,
      effectiveChords: (commandId) => testCatalog
          .firstWhere((def) => def.id == commandId)
          .defaultChords,
      context: () => const ShortcutContext(),
      isMacOS: () => true,
      catalog: testCatalog,
    );
  }

  group('ShortcutDispatcher.handle', () {
    test('match invokes the registered handler and returns true', () {
      final bus = CommandBus();
      var called = false;
      bus.register(testCommandId, () => called = true);
      final dispatcher = buildDispatcher(bus);

      pressModifier(LogicalKeyboardKey.metaLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.metaLeft));

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.keyK));

      expect(handled, isTrue);
      expect(called, isTrue);
    });

    test('match with no registered handler still returns true', () {
      final bus = CommandBus();
      final dispatcher = buildDispatcher(bus);

      pressModifier(LogicalKeyboardKey.metaLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.metaLeft));

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.keyK));

      expect(handled, isTrue);
    });

    test('disabled dispatcher returns false without invoking the bus', () {
      final bus = CommandBus();
      var called = false;
      bus.register(testCommandId, () => called = true);
      final dispatcher = buildDispatcher(bus)..enabled = false;

      pressModifier(LogicalKeyboardKey.metaLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.metaLeft));

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.keyK));

      expect(handled, isFalse);
      expect(called, isFalse);
    });

    test('no chord match returns false', () {
      final bus = CommandBus();
      final dispatcher = buildDispatcher(bus);

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.keyZ));

      expect(handled, isFalse);
    });

    test('non-KeyDownEvent returns false', () {
      final bus = CommandBus();
      final dispatcher = buildDispatcher(bus);

      pressModifier(LogicalKeyboardKey.metaLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.metaLeft));

      final handled = dispatcher.handle(keyUp(LogicalKeyboardKey.keyK));

      expect(handled, isFalse);
    });
  });

  group('ShortcutDispatcher reconciled keyboard', () {
    final altTabId = 'test.altTab';
    final altTabCatalog = [
      CommandDefinition(
        id: altTabId,
        category: CommandCategory.tabs,
        defaultChords: [KeyChord(key: 'digit1', mods: [KeyChordMod.alt])],
        when: ShortcutWhen.always,
        terminalPassthrough: true,
        titleL10nKey: 'x',
      ),
    ];

    ShortcutDispatcher buildWith(
      CommandBus bus,
      ReconciledKeyboard keyboard, {
      List<CommandDefinition>? catalog,
    }) {
      final effectiveCatalog = catalog ?? testCatalog;
      return ShortcutDispatcher(
        bus: bus,
        effectiveChords: (commandId) => effectiveCatalog
            .firstWhere((def) => def.id == commandId)
            .defaultChords,
        context: () => const ShortcutContext(),
        isMacOS: () => true,
        catalog: effectiveCatalog,
        keyboard: keyboard,
      );
    }

    test('attach asserts when the mirror is not listening yet', () {
      final keyboard = ReconciledKeyboard();
      final dispatcher = buildWith(CommandBus(), keyboard);

      expect(dispatcher.attach, throwsAssertionError);

      keyboard.attach();
      addTearDown(keyboard.detach);
      addTearDown(dispatcher.detach);
      expect(dispatcher.attach, returnsNormally);
    });

    test('a phantom Alt no longer fires the Alt+1 tab command', () {
      final keyboard = ReconciledKeyboard()..attach();
      addTearDown(keyboard.detach);
      final bus = CommandBus();
      var called = false;
      bus.register(altTabId, () => called = true);
      final dispatcher = buildWith(bus, keyboard, catalog: altTabCatalog);

      // Alt goes down for real, then its key-up is stranded in another window
      // — modeled by clearing the mirror the way a window blur does.
      pressModifier(LogicalKeyboardKey.altLeft);
      keyboard.clear();

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.digit1));

      expect(handled, isFalse);
      expect(called, isFalse);
      // The framework is still wrong; only the mirror was fixed.
      expect(HardwareKeyboard.instance.isAltPressed, isTrue);
    });

    test('a genuinely held Alt still fires Alt+1', () {
      final keyboard = ReconciledKeyboard()..attach();
      addTearDown(keyboard.detach);
      final bus = CommandBus();
      var called = false;
      bus.register(altTabId, () => called = true);
      final dispatcher = buildWith(bus, keyboard, catalog: altTabCatalog);

      pressModifier(LogicalKeyboardKey.altLeft);

      expect(dispatcher.handle(keyDown(LogicalKeyboardKey.digit1)), isTrue);
      expect(called, isTrue);
    });

    test('the mirror keeps tracking while the dispatcher is disabled', () {
      // Design lock: feeding the mirror must NOT live behind handle()'s
      // `enabled` guard. The rebind dialog disables the dispatcher for its
      // whole lifetime, which is exactly when it captures modifier state.
      final keyboard = ReconciledKeyboard()..attach();
      addTearDown(keyboard.detach);
      final bus = CommandBus();
      final dispatcher = buildWith(bus, keyboard)..enabled = false;

      pressModifier(LogicalKeyboardKey.metaLeft);
      dispatcher.enabled = true;

      // Only passes if the mirror saw the Meta press while disabled.
      expect(dispatcher.handle(keyDown(LogicalKeyboardKey.keyK)), isTrue);
    });
  });

  group('ShortcutDispatcher double Shift', () {
    final searchId = 'workbench.workspace.search';
    final searchCatalog = [
      CommandDefinition(
        id: searchId,
        category: CommandCategory.navigation,
        defaultChords: [
          KeyChord(key: 'f', mods: [KeyChordMod.mod]),
          KeyChord.doubleTapShift(),
        ],
        when: ShortcutWhen.hasWorkspace,
        terminalPassthrough: true,
        titleL10nKey: 'x',
      ),
    ];

    test('double Shift invokes the bound command when hasWorkspace', () {
      final bus = CommandBus();
      var called = false;
      bus.register(searchId, () => called = true);
      final dispatcher = ShortcutDispatcher(
        bus: bus,
        effectiveChords: (id) => searchCatalog
            .firstWhere((def) => def.id == id)
            .defaultChords,
        context: () => const ShortcutContext(hasWorkspace: true),
        isMacOS: () => false,
        catalog: searchCatalog,
      );

      final first = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        logicalKey: LogicalKeyboardKey.shiftLeft,
        timeStamp: Duration.zero,
      );
      final second = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        logicalKey: LogicalKeyboardKey.shiftLeft,
        timeStamp: const Duration(milliseconds: 150),
      );

      expect(dispatcher.handle(first), isFalse);
      expect(dispatcher.handle(second), isTrue);
      expect(called, isTrue);
    });

    test('double Shift is ignored without hasWorkspace', () {
      final bus = CommandBus();
      var called = false;
      bus.register(searchId, () => called = true);
      final dispatcher = ShortcutDispatcher(
        bus: bus,
        effectiveChords: (id) => searchCatalog
            .firstWhere((def) => def.id == id)
            .defaultChords,
        context: () => const ShortcutContext(),
        isMacOS: () => false,
        catalog: searchCatalog,
      );

      expect(
        dispatcher.handle(
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.shiftLeft,
            logicalKey: LogicalKeyboardKey.shiftLeft,
            timeStamp: Duration.zero,
          ),
        ),
        isFalse,
      );
      expect(
        dispatcher.handle(
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.shiftLeft,
            logicalKey: LogicalKeyboardKey.shiftLeft,
            timeStamp: const Duration(milliseconds: 150),
          ),
        ),
        isFalse,
      );
      expect(called, isFalse);
    });
  });
}
