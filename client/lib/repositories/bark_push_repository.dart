import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bark_push_settings.dart';
import '../utils/logging/logger.dart';
import 'ssh_credential_store.dart';

/// Loads and stores the Bark push channel: [BarkPushSettings] as one JSON blob
/// in [SharedPreferences], the device key in the keychain.
///
/// Split for the same reason as `VoiceInputRepository`: the key is a bearer
/// capability for pushing to someone's phone, so it must not sit in a
/// world-readable preferences file next to the window size.
abstract class BarkPushRepository {
  Future<BarkPushSettings> loadSettings();
  Future<void> saveSettings(BarkPushSettings settings);

  /// The stored device key, or `''` when the channel was never configured.
  Future<String> loadDeviceKey();

  /// Persists [deviceKey]; an empty value deletes the keychain entry rather
  /// than storing a blank, so "cleared" and "never set" stay the same state.
  Future<void> saveDeviceKey(String deviceKey);
}

class SharedPrefsBarkPushRepository implements BarkPushRepository {
  SharedPrefsBarkPushRepository({
    required SharedPreferences preferences,
    required SecureKeyValueStore secureStore,
  }) : _preferences = preferences,
       _secureStore = secureStore;

  static const _settingsKey = 'teampilot.bark_push.v1';

  /// Deliberately versioned and spelled out: renaming it silently orphans a key
  /// the user already typed, and the failure looks like "push stopped working"
  /// with nothing in the logs.
  static const _deviceKeyKey = 'teampilot.bark_push.v1.device_key';

  final SharedPreferences _preferences;
  final SecureKeyValueStore _secureStore;

  @override
  Future<BarkPushSettings> loadSettings() async {
    final raw = _preferences.getString(_settingsKey);
    if (raw == null || raw.trim().isEmpty) return BarkPushSettings.defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return BarkPushSettings.defaults;
      return BarkPushSettings.fromJson(decoded.cast<String, Object?>());
    } on Object catch (e) {
      appLogger.d('[bark] settings unreadable, using defaults: $e');
      return BarkPushSettings.defaults;
    }
  }

  @override
  Future<void> saveSettings(BarkPushSettings settings) =>
      _preferences.setString(_settingsKey, jsonEncode(settings.toJson()));

  @override
  Future<String> loadDeviceKey() async {
    try {
      return (await _secureStore.read(_deviceKeyKey))?.trim() ?? '';
    } on Object catch (e) {
      // A locked / unavailable keychain must not take the settings page down.
      appLogger.d('[bark] device key unreadable: $e');
      return '';
    }
  }

  @override
  Future<void> saveDeviceKey(String deviceKey) {
    final value = deviceKey.trim();
    return value.isEmpty
        ? _secureStore.delete(_deviceKeyKey)
        : _secureStore.write(_deviceKeyKey, value);
  }
}

/// Test double holding one settings blob and one key in memory.
class InMemoryBarkPushRepository implements BarkPushRepository {
  InMemoryBarkPushRepository({
    BarkPushSettings? settings,
    String deviceKey = '',
  }) : _settings = settings ?? BarkPushSettings.defaults,
       _deviceKey = deviceKey;

  BarkPushSettings _settings;
  String _deviceKey;

  @override
  Future<BarkPushSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(BarkPushSettings settings) async =>
      _settings = settings;

  @override
  Future<String> loadDeviceKey() async => _deviceKey;

  @override
  Future<void> saveDeviceKey(String deviceKey) async =>
      _deviceKey = deviceKey.trim();
}
