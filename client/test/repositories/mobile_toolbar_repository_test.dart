import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/models/toolbar_key.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  group('sanitizeToolbarPrefs', () {
    test('defaults to the built-in order and count', () {
      final p = sanitizeToolbarPrefs();
      expect(p.groupOrder, defaultToolbarGroupIds);
      expect(p.visibleGroupCount, defaultVisibleToolbarGroupCount);
      expect(p.usage, isEmpty);
    });

    test('drops unknown ids, dedupes, appends missing groups at the tail', () {
      final p = sanitizeToolbarPrefs(
        groupOrder: ['signals', 'bogus', 'signals', 'arrows'],
      );
      expect(p.groupOrder.take(2), ['signals', 'arrows']);
      expect(p.groupOrder.length, defaultToolbarGroupIds.length);
      expect(p.groupOrder.toSet().length, p.groupOrder.length);
      expect(p.groupOrder, containsAll(defaultToolbarGroupIds));
    });

    test('clamps the visible count into 1..groups', () {
      expect(sanitizeToolbarPrefs(visibleGroupCount: 0).visibleGroupCount, 1);
      expect(
        sanitizeToolbarPrefs(visibleGroupCount: 99).visibleGroupCount,
        defaultToolbarGroupIds.length,
      );
    });

    test('drops usage entries for unknown keys and non-positive counts', () {
      final p = sanitizeToolbarPrefs(
        usage: {'ctrl_c': 3, 'ghost': 9, 'esc': 0},
      );
      expect(p.usage, {'ctrl_c': 3});
    });

    test('returned collections are unmodifiable and detached from the input',
        () {
      final order = ['signals', 'arrows'];
      final usage = {'ctrl_c': 3};
      final p = sanitizeToolbarPrefs(groupOrder: order, usage: usage);
      expect(() => p.groupOrder.add('arrows'), throwsUnsupportedError);
      expect(() => p.usage['esc'] = 1, throwsUnsupportedError);
      order.clear();
      usage.clear();
      expect(p.groupOrder.take(2), ['signals', 'arrows']);
      expect(p.usage, {'ctrl_c': 3});
    });
  });

  group('MobileToolbarPrefs.copyWith', () {
    test('replaces one field, keeps the rest, leaves the original alone', () {
      final original = sanitizeToolbarPrefs(
        groupOrder: ['signals'],
        visibleGroupCount: 3,
        usage: {'esc': 2},
      );
      final copy = original.copyWith(visibleGroupCount: 5);
      expect(copy.visibleGroupCount, 5);
      expect(copy.groupOrder, original.groupOrder);
      expect(copy.usage, {'esc': 2});
      expect(original.visibleGroupCount, 3);

      final reordered = original.copyWith(groupOrder: ['arrows']);
      expect(reordered.groupOrder, ['arrows']);
      expect(reordered.visibleGroupCount, 3);
      expect(reordered.usage, {'esc': 2});
      expect(original.groupOrder.first, 'signals');
    });
  });

  group('SharedPrefsMobileToolbarRepository', () {
    test('load on a fresh install returns sanitized defaults', () async {
      final repo = SharedPrefsMobileToolbarRepository(await prefsWith({}));
      final p = await repo.load();
      expect(p.groupOrder, defaultToolbarGroupIds);
      expect(p.visibleGroupCount, 4);
    });

    test('save then load round-trips', () async {
      final prefs = await prefsWith({});
      final repo = SharedPrefsMobileToolbarRepository(prefs);
      await repo.save(sanitizeToolbarPrefs(
        groupOrder: ['fkeys1', 'arrows'],
        visibleGroupCount: 6,
        usage: {'f1': 2},
      ));
      final loaded = await SharedPrefsMobileToolbarRepository(prefs).load();
      expect(loaded.groupOrder.take(2), ['fkeys1', 'arrows']);
      expect(loaded.visibleGroupCount, 6);
      expect(loaded.usage, {'f1': 2});
    });

    test('corrupt json falls back to defaults instead of throwing', () async {
      final repo = SharedPrefsMobileToolbarRepository(await prefsWith({
        SharedPrefsMobileToolbarRepository.storageKey: 'not json {',
      }));
      final p = await repo.load();
      expect(p.groupOrder, defaultToolbarGroupIds);
    });

    test('stored blob shape is the documented three keys', () async {
      final prefs = await prefsWith({});
      await SharedPrefsMobileToolbarRepository(prefs)
          .save(sanitizeToolbarPrefs(usage: {'esc': 1}));
      final raw =
          prefs.getString(SharedPrefsMobileToolbarRepository.storageKey)!;
      expect(
        (jsonDecode(raw) as Map).keys.toSet(),
        {'groupOrder', 'visibleGroupCount', 'usage'},
      );
    });
  });

  group('InMemoryMobileToolbarRepository', () {
    test('records saves', () async {
      final repo = InMemoryMobileToolbarRepository();
      expect((await repo.load()).groupOrder, defaultToolbarGroupIds);
      await repo.save(sanitizeToolbarPrefs(visibleGroupCount: 9));
      expect(repo.saveCount, 1);
      expect(repo.lastSaved!.visibleGroupCount, 9);
    });

    test('load returns the seeded initial value', () async {
      final initial = sanitizeToolbarPrefs(
        groupOrder: ['signals'],
        visibleGroupCount: 2,
        usage: {'esc': 4},
      );
      final repo = InMemoryMobileToolbarRepository(initial: initial);
      final loaded = await repo.load();
      expect(loaded.groupOrder.first, 'signals');
      expect(loaded.visibleGroupCount, 2);
      expect(loaded.usage, {'esc': 4});
      expect(repo.saveCount, 0);
      expect(repo.lastSaved, isNull);
    });
  });
}
