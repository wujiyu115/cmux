import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class AppSettingsRepository {
  Future<String?> loadLlmConfigPathOverride();
  Future<void> saveLlmConfigPathOverride(String? path);

  Future<bool> loadHasCompletedOnboarding();
  Future<void> saveHasCompletedOnboarding(bool value);

  /// Whether to silently check GitHub Releases for updates on app startup.
  /// Defaults to `true` when the user has not made a choice.
  Future<bool> loadAutoCheckUpdatesEnabled();
  Future<void> saveAutoCheckUpdatesEnabled(bool value);

  /// The release version the user chose to skip, so the startup prompt is not
  /// shown again for it. `null` once a newer version supersedes it.
  Future<String?> loadSkippedUpdateVersion();
  Future<void> saveSkippedUpdateVersion(String? version);

}

class SharedPrefsAppSettingsRepository implements AppSettingsRepository {
  const SharedPrefsAppSettingsRepository(this._preferences);

  static const storageKey = 'teampilot.app_settings.v1';
  static const _llmConfigPathKey = 'llmConfigPath';
  static const _hasCompletedOnboardingKey = 'hasCompletedOnboarding';
  static const _autoCheckUpdatesKey = 'autoCheckUpdates';
  static const _skippedUpdateVersionKey = 'skippedUpdateVersion';

  final SharedPreferences _preferences;

  @override
  Future<String?> loadLlmConfigPathOverride() async {
    final stored = _preferences.getString(storageKey);
    if (stored == null || stored.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return null;
      final value = decoded[_llmConfigPathKey];
      if (value is String && value.isNotEmpty) return value;
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveLlmConfigPathOverride(String? path) async {
    final current = _readMap();
    if (path == null || path.trim().isEmpty) {
      current.remove(_llmConfigPathKey);
    } else {
      current[_llmConfigPathKey] = path;
    }
    await _writeMap(current);
  }

  @override
  Future<bool> loadHasCompletedOnboarding() async {
    final value = _readMap()[_hasCompletedOnboardingKey];
    return value == true;
  }

  @override
  Future<void> saveHasCompletedOnboarding(bool value) async {
    final current = _readMap();
    current[_hasCompletedOnboardingKey] = value;
    await _writeMap(current);
  }

  @override
  Future<bool> loadAutoCheckUpdatesEnabled() async {
    final value = _readMap()[_autoCheckUpdatesKey];
    // Opt-out: enabled unless explicitly turned off.
    return value != false;
  }

  @override
  Future<void> saveAutoCheckUpdatesEnabled(bool value) async {
    final current = _readMap();
    current[_autoCheckUpdatesKey] = value;
    await _writeMap(current);
  }

  @override
  Future<String?> loadSkippedUpdateVersion() async {
    final value = _readMap()[_skippedUpdateVersionKey];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  @override
  Future<void> saveSkippedUpdateVersion(String? version) async {
    final current = _readMap();
    final trimmed = version?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      current.remove(_skippedUpdateVersionKey);
    } else {
      current[_skippedUpdateVersionKey] = trimmed;
    }
    await _writeMap(current);
  }

  Future<void> _writeMap(Map<String, Object?> current) async {
    if (current.isEmpty) {
      await _preferences.remove(storageKey);
    } else {
      await _preferences.setString(storageKey, jsonEncode(current));
    }
  }

  Map<String, Object?> _readMap() {
    final stored = _preferences.getString(storageKey);
    if (stored == null || stored.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return <String, Object?>{};
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      return <String, Object?>{};
    }
  }
}

/// Test-friendly in-memory implementation.
class InMemoryAppSettingsRepository implements AppSettingsRepository {
  InMemoryAppSettingsRepository({
    String? llmConfigPathOverride,
    bool hasCompletedOnboarding = false,
    bool autoCheckUpdatesEnabled = true,
    String? skippedUpdateVersion,
  }) : _llmConfigPathOverride = llmConfigPathOverride,
       _hasCompletedOnboarding = hasCompletedOnboarding,
       _autoCheckUpdatesEnabled = autoCheckUpdatesEnabled,
       _skippedUpdateVersion = skippedUpdateVersion;

  String? _llmConfigPathOverride;
  bool _hasCompletedOnboarding;
  bool _autoCheckUpdatesEnabled;
  String? _skippedUpdateVersion;

  @override
  Future<String?> loadLlmConfigPathOverride() async => _llmConfigPathOverride;

  @override
  Future<void> saveLlmConfigPathOverride(String? path) async {
    final trimmed = path?.trim();
    _llmConfigPathOverride = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
  }

  @override
  Future<bool> loadHasCompletedOnboarding() async => _hasCompletedOnboarding;

  @override
  Future<void> saveHasCompletedOnboarding(bool value) async {
    _hasCompletedOnboarding = value;
  }

  @override
  Future<bool> loadAutoCheckUpdatesEnabled() async => _autoCheckUpdatesEnabled;

  @override
  Future<void> saveAutoCheckUpdatesEnabled(bool value) async {
    _autoCheckUpdatesEnabled = value;
  }

  @override
  Future<String?> loadSkippedUpdateVersion() async => _skippedUpdateVersion;

  @override
  Future<void> saveSkippedUpdateVersion(String? version) async {
    final trimmed = version?.trim();
    _skippedUpdateVersion = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
  }
}
