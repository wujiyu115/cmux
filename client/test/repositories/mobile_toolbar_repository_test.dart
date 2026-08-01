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
      expect(sanitizeToolbarPrefs(visibleGroupCount: 99).visibleGroupCount, 16);
    });

    test('drops usage entries for unknown keys and non-positive counts', () {
      final p = sanitizeToolbarPrefs(
        usage: {'ctrl_c': 3, 'ghost': 9, 'esc': 0},
      );
      expect(p.usage, {'ctrl_c': 3});
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
        (jsonDecode(raw) as Map).keys,
        containsAll(['groupOrder', 'visibleGroupCount', 'usage']),
      );
    });
  });

  test('InMemoryMobileToolbarRepository records saves', () async {
    final repo = InMemoryMobileToolbarRepository();
    expect((await repo.load()).groupOrder, defaultToolbarGroupIds);
    await repo.save(sanitizeToolbarPrefs(visibleGroupCount: 9));
    expect(repo.saveCount, 1);
    expect(repo.lastSaved!.visibleGroupCount, 9);
  });
}
