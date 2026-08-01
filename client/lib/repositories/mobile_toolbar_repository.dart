import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/toolbar_key.dart';

/// Persisted layout of the mobile terminal toolbar.
@immutable
class MobileToolbarPrefs {
  const MobileToolbarPrefs({
    required this.groupOrder,
    required this.visibleGroupCount,
    required this.usage,
  });

  /// Every known group id, in display order.
  final List<String> groupOrder;

  /// How many leading groups the bar shows.
  final int visibleGroupCount;

  /// Tap counts per key id, used to surface the user's most-used keys.
  final Map<String, int> usage;

  MobileToolbarPrefs copyWith({
    List<String>? groupOrder,
    int? visibleGroupCount,
    Map<String, int>? usage,
  }) => MobileToolbarPrefs(
    groupOrder: groupOrder ?? this.groupOrder,
    visibleGroupCount: visibleGroupCount ?? this.visibleGroupCount,
    usage: usage ?? this.usage,
  );

  Map<String, Object?> toJson() => {
    'groupOrder': groupOrder,
    'visibleGroupCount': visibleGroupCount,
    'usage': usage,
  };
}

/// Normalizes anything read from disk (or from a UI mutation) into a usable
/// layout: unknown group ids are dropped, built-in groups that the stored order
/// has never seen are appended at the tail — so shipping a new group does not
/// invalidate an existing user's order — and the visible count is clamped.
MobileToolbarPrefs sanitizeToolbarPrefs({
  Iterable<String>? groupOrder,
  int? visibleGroupCount,
  Map<String, int>? usage,
}) {
  final known = defaultToolbarGroupIds;
  final ordered = <String>[];
  for (final id in groupOrder ?? const <String>[]) {
    if (known.contains(id) && !ordered.contains(id)) ordered.add(id);
  }
  for (final id in known) {
    if (!ordered.contains(id)) ordered.add(id);
  }
  final cleanUsage = <String, int>{};
  (usage ?? const <String, int>{}).forEach((key, count) {
    if (count > 0 && toolbarKeyById(key) != null) cleanUsage[key] = count;
  });
  return MobileToolbarPrefs(
    groupOrder: ordered,
    visibleGroupCount: (visibleGroupCount ?? defaultVisibleToolbarGroupCount)
        .clamp(1, ordered.length),
    usage: cleanUsage,
  );
}

abstract class MobileToolbarRepository {
  Future<MobileToolbarPrefs> load();
  Future<void> save(MobileToolbarPrefs prefs);
}

/// One versioned JSON blob, matching [PairingSettingsRepository]'s shape.
class SharedPrefsMobileToolbarRepository implements MobileToolbarRepository {
  const SharedPrefsMobileToolbarRepository(this._preferences);

  static const storageKey = 'teampilot.mobile_toolbar.v1';

  final SharedPreferences _preferences;

  @override
  Future<MobileToolbarPrefs> load() async {
    final map = _readMap();
    final order = map['groupOrder'];
    final usage = map['usage'];
    return sanitizeToolbarPrefs(
      groupOrder: order is List ? order.whereType<String>() : null,
      visibleGroupCount: map['visibleGroupCount'] is int
          ? map['visibleGroupCount'] as int
          : null,
      usage: usage is Map
          ? {
              for (final e in usage.entries)
                if (e.key is String && e.value is int)
                  e.key as String: e.value as int,
            }
          : null,
    );
  }

  @override
  Future<void> save(MobileToolbarPrefs prefs) =>
      _preferences.setString(storageKey, jsonEncode(prefs.toJson()));

  Map<String, Object?> _readMap() {
    final stored = _preferences.getString(storageKey);
    if (stored == null || stored.isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return const <String, Object?>{};
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      return const <String, Object?>{};
    }
  }
}

class InMemoryMobileToolbarRepository implements MobileToolbarRepository {
  InMemoryMobileToolbarRepository({MobileToolbarPrefs? initial})
    : _prefs = initial ?? sanitizeToolbarPrefs();

  MobileToolbarPrefs _prefs;

  /// Number of [save] calls — lets tests assert the usage debounce coalesces.
  int saveCount = 0;

  MobileToolbarPrefs? lastSaved;

  @override
  Future<MobileToolbarPrefs> load() async => _prefs;

  @override
  Future<void> save(MobileToolbarPrefs prefs) async {
    _prefs = prefs;
    lastSaved = prefs;
    saveCount++;
  }
}
