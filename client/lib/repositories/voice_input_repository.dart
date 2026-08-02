import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/stt/stt_provider.dart';
import '../utils/logging/logger_utils.dart';
import 'ssh_credential_store.dart';

/// One cloud-credential slot. The two Volcengine fields and the three Aliyun
/// fields each map to a keychain entry; see [DefaultVoiceInputRepository].
enum VoiceCredentialField {
  volcAppId,
  volcAccessToken,
  aliyunAccessKeyId,
  aliyunAccessKeySecret,
  aliyunAppKey,
}

/// The non-secret voice-input preferences: which backend, and the recognition
/// language the user pinned. Persisted as one JSON blob in [SharedPreferences];
/// the secrets live separately in the keychain.
@immutable
class VoiceInputPrefs {
  const VoiceInputPrefs({required this.provider, required this.localeId});

  /// The chosen recognition backend.
  final SttProviderType provider;

  /// The pinned recognition-language id, or `''` to let the backend pick.
  final String localeId;

  static const defaults = VoiceInputPrefs(
    provider: SttProviderType.system,
    localeId: '',
  );

  VoiceInputPrefs copyWith({SttProviderType? provider, String? localeId}) =>
      VoiceInputPrefs(
        provider: provider ?? this.provider,
        localeId: localeId ?? this.localeId,
      );

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'localeId': localeId,
  };

  /// Reads a stored blob back. An unrecognized provider name degrades to
  /// [SttProviderType.system] — the backend that needs no credentials — while
  /// still keeping whatever [localeId] it could read, so a downgrade or a
  /// dropped backend never bricks voice input.
  factory VoiceInputPrefs.fromJson(Map<String, Object?> json) {
    final raw = json['provider'];
    final provider = SttProviderType.values.firstWhere(
      (t) => t.name == raw,
      orElse: () => SttProviderType.system,
    );
    final localeId = json['localeId'];
    return VoiceInputPrefs(
      provider: provider,
      localeId: localeId is String ? localeId : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceInputPrefs &&
      other.provider == provider &&
      other.localeId == localeId;

  @override
  int get hashCode => Object.hash(provider, localeId);
}

/// The cloud credentials, held together so equality can drive a `buildWhen`.
@immutable
class VoiceCredentials {
  const VoiceCredentials({
    required this.volcAppId,
    required this.volcAccessToken,
    required this.aliyunAccessKeyId,
    required this.aliyunAccessKeySecret,
    required this.aliyunAppKey,
  });

  final String volcAppId;
  final String volcAccessToken;
  final String aliyunAccessKeyId;
  final String aliyunAccessKeySecret;
  final String aliyunAppKey;

  static const empty = VoiceCredentials(
    volcAppId: '',
    volcAccessToken: '',
    aliyunAccessKeyId: '',
    aliyunAccessKeySecret: '',
    aliyunAppKey: '',
  );

  bool get hasVolcengine => volcAppId.isNotEmpty && volcAccessToken.isNotEmpty;

  bool get hasAliyun =>
      aliyunAccessKeyId.isNotEmpty &&
      aliyunAccessKeySecret.isNotEmpty &&
      aliyunAppKey.isNotEmpty;

  /// Whether [type] has every credential it needs to run.
  bool hasFor(SttProviderType type) => switch (type) {
    SttProviderType.system => true,
    SttProviderType.volcengine => hasVolcengine,
    SttProviderType.aliyun => hasAliyun,
  };

  /// The current value of [f]. Exhaustive over [VoiceCredentialField] with no
  /// `default`, so a sixth field fails to compile rather than silently reading
  /// as empty.
  String field(VoiceCredentialField f) => switch (f) {
    VoiceCredentialField.volcAppId => volcAppId,
    VoiceCredentialField.volcAccessToken => volcAccessToken,
    VoiceCredentialField.aliyunAccessKeyId => aliyunAccessKeyId,
    VoiceCredentialField.aliyunAccessKeySecret => aliyunAccessKeySecret,
    VoiceCredentialField.aliyunAppKey => aliyunAppKey,
  };

  /// A copy with [f] set to [value]. Exhaustive, same reasoning as [field].
  VoiceCredentials withField(VoiceCredentialField f, String value) =>
      switch (f) {
        VoiceCredentialField.volcAppId => VoiceCredentials(
          volcAppId: value,
          volcAccessToken: volcAccessToken,
          aliyunAccessKeyId: aliyunAccessKeyId,
          aliyunAccessKeySecret: aliyunAccessKeySecret,
          aliyunAppKey: aliyunAppKey,
        ),
        VoiceCredentialField.volcAccessToken => VoiceCredentials(
          volcAppId: volcAppId,
          volcAccessToken: value,
          aliyunAccessKeyId: aliyunAccessKeyId,
          aliyunAccessKeySecret: aliyunAccessKeySecret,
          aliyunAppKey: aliyunAppKey,
        ),
        VoiceCredentialField.aliyunAccessKeyId => VoiceCredentials(
          volcAppId: volcAppId,
          volcAccessToken: volcAccessToken,
          aliyunAccessKeyId: value,
          aliyunAccessKeySecret: aliyunAccessKeySecret,
          aliyunAppKey: aliyunAppKey,
        ),
        VoiceCredentialField.aliyunAccessKeySecret => VoiceCredentials(
          volcAppId: volcAppId,
          volcAccessToken: volcAccessToken,
          aliyunAccessKeyId: aliyunAccessKeyId,
          aliyunAccessKeySecret: value,
          aliyunAppKey: aliyunAppKey,
        ),
        VoiceCredentialField.aliyunAppKey => VoiceCredentials(
          volcAppId: volcAppId,
          volcAccessToken: volcAccessToken,
          aliyunAccessKeyId: aliyunAccessKeyId,
          aliyunAccessKeySecret: aliyunAccessKeySecret,
          aliyunAppKey: value,
        ),
      };

  @override
  bool operator ==(Object other) =>
      other is VoiceCredentials &&
      other.volcAppId == volcAppId &&
      other.volcAccessToken == volcAccessToken &&
      other.aliyunAccessKeyId == aliyunAccessKeyId &&
      other.aliyunAccessKeySecret == aliyunAccessKeySecret &&
      other.aliyunAppKey == aliyunAppKey;

  @override
  int get hashCode => Object.hash(
    volcAppId,
    volcAccessToken,
    aliyunAccessKeyId,
    aliyunAccessKeySecret,
    aliyunAppKey,
  );
}

/// Loads and stores the voice-input preferences and cloud credentials.
abstract class VoiceInputRepository {
  Future<VoiceInputPrefs> loadPrefs();
  Future<void> savePrefs(VoiceInputPrefs prefs);
  Future<VoiceCredentials> loadCredentials();
  Future<void> saveCredential(VoiceCredentialField field, String value);
}

/// Prefs go to [SharedPreferences] as one JSON blob; credentials go to the
/// system keychain through the shared [SecureKeyValueStore], one entry per
/// field.
class DefaultVoiceInputRepository implements VoiceInputRepository {
  const DefaultVoiceInputRepository({
    required SharedPreferences preferences,
    required SecureKeyValueStore secureStore,
  }) : _preferences = preferences,
       _secureStore = secureStore;

  static const storageKey = 'teampilot.voice_input.v1';

  static const _credentialPrefix = 'teampilot.voice_creds.v1';

  final SharedPreferences _preferences;
  final SecureKeyValueStore _secureStore;

  /// The keychain entry name for [field]. These suffixes are load-bearing:
  /// renaming one silently orphans a credential the user already typed.
  static String _fieldName(VoiceCredentialField field) => switch (field) {
    VoiceCredentialField.volcAppId => 'volc_app_id',
    VoiceCredentialField.volcAccessToken => 'volc_access_token',
    VoiceCredentialField.aliyunAccessKeyId => 'aliyun_access_key_id',
    VoiceCredentialField.aliyunAccessKeySecret => 'aliyun_access_key_secret',
    VoiceCredentialField.aliyunAppKey => 'aliyun_app_key',
  };

  String _key(VoiceCredentialField field) =>
      '$_credentialPrefix.${_fieldName(field)}';

  @override
  Future<VoiceInputPrefs> loadPrefs() async {
    final stored = _preferences.getString(storageKey);
    if (stored == null || stored.isEmpty) return VoiceInputPrefs.defaults;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return VoiceInputPrefs.defaults;
      return VoiceInputPrefs.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException catch (e, st) {
      // Silently defaulting hides the one case a user would report: a backend
      // and language they configured coming back reset.
      AppLogger.instance.w(
        'Discarding unparseable voice input prefs at $storageKey ($e)',
        error: e,
        stackTrace: st,
      );
      return VoiceInputPrefs.defaults;
    }
  }

  @override
  Future<void> savePrefs(VoiceInputPrefs prefs) =>
      _preferences.setString(storageKey, jsonEncode(prefs.toJson()));

  @override
  Future<VoiceCredentials> loadCredentials() async {
    final values = await Future.wait(
      VoiceCredentialField.values.map((f) => _secureStore.read(_key(f))),
    );
    String at(VoiceCredentialField f) => values[f.index] ?? '';
    return VoiceCredentials(
      volcAppId: at(VoiceCredentialField.volcAppId),
      volcAccessToken: at(VoiceCredentialField.volcAccessToken),
      aliyunAccessKeyId: at(VoiceCredentialField.aliyunAccessKeyId),
      aliyunAccessKeySecret: at(VoiceCredentialField.aliyunAccessKeySecret),
      aliyunAppKey: at(VoiceCredentialField.aliyunAppKey),
    );
  }

  @override
  Future<void> saveCredential(VoiceCredentialField field, String value) {
    final key = _key(field);
    // Clearing a field deletes the entry rather than writing an empty string,
    // so a deliberately removed secret leaves no dead keychain entry behind.
    return value.isEmpty
        ? _secureStore.delete(key)
        : _secureStore.write(key, value);
  }
}

/// Test double holding one prefs blob and one credentials snapshot in memory.
class InMemoryVoiceInputRepository implements VoiceInputRepository {
  InMemoryVoiceInputRepository({
    VoiceInputPrefs? prefs,
    VoiceCredentials? credentials,
  }) : _prefs = prefs ?? VoiceInputPrefs.defaults,
       _credentials = credentials ?? VoiceCredentials.empty;

  VoiceInputPrefs _prefs;
  VoiceCredentials _credentials;

  /// The last value passed to [savePrefs], for tests to assert against.
  VoiceInputPrefs? lastSavedPrefs;

  /// Number of [savePrefs] calls — lets tests assert a debounce coalesced.
  int savePrefsCount = 0;

  @override
  Future<VoiceInputPrefs> loadPrefs() async => _prefs;

  @override
  Future<void> savePrefs(VoiceInputPrefs prefs) async {
    _prefs = prefs;
    lastSavedPrefs = prefs;
    savePrefsCount++;
  }

  @override
  Future<VoiceCredentials> loadCredentials() async => _credentials;

  @override
  Future<void> saveCredential(VoiceCredentialField field, String value) async {
    _credentials = _credentials.withField(field, value);
  }
}
