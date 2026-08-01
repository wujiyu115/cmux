import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mobile_toolbar_cubit.dart';
import 'package:teampilot/models/toolbar_key.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';

void main() {
  late List<List<int>> sent;
  late InMemoryMobileToolbarRepository repo;

  MobileToolbarCubit build({String? clipboard}) => MobileToolbarCubit(
    repository: repo,
    sendInput: sent.add,
    readClipboard: () async => clipboard,
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
    expect(cubit.state.visibleGroups.map((g) => g.id).length, 2);
    await cubit.close();
  });

  test('a plain key sends its bytes and counts usage', () async {
    final cubit = build();
    await cubit.tapKey(key('ctrl_c'));
    expect(sent, [[0x03]]);
    expect(cubit.state.usage['ctrl_c'], 1);
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

  test('resetLayout restores built-in order and count, keeps usage', () async {
    final cubit = build();
    await cubit.load();
    await cubit.tapKey(key('esc'));
    await cubit.reorderGroups(5, 0);
    await cubit.resetLayout();
    expect(cubit.state.groupOrder, defaultToolbarGroupIds);
    expect(cubit.state.visibleGroupCount, defaultVisibleToolbarGroupCount);
    expect(cubit.state.usage['esc'], 1);
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
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(repo.saveCount, 1);
      expect(repo.lastSaved!.usage, {'esc': 2, 'tab': 1});
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
}
