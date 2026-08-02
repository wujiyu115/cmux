import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/voice_input_repository.dart';
import 'package:teampilot/services/stt/speech_recognizer.dart';
import 'package:teampilot/services/stt/stt_locales.dart';
import 'package:teampilot/services/stt/stt_provider.dart';

void main() {
  late SharedPreferences preferences;
  late InMemorySecureKeyValueStore secureStore;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    secureStore = InMemorySecureKeyValueStore();
  });

  DefaultVoiceInputRepository build() => DefaultVoiceInputRepository(
    preferences: preferences,
    secureStore: secureStore,
  );

  group('prefs', () {
    test('defaults to the system provider and no explicit locale', () async {
      final prefs = await build().loadPrefs();
      expect(prefs.provider, SttProviderType.system);
      expect(prefs.localeId, '');
    });

    test('round-trips through storage', () async {
      await build().savePrefs(
        const VoiceInputPrefs(
          provider: SttProviderType.aliyun,
          localeId: 'zh-CN',
        ),
      );
      final reloaded = await build().loadPrefs();
      expect(reloaded.provider, SttProviderType.aliyun);
      expect(reloaded.localeId, 'zh-CN');
    });

    test('falls back to system for an unknown provider name', () async {
      // A downgrade, or a provider dropped in a later version, must not brick
      // voice input — it degrades to the backend that needs no credentials.
      await preferences.setString(
        DefaultVoiceInputRepository.storageKey,
        '{"provider":"tencent","localeId":"zh-CN"}',
      );
      final prefs = await build().loadPrefs();
      expect(prefs.provider, SttProviderType.system);
      expect(prefs.localeId, 'zh-CN', reason: 'the readable half survives');
    });

    test('falls back to defaults on unparseable JSON', () async {
      await preferences.setString(
        DefaultVoiceInputRepository.storageKey,
        'not json',
      );
      final prefs = await build().loadPrefs();
      expect(prefs.provider, SttProviderType.system);
      expect(prefs.localeId, '');
    });
  });

  group('credentials', () {
    test('start out empty', () async {
      final credentials = await build().loadCredentials();
      expect(credentials, VoiceCredentials.empty);
      expect(credentials.hasVolcengine, isFalse);
      expect(credentials.hasAliyun, isFalse);
    });

    test('write to the documented secure-storage keys', () async {
      final repository = build();
      await repository.saveCredential(VoiceCredentialField.volcAppId, 'app');
      await repository.saveCredential(
        VoiceCredentialField.aliyunAppKey,
        'key',
      );
      // Pinned literally: renaming a key silently loses the credential a user
      // already typed, and the failure looks like a broken provider.
      expect(
        await secureStore.read('teampilot.voice_creds.v1.volc_app_id'),
        'app',
      );
      expect(
        await secureStore.read('teampilot.voice_creds.v1.aliyun_app_key'),
        'key',
      );
    });

    test('load every field back', () async {
      final repository = build();
      for (final field in VoiceCredentialField.values) {
        await repository.saveCredential(field, field.name);
      }
      final credentials = await repository.loadCredentials();
      for (final field in VoiceCredentialField.values) {
        expect(credentials.field(field), field.name);
      }
    });

    test('deletes the entry when a field is cleared', () async {
      // Leaving an empty string behind would keep a dead keychain entry around
      // after the user deliberately removed a secret.
      final repository = build();
      await repository.saveCredential(VoiceCredentialField.volcAppId, 'app');
      await repository.saveCredential(VoiceCredentialField.volcAppId, '');
      expect(
        await secureStore.read('teampilot.voice_creds.v1.volc_app_id'),
        isNull,
      );
    });
  });

  group('VoiceCredentials.hasFor', () {
    test('system needs nothing', () {
      expect(VoiceCredentials.empty.hasFor(SttProviderType.system), isTrue);
    });

    test('volcengine needs both its fields', () {
      var credentials = VoiceCredentials.empty.withField(
        VoiceCredentialField.volcAppId,
        'app',
      );
      expect(credentials.hasFor(SttProviderType.volcengine), isFalse);
      credentials = credentials.withField(
        VoiceCredentialField.volcAccessToken,
        'token',
      );
      expect(credentials.hasFor(SttProviderType.volcengine), isTrue);
    });

    test('aliyun needs all three of its fields', () {
      var credentials = VoiceCredentials.empty
          .withField(VoiceCredentialField.aliyunAccessKeyId, 'id')
          .withField(VoiceCredentialField.aliyunAccessKeySecret, 'secret');
      expect(credentials.hasFor(SttProviderType.aliyun), isFalse);
      credentials = credentials.withField(
        VoiceCredentialField.aliyunAppKey,
        'key',
      );
      expect(credentials.hasFor(SttProviderType.aliyun), isTrue);
    });
  });

  group('sttLocalesFor', () {
    test('offers locales for every provider', () {
      for (final type in SttProviderType.values) {
        expect(sttLocalesFor(type), isNotEmpty, reason: type.name);
      }
    });

    test('has no duplicate ids within a provider', () {
      for (final type in SttProviderType.values) {
        final ids = sttLocalesFor(type).map((l) => l.id).toList();
        expect(ids.toSet(), hasLength(ids.length), reason: type.name);
      }
    });

    test('returns unmodifiable lists', () {
      // The picker holds onto whatever it is handed; a caller mutating this
      // would corrupt the table for every later open.
      expect(
        () => sttLocalesFor(SttProviderType.aliyun).add(
          const SpeechLocale(id: 'x', name: 'x'),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
