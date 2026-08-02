import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/voice_input_cubit.dart';
import 'package:teampilot/repositories/voice_input_repository.dart';
import 'package:teampilot/services/stt/stt_provider.dart';

import '../support/fake_stt_provider.dart';

void main() {
  late InMemoryVoiceInputRepository repository;
  late List<String> transcripts;
  late List<VoiceInputFailure> failures;
  late FakeSttProvider provider;
  late List<SttProviderType> builtFor;

  VoiceInputCubit build({
    FakeSttProvider? withProvider,
    Duration maxDuration = const Duration(seconds: 60),
  }) {
    provider = withProvider ?? FakeSttProvider();
    final cubit = VoiceInputCubit(
      repository: repository,
      providerFactory: (type, credentials) {
        builtFor.add(type);
        return provider;
      },
      maxDuration: maxDuration,
    );
    // Both are broadcast, so subscribing here does not stop the production
    // consumers (the mirror page and the failure messenger) from subscribing.
    cubit.transcripts.listen(transcripts.add);
    cubit.failures.listen(failures.add);
    return cubit;
  }

  setUp(() {
    repository = InMemoryVoiceInputRepository();
    transcripts = [];
    failures = [];
    builtFor = [];
  });

  group('load', () {
    test('starts idle on the system provider', () async {
      final cubit = build();
      await cubit.load();
      expect(cubit.state.provider, SttProviderType.system);
      expect(cubit.state.status, VoiceInputStatus.idle);
      expect(cubit.state.systemAvailable, isTrue);
      expect(cubit.state.available, isTrue);
      expect(cubit.state.configured, isTrue);
      await cubit.close();
    });

    test('is unavailable when nothing can run', () async {
      // No on-device recognizer and no cloud credentials: the mic button hides
      // rather than offering a tap that can only fail.
      final cubit = build(
        withProvider: FakeSttProvider(availableValue: false),
      );
      await cubit.load();
      expect(cubit.state.systemAvailable, isFalse);
      expect(cubit.state.available, isFalse);
      await cubit.close();
    });

    test('is available but unconfigured on a cloud provider with no keys',
        () async {
      await repository.savePrefs(
        const VoiceInputPrefs(
          provider: SttProviderType.aliyun,
          localeId: '',
        ),
      );
      final cubit = build();
      await cubit.load();
      expect(cubit.state.provider, SttProviderType.aliyun);
      expect(cubit.state.configured, isFalse);
      expect(
        cubit.state.available,
        isTrue,
        reason: 'the system recognizer still works, so the button stays',
      );
      await cubit.close();
    });
  });

  group('listening', () {
    test('goes starting then listening, passing the chosen locale', () async {
      final cubit = build();
      await cubit.load();
      await cubit.setLocaleId('zh-CN');

      final starting = cubit.startListening();
      expect(cubit.state.status, VoiceInputStatus.starting);
      await starting;
      expect(cubit.state.status, VoiceInputStatus.listening);
      expect(provider.startedLocaleId, 'zh-CN');
      await cubit.close();
    });

    test('inserts only final results', () async {
      // Interim text is overwritten on the next frame; inserting it would leave
      // half-recognized fragments in the composer.
      final cubit = build();
      await cubit.load();
      await cubit.startListening();

      provider.emit('git', isFinal: false);
      provider.emit('git commit', isFinal: true);
      await Future<void>.delayed(Duration.zero);

      expect(transcripts, ['git commit']);
      await cubit.close();
    });

    test('inserts the last interim result if the session ends without a final',
        () async {
      // A short utterance can close before the backend settles a sentence;
      // dropping it would lose everything the user said.
      final cubit = build();
      await cubit.load();
      await cubit.startListening();

      provider.emit('ls -la', isFinal: false);
      await Future<void>.delayed(Duration.zero);
      await provider.endSession();
      await Future<void>.delayed(Duration.zero);

      expect(transcripts, ['ls -la']);
      expect(cubit.state.status, VoiceInputStatus.idle);
      await cubit.close();
    });

    test('does not re-insert an interim result already superseded by a final',
        () async {
      final cubit = build();
      await cubit.load();
      await cubit.startListening();

      provider.emit('git', isFinal: false);
      provider.emit('git commit', isFinal: true);
      await Future<void>.delayed(Duration.zero);
      await provider.endSession();
      await Future<void>.delayed(Duration.zero);

      expect(transcripts, ['git commit']);
      await cubit.close();
    });

    test('ignores a second start while already listening', () async {
      final cubit = build();
      await cubit.load();
      await cubit.startListening();
      await cubit.startListening();
      expect(provider.startCalls, 1);
      await cubit.close();
    });

    test('returns to idle and stops the provider on stopListening', () async {
      final cubit = build();
      await cubit.load();
      await cubit.startListening();
      await cubit.stopListening();
      expect(cubit.state.status, VoiceInputStatus.idle);
      expect(provider.stopCalls, 1);
      await cubit.close();
    });

    test('stopListening is safe when idle', () async {
      final cubit = build();
      await cubit.load();
      await expectLater(cubit.stopListening(), completes);
      expect(provider.stopCalls, 0);
      await cubit.close();
    });

    test('returns to idle when the session never becomes ready', () async {
      final cubit = build(withProvider: FakeSttProvider(readyValue: false));
      await cubit.load();
      await cubit.startListening();
      expect(cubit.state.status, VoiceInputStatus.idle);
      await cubit.close();
    });
  });

  group('failures', () {
    test('reports a denied microphone as its own failure', () async {
      final cubit = build();
      await cubit.load();
      await cubit.startListening();

      provider.fail(const VoicePermissionDeniedException());
      await Future<void>.delayed(Duration.zero);

      expect(failures, [VoiceInputFailure.permissionDenied]);
      expect(cubit.state.status, VoiceInputStatus.idle);
      await cubit.close();
    });

    test('reports any other error as a generic failure', () async {
      final cubit = build();
      await cubit.load();
      await cubit.startListening();

      provider.fail(const SttException('socket died'));
      await Future<void>.delayed(Duration.zero);

      expect(failures, [VoiceInputFailure.failed]);
      expect(cubit.state.status, VoiceInputStatus.idle);
      await cubit.close();
    });
  });

  group('settings', () {
    test('setProvider persists and rebuilds on the next session', () async {
      final cubit = build();
      await cubit.load();
      await cubit.setProvider(SttProviderType.volcengine);
      expect(cubit.state.provider, SttProviderType.volcengine);
      expect(repository.lastSavedPrefs!.provider, SttProviderType.volcengine);
      // The volcengine backend must be configured before startListening() will
      // open a session — the guard is on `configured`, not `available`.
      await cubit.setCredential(VoiceCredentialField.volcAppId, 'app');
      await cubit.setCredential(VoiceCredentialField.volcAccessToken, 'token');
      await cubit.startListening();
      expect(builtFor.last, SttProviderType.volcengine);
      await cubit.close();
    });

    test('does not start an unconfigured cloud backend', () async {
      // A cloud backend selected with no credentials is `available` (the system
      // recognizer works) but not `configured`. startListening() must refuse:
      // opening a session would dial a socket with an empty app id and fail
      // opaquely. Routing the tap to settings is the UI's job (Task 10).
      final cubit = build();
      await cubit.load();
      await cubit.setProvider(SttProviderType.volcengine);
      expect(cubit.state.available, isTrue);
      expect(cubit.state.configured, isFalse);

      await cubit.startListening();

      expect(cubit.state.status, VoiceInputStatus.idle);
      // Assert on the factory record, not only status: a status-only check
      // would pass even if a provider had been built and immediately failed.
      expect(builtFor, isNot(contains(SttProviderType.volcengine)));
      expect(provider.startCalls, 0);
      await cubit.close();
    });

    test('setProvider stops an in-flight session first', () async {
      // Switching backends mid-utterance would leave the old socket streaming
      // audio the user thinks they redirected.
      final cubit = build();
      await cubit.load();
      await cubit.startListening();
      await cubit.setProvider(SttProviderType.aliyun);
      expect(provider.stopCalls, 1);
      expect(cubit.state.status, VoiceInputStatus.idle);
      await cubit.close();
    });

    test('setCredential persists and updates configured', () async {
      final cubit = build();
      await cubit.load();
      await cubit.setProvider(SttProviderType.volcengine);
      expect(cubit.state.configured, isFalse);

      await cubit.setCredential(VoiceCredentialField.volcAppId, 'app');
      await cubit.setCredential(
        VoiceCredentialField.volcAccessToken,
        'token',
      );

      expect(cubit.state.configured, isTrue);
      expect(cubit.state.credentials.volcAppId, 'app');
      await cubit.close();
    });

    test('testConnection returns the provider latency', () async {
      final cubit = build();
      await cubit.load();
      expect(await cubit.testConnection(), 42);
      await cubit.close();
    });

    test('testConnection propagates the failure', () async {
      final cubit = build();
      await cubit.load();
      provider.testConnectionError = const SttException('bad key');
      await expectLater(
        cubit.testConnection(),
        throwsA(isA<SttException>()),
      );
      await cubit.close();
    });
  });

  test('auto-stops at the recording cap', () {
    // A mic left open is metered cloud spend and an open privacy hole; nothing
    // dictated into a terminal runs a minute.
    fakeAsync((async) {
      final cubit = build(maxDuration: const Duration(seconds: 60));
      cubit.load();
      async.flushMicrotasks();
      cubit.startListening();
      async.flushMicrotasks();
      expect(cubit.state.status, VoiceInputStatus.listening);

      async.elapse(const Duration(seconds: 59));
      expect(cubit.state.status, VoiceInputStatus.listening);

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(cubit.state.status, VoiceInputStatus.idle);
      expect(provider.stopCalls, 1);

      cubit.close();
      async.flushMicrotasks();
    });
  });

  test('close stops an in-flight session', () async {
    // Leaving the mirror page must not leave the microphone hot.
    final cubit = build();
    await cubit.load();
    await cubit.startListening();
    await cubit.close();
    expect(provider.stopCalls, 1);
  });

  test('load after close does not emit', () async {
    final cubit = build();
    await cubit.close();
    await expectLater(cubit.load(), completes);
  });
}
