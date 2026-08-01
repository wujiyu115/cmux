import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/toolbar_key.dart';
import '../utils/logging/logger_utils.dart';

/// Persisted layout of the mobile terminal toolbar.
@immutable
class MobileToolbarPrefs {
  /// Copies the collections into unmodifiable views so the `@immutable` claim
  /// holds for real: a caller that kept the list/map it passed in and mutated it
  /// later would otherwise rewrite an instance others already hold — including
  /// [InMemoryMobileToolbarRepository.lastSaved], which tests read to prove the
  /// usage debounce coalesced.
  MobileToolbarPrefs({
    required List<String> groupOrder,
    required this.visibleGroupCount,
    required Map<String, int> usage,
  }) : groupOrder = List.unmodifiable(groupOrder),
       usage = Map.unmodifiable(usage);

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

/// Loads and stores the toolbar layout. [load] never throws — missing or corrupt
/// storage resolves to sanitized defaults — so callers need no fallback of their
/// own, and [save] always receives an already-sanitized value.
abstract class MobileToolbarRepository {
  Future<MobileToolbarPrefs> load();
  Future<void> save(MobileToolbarPrefs prefs);
}

/// One versioned JSON blob, like PairingSettingsRepository — except that [save]
/// overwrites [storageKey] outright instead of read-modify-writing it: this key
/// holds nothing but the toolbar layout, so a merge would have no sibling field
/// left to preserve.
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
    } on FormatException catch (e, st) {
      // Silently defaulting hides the one case a user would report: a layout
      // they customized coming back empty.
      AppLogger.instance.w(
        'Discarding unparseable mobile toolbar layout at $storageKey ($e)',
        error: e,
        stackTrace: st,
      );
      return const <String, Object?>{};
    }
  }
}

/// Test double. Sharing the caller's instance is safe because
/// [MobileToolbarPrefs] copies its collections, so [lastSaved] stays the snapshot
/// as-saved even if the caller keeps mutating its own lists.
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
