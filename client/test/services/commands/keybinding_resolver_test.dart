import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/command_definition.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/keybinding_resolver.dart';
import 'package:teampilot/services/commands/shortcut_context.dart';

PhysicalKeyboardKey _physicalFor(LogicalKeyboardKey logicalKey) {
  return switch (logicalKey) {
    LogicalKeyboardKey.enter => PhysicalKeyboardKey.enter,
    LogicalKeyboardKey.tab => PhysicalKeyboardKey.tab,
    LogicalKeyboardKey.controlLeft => PhysicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.shiftLeft => PhysicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.metaLeft => PhysicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.altLeft => PhysicalKeyboardKey.altLeft,
    LogicalKeyboardKey.keyW => PhysicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyK => PhysicalKeyboardKey.keyK,
    LogicalKeyboardKey.digit1 => PhysicalKeyboardKey.digit1,
    LogicalKeyboardKey.f5 => PhysicalKeyboardKey.f5,
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
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.altLeft,
    ]) {
      if (HardwareKeyboard.instance.isLogicalKeyPressed(key)) {
        releaseModifier(key);
      }
    }
  });

  group('KeybindingResolver.effectiveBindings', () {
    final catalog = [
      CommandDefinition(
        id: 'test.a',
        category: CommandCategory.meta,
        defaultChords: [KeyChord(key: 'a', mods: [KeyChordMod.mod])],
        when: ShortcutWhen.always,
        terminalPassthrough: true,
        titleL10nKey: 'x',
      ),
    ];

    test('missing override falls back to default chords', () {
      final effective = KeybindingResolver.effectiveBindings(
        catalog: catalog,
        overrides: {},
      );

      expect(effective['test.a'], catalog.single.defaultChords);
    });

    test('explicit empty override means unbound', () {
      final effective = KeybindingResolver.effectiveBindings(
        catalog: catalog,
        overrides: {'test.a': []},
      );

      expect(effective['test.a'], isEmpty);
    });

    test('non-empty override replaces the default', () {
      final overrideChord = KeyChord(key: 'b', mods: [KeyChordMod.mod]);
      final effective = KeybindingResolver.effectiveBindings(
        catalog: catalog,
        overrides: {
          'test.a': [overrideChord],
        },
      );

      expect(effective['test.a'], [overrideChord]);
    });
  });

  group('KeybindingResolver.match', () {
    late Map<String, List<KeyChord>> effective;

    setUp(() {
      effective = KeybindingResolver.effectiveBindings(
        catalog: CommandCatalog.v1,
        overrides: {},
      );
    });

    test('Ctrl+Tab matches stripNextTab when hasWorkspace', () {
      pressModifier(LogicalKeyboardKey.controlLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.tab),
        effectiveByCommand: effective,
        context: const ShortcutContext(hasWorkspace: true),
        isMacOS: false,
      );

      expect(result, CommandIds.stripNextTab);
    });

    test('ignored when `when` is unsatisfied', () {
      pressModifier(LogicalKeyboardKey.controlLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.tab),
        effectiveByCommand: effective,
        context: const ShortcutContext(),
        isMacOS: false,
      );

      expect(result, isNull);
    });

    test(
      'ignored when inTerminal and terminalPassthrough is false',
      () {
        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.enter),
          effectiveByCommand: effective,
          context: const ShortcutContext(inTerminal: true, inCompose: true),
          isMacOS: false,
        );

        expect(result, isNull);
      },
    );

    test('allowed when inTerminal and terminalPassthrough is true', () {
      pressModifier(LogicalKeyboardKey.controlLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.tab),
        effectiveByCommand: effective,
        context: const ShortcutContext(hasWorkspace: true, inTerminal: true),
        isMacOS: false,
      );

      expect(result, CommandIds.stripNextTab);
    });

    test('bare Enter is ignored when not inCompose', () {
      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.enter),
        effectiveByCommand: effective,
        context: const ShortcutContext(),
        isMacOS: false,
      );

      expect(result, isNull);
    });

    test('bare Enter matches composeSubmit when inCompose', () {
      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.enter),
        effectiveByCommand: effective,
        context: const ShortcutContext(inCompose: true),
        isMacOS: false,
      );

      expect(result, CommandIds.composeSubmit);
    });

    group('inTerminal bare chords', () {
      test('bare F5 does not steal the key from the PTY', () {
        // runRunSelected is terminalPassthrough with a modifier-less F5
        // default, and a focused terminal is inTerminal / NOT inTextInput —
        // so before this guard it fired into the shell.
        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.f5),
          effectiveByCommand: effective,
          context: const ShortcutContext(hasWorkspace: true, inTerminal: true),
          isMacOS: false,
        );

        expect(result, isNull);
      });

      test('bare F5 still runs when no terminal has focus', () {
        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.f5),
          effectiveByCommand: effective,
          context: const ShortcutContext(hasWorkspace: true),
          isMacOS: false,
        );

        expect(result, CommandIds.runRunSelected);
      });

      test('a modifier chord still fires in a terminal (Ctrl+Tab)', () {
        pressModifier(LogicalKeyboardKey.controlLeft);
        addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.tab),
          effectiveByCommand: effective,
          context: const ShortcutContext(hasWorkspace: true, inTerminal: true),
          isMacOS: false,
        );

        expect(result, CommandIds.stripNextTab);
      });
    });

    group('inTextInput', () {
      test('modifier chord still matches (Mod+W closes session tab)', () {
        pressModifier(LogicalKeyboardKey.metaLeft);
        addTearDown(() => releaseModifier(LogicalKeyboardKey.metaLeft));

        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.keyW),
          effectiveByCommand: effective,
          context: const ShortcutContext(
            inTextInput: true,
            hasSessionTab: true,
          ),
          isMacOS: true,
        );

        expect(result, CommandIds.sessionCloseTab);
      });

      test('unmodified key never matches, even with when: always', () {
        final catalog = [
          CommandDefinition(
            id: 'test.bareAlways',
            category: CommandCategory.meta,
            defaultChords: [KeyChord(key: 'k')],
            when: ShortcutWhen.always,
            terminalPassthrough: true,
            titleL10nKey: 'x',
          ),
        ];
        final bareEffective = KeybindingResolver.effectiveBindings(
          catalog: catalog,
          overrides: {},
        );

        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.keyK),
          effectiveByCommand: bareEffective,
          context: const ShortcutContext(inTextInput: true),
          isMacOS: false,
          catalog: catalog,
        );

        expect(result, isNull);
      });

      test('compose Enter still matches when inTextInput and inCompose', () {
        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.enter),
          effectiveByCommand: effective,
          context: const ShortcutContext(inTextInput: true, inCompose: true),
          isMacOS: false,
        );

        expect(result, CommandIds.composeSubmit);
      });
    });

    group('stuck Alt', () {
      /// A keyboard with no keys held — models the mirror after a
      /// window-focus clear.
      HardwareKeyboard cleanKeyboard() => HardwareKeyboard();

      /// A keyboard that genuinely has Alt held.
      HardwareKeyboard altHeldKeyboard() =>
          HardwareKeyboard()..handleKeyEvent(keyDown(LogicalKeyboardKey.altLeft));

      test('bare digit does not hop tabs when only the framework thinks Alt '
          'is down', () {
        // The bug: Windows Alt+Tab strands the Alt key-up in another window,
        // so HardwareKeyboard.instance reports Alt forever and a bare `1`
        // satisfies SingleActivator(digit1, alt: true).
        pressModifier(LogicalKeyboardKey.altLeft);
        addTearDown(() => releaseModifier(LogicalKeyboardKey.altLeft));

        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.digit1),
          effectiveByCommand: effective,
          context: const ShortcutContext(hasWorkspace: true, inTerminal: true),
          isMacOS: false,
          keyboardState: cleanKeyboard(),
        );

        expect(result, isNull);
      });

      test('a real Alt+1 still focuses strip tab 1', () {
        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.digit1),
          effectiveByCommand: effective,
          context: const ShortcutContext(hasWorkspace: true, inTerminal: true),
          isMacOS: false,
          keyboardState: altHeldKeyboard(),
        );

        expect(result, CommandIds.stripFocusTab(1));
      });

      test('omitting keyboardState falls back to the reconciled instance', () {
        // The default path used by every pre-existing caller: unattached, so
        // ReconciledKeyboard.state defers to HardwareKeyboard.instance.
        pressModifier(LogicalKeyboardKey.altLeft);
        addTearDown(() => releaseModifier(LogicalKeyboardKey.altLeft));

        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.digit1),
          effectiveByCommand: effective,
          context: const ShortcutContext(hasWorkspace: true, inTerminal: true),
          isMacOS: false,
        );

        expect(result, CommandIds.stripFocusTab(1));
      });
    });

    test('duplicate chord across commands: first catalog order wins', () {
      final sharedChord = KeyChord(key: 'k', mods: [KeyChordMod.mod]);
      final catalog = [
        CommandDefinition(
          id: 'test.first',
          category: CommandCategory.meta,
          defaultChords: [sharedChord],
          when: ShortcutWhen.always,
          terminalPassthrough: true,
          titleL10nKey: 'x',
        ),
        CommandDefinition(
          id: 'test.second',
          category: CommandCategory.meta,
          defaultChords: [sharedChord],
          when: ShortcutWhen.always,
          terminalPassthrough: true,
          titleL10nKey: 'y',
        ),
      ];
      final dupEffective = KeybindingResolver.effectiveBindings(
        catalog: catalog,
        overrides: {},
      );

      pressModifier(LogicalKeyboardKey.metaLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.metaLeft));

      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.keyK),
        effectiveByCommand: dupEffective,
        context: const ShortcutContext(),
        isMacOS: true,
        catalog: catalog,
      );

      expect(result, 'test.first');
    });
  });

  group('KeybindingResolver.findConflicts', () {
    test('returns pairs sharing a chord', () {
      final sharedChord = KeyChord(key: 'k', mods: [KeyChordMod.mod]);
      final conflicts = KeybindingResolver.findConflicts({
        'a': [sharedChord],
        'b': [sharedChord],
        'c': [KeyChord(key: 'l')],
      });

      expect(conflicts, hasLength(1));
      expect(conflicts.single.chord, sharedChord);
      expect(conflicts.single.commandIds, unorderedEquals(['a', 'b']));
    });

    test('returns empty list when no chords are shared', () {
      final conflicts = KeybindingResolver.findConflicts({
        'a': [KeyChord(key: 'k', mods: [KeyChordMod.mod])],
        'b': [KeyChord(key: 'l')],
      });

      expect(conflicts, isEmpty);
    });
  });
}
