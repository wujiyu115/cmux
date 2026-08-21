import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mobile_toolbar_cubit.dart';
import 'package:teampilot/models/toolbar_key.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';

/// Holds [load] open so a test can close the cubit while the read is still in
/// flight — the race the `isClosed` guard exists for.
class _BlockingLoadRepository implements MobileToolbarRepository {
  final loadGate = Completer<MobileToolbarPrefs>();

  @override
  Future<MobileToolbarPrefs> load() => loadGate.future;

  @override
  Future<void> save(MobileToolbarPrefs prefs) async {}
}

void main() {
  late List<List<int>> sent;
  late InMemoryMobileToolbarRepository repo;

  MobileToolbarCubit build({String? clipboard, Duration? usageFlushDelay}) =>
      MobileToolbarCubit(
        repository: repo,
        sendInput: sent.add,
        readClipboard: () async => clipboard,
        usageFlushDelay: usageFlushDelay ?? const Duration(seconds: 1),
      );

  ToolbarKey key(String id) => toolbarKeyById(id)!;

  setUp(() {
    sent = [];
    repo = InMemoryMobileToolbarRepository();
  });

  test('load hydrates order and visible count from the repository', () async {
    repo = InMemoryMobileToolbarRepository(
      initial: sanitizeToolbarPrefs(
        groupOrder: ['signals'],
        visibleGroupCount: 2,
      ),
    );
    final cubit = build();
    await cubit.load();
    expect(cubit.state.groupOrder.first, 'signals');
    expect(cubit.state.visibleGroupCount, 2);
    expect(cubit.state.visibleGroups.map((g) => g.id).toList(), [
      'signals',
      'arrows',
    ]);
    await cubit.close();
  });

  test('load resolving after close does not emit', () async {
    final blocking = _BlockingLoadRepository();
    final cubit = MobileToolbarCubit(
      repository: blocking,
      sendInput: sent.add,
      readClipboard: () async => null,
    );
    final pending = cubit.load();
    await cubit.close();
    blocking.loadGate.complete(sanitizeToolbarPrefs());
    await expectLater(pending, completes);
  });

  test('a plain key sends its bytes and counts usage', () async {
    final cubit = build();
    await cubit.tapKey(key('ctrl_c'));
    expect(sent, [[0x03]]);
    expect(cubit.state.usage['ctrl_c'], 1);
    await cubit.close();
  });

  test('sent bytes are unmodifiable, so the key table cannot be corrupted', () async {
    final cubit = build();
    await cubit.tapKey(key('ctrl_c'));
    expect(() => sent.single.add(0x00), throwsUnsupportedError);
    expect(key('ctrl_c').bytes, [0x03], reason: 'global key table intact');
    await cubit.close();
  });

  test('state collections are unmodifiable', () async {
    final cubit = build();
    await cubit.load();
    expect(() => cubit.state.groupOrder.removeAt(0), throwsUnsupportedError);
    await cubit.tapKey(key('esc'));
    expect(() => cubit.state.usage.clear(), throwsUnsupportedError);
    await cubit.close();
  });

  test('Ctrl and Alt are mutually exclusive and one-shot', () async {
    final cubit = build();
    await cubit.tapKey(key('ctrl'));
    expect(cubit.state.ctrl, isTrue);
    await cubit.tapKey(key('alt'));
    expect(cubit.state.ctrl, isFalse);
    expect(cubit.state.alt, isTrue);
    await cubit.tapKey(key('slash')); // Alt+/
    expect(sent, [[0x1b, 0x2f]]);
    expect(cubit.state.alt, isFalse, reason: 'modifier must reset after use');
    await cubit.tapKey(key('slash'));
    expect(sent.last, [0x2f]);
    await cubit.close();
  });

  test('Ctrl rewrites an arrow into the xterm modifier form', () async {
    final cubit = build();
    await cubit.tapKey(key('ctrl'));
    await cubit.tapKey(key('arrow_up'));
    expect(sent, [[0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x41]]);
    await cubit.close();
  });

  test('modifier keys are not counted as usage', () async {
    final cubit = build();
    await cubit.tapKey(key('ctrl'));
    await cubit.tapKey(key('alt'));
    expect(cubit.state.usage, isEmpty);
    await cubit.close();
  });

  test('paste normalizes newlines to CR, bypasses modifiers and usage', () async {
    final cubit = build(clipboard: 'echo a\nls\r\n');
    await cubit.tapKey(key('ctrl'));
    await cubit.tapKey(key('paste'));
    expect(String.fromCharCodes(sent.single), 'echo a\rls\r');
    expect(cubit.state.usage, isEmpty);
    expect(cubit.state.ctrl, isTrue, reason: 'paste must not consume Ctrl');
    await cubit.close();
  });

  test('empty or missing clipboard sends nothing', () async {
    final cubit = build(clipboard: null);
    await cubit.tapKey(key('paste'));
    final empty = build(clipboard: '');
    await empty.tapKey(key('paste'));
    expect(sent, isEmpty);
    await cubit.close();
    await empty.close();
  });

  test('reorder and visible count persist immediately', () async {
    final cubit = build();
    await cubit.load();
    await cubit.reorderGroups(3, 0); // signals to the front
    expect(cubit.state.groupOrder.first, 'signals');
    expect(repo.lastSaved!.groupOrder.first, 'signals');
    await cubit.setVisibleGroupCount(7);
    expect(repo.lastSaved!.visibleGroupCount, 7);
    await cubit.setVisibleGroupCount(999);
    expect(cubit.state.visibleGroupCount, 16, reason: 'clamped');
    await cubit.close();
  });

  test('reorderGroups takes a post-removal newIndex', () async {
    final cubit = build();
    await cubit.load();
    expect(cubit.state.groupOrder.take(4), [
      'arrows',
      'clipboard',
      'terminal_ctrl',
      'signals',
    ]);
    // Downward move: 'arrows' lands at index 3, the index it occupies once it has
    // been removed. ReorderableListView would report 4 for the same gesture.
    await cubit.reorderGroups(0, 3);
    expect(cubit.state.groupOrder.take(4), [
      'clipboard',
      'terminal_ctrl',
      'signals',
      'arrows',
    ]);
    await cubit.close();
  });

  test('resetLayout restores built-in order and count, keeps usage', () async {
    final cubit = build();
    await cubit.load();
    await cubit.tapKey(key('esc'));
    await cubit.reorderGroups(5, 0);
    await cubit.resetLayout();
    expect(cubit.state.groupOrder, defaultToolbarGroupIds);
    expect(cubit.state.visibleGroupCount, defaultVisibleToolbarGroupCount);
    expect(cubit.state.usage['esc'], 1);
    expect(repo.lastSaved!.groupOrder, defaultToolbarGroupIds);
    expect(repo.lastSaved!.visibleGroupCount, defaultVisibleToolbarGroupCount);
    expect(repo.lastSaved!.usage['esc'], 1);
    await cubit.close();
  });

  test('mostUsedKeys ranks by tap count, highest first', () async {
    final cubit = build();
    await cubit.tapKey(key('esc'));
    await cubit.tapKey(key('tab'));
    await cubit.tapKey(key('tab'));
    expect(cubit.state.mostUsedKeys.map((k) => k.id).take(2), ['tab', 'esc']);
    await cubit.close();
  });

  test('usage writes are debounced into a single save', () {
    fakeAsync((async) {
      final cubit = build();
      cubit.tapKey(key('esc'));
      cubit.tapKey(key('esc'));
      cubit.tapKey(key('tab'));
      async.flushMicrotasks();
      expect(repo.saveCount, 0, reason: 'not written yet');
      async.elapse(const Duration(milliseconds: 999));
      async.flushMicrotasks();
      expect(repo.saveCount, 0, reason: 'still inside the 1s window');
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(repo.saveCount, 1);
      expect(repo.lastSaved!.usage, {'esc': 2, 'tab': 1});
      cubit.close();
      async.flushMicrotasks();
    });
  });

  test('a custom usageFlushDelay is honored', () {
    fakeAsync((async) {
      final cubit = build(usageFlushDelay: const Duration(milliseconds: 50));
      cubit.tapKey(key('esc'));
      async.elapse(const Duration(milliseconds: 49));
      async.flushMicrotasks();
      expect(repo.saveCount, 0, reason: 'still inside the 50ms window');
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(repo.saveCount, 1);
      cubit.close();
      async.flushMicrotasks();
    });
  });

  test('close flushes a pending usage write', () async {
    final cubit = build();
    await cubit.tapKey(key('esc'));
    expect(repo.saveCount, 0);
    await cubit.close();
    expect(repo.saveCount, 1);
    expect(repo.lastSaved!.usage, {'esc': 1});
  });

  test('close does not re-save an already flushed usage write', () {
    fakeAsync((async) {
      final cubit = build();
      cubit.tapKey(key('esc'));
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(repo.saveCount, 1);
      cubit.close();
      async.flushMicrotasks();
      expect(repo.saveCount, 1, reason: 'nothing pending, nothing to write');
    });
  });

  group('consumeModifiers', () {
    test('applies an armed Ctrl to a soft-keyboard byte and consumes it',
        () async {
      final cubit = build();
      await cubit.tapKey(key('ctrl'));
      expect(cubit.consumeModifiers([0x63]), [0x03]); // Ctrl+C
      expect(cubit.state.ctrl, isFalse);
      expect(cubit.consumeModifiers([0x63]), [0x63], reason: 'one-shot');
      await cubit.close();
    });

    test('applies an armed Alt as an ESC prefix and consumes it', () async {
      final cubit = build();
      await cubit.tapKey(key('alt'));
      expect(cubit.consumeModifiers([0x62]), [0x1b, 0x62]); // Alt+b
      expect(cubit.state.alt, isFalse);
      await cubit.close();
    });

    test('no modifier armed passes the caller list through untouched',
        () async {
      final cubit = build();
      final bytes = [0x6c];
      expect(identical(cubit.consumeModifiers(bytes), bytes), isTrue);
      await cubit.close();
    });

    test('multi-byte frames pass through but still consume the modifier',
        () async {
      // The engine output also carries mouse reports, bracketed paste and UTF-8;
      // applying Ctrl there would rewrite them into nonsense chords.
      final cubit = build();
      await cubit.tapKey(key('ctrl'));
      final frame = [0x1b, 0x5b, 0x4d]; // xterm mouse report prefix
      expect(identical(cubit.consumeModifiers(frame), frame), isTrue);
      expect(cubit.state.ctrl, isFalse, reason: 'dropped, not carried over');
      await cubit.close();
    });
  });

  group('composer', () {
    test('starts in key mode with Return-mode on', () async {
      final cubit = build();
      expect(cubit.state.mode, MobileInputMode.keys);
      expect(cubit.state.chatMode, isTrue);
      await cubit.close();
    });

    test('toggleComposer flips between the two panels', () async {
      final cubit = build();
      cubit.toggleComposer();
      expect(cubit.state.mode, MobileInputMode.composer);
      cubit.toggleComposer();
      expect(cubit.state.mode, MobileInputMode.keys);
      await cubit.close();
    });

    test('setMode to the current mode does not emit', () async {
      final cubit = build();
      final seen = <MobileInputMode>[];
      final sub = cubit.stream.listen((s) => seen.add(s.mode));
      cubit.setMode(MobileInputMode.keys);
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
      cubit.setMode(MobileInputMode.composer);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [MobileInputMode.composer]);
      await sub.cancel();
      await cubit.close();
    });

    test('toggleChatMode flips the flag', () async {
      final cubit = build();
      cubit.toggleChatMode();
      expect(cubit.state.chatMode, isFalse);
      cubit.toggleChatMode();
      expect(cubit.state.chatMode, isTrue);
      await cubit.close();
    });

    test('sendText appends CR only when submitting', () async {
      final cubit = build();
      cubit.sendText('ls', submit: true);
      cubit.sendText('ls', submit: false);
      expect(sent, [
        [0x6c, 0x73, 0x0d],
        [0x6c, 0x73],
      ]);
      await cubit.close();
    });

    test('sendText rewrites newlines to CR so each line runs', () async {
      final cubit = build();
      cubit.sendText('a\nb', submit: false);
      expect(String.fromCharCodes(sent.single), 'a\rb');
      await cubit.close();
    });

    test('empty text sends a bare CR when submitting, nothing otherwise', () async {
      final cubit = build();
      cubit.sendText('', submit: false);
      expect(sent, isEmpty);
      cubit.sendText('', submit: true);
      expect(sent, [[0x0d]]);
      await cubit.close();
    });

    test('whitespace is real input, not emptiness', () async {
      final cubit = build();
      cubit.sendText('  ', submit: false);
      expect(sent, [[0x20, 0x20]]);
      await cubit.close();
    });

    test('sendText ignores modifiers and does not consume them', () async {
      final cubit = build();
      await cubit.tapKey(key('ctrl'));
      cubit.sendText('a', submit: false);
      expect(sent, [[0x61]], reason: 'Ctrl must not mask composer text');
      expect(cubit.state.ctrl, isTrue, reason: 'and must survive the send');
      expect(cubit.state.usage, isEmpty, reason: 'text is not a key tap');
      await cubit.close();
    });

    test('sent bytes are unmodifiable', () async {
      final cubit = build();
      cubit.sendText('a', submit: true);
      expect(() => sent.single.add(0x00), throwsUnsupportedError);
      await cubit.close();
    });
  });
}
