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
}
