import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/stt/speech_recognizer.dart';
import 'package:teampilot/services/stt/stt_provider.dart';
import 'package:teampilot/services/stt/system_stt_provider.dart';

/// Hand-written stand-in for the on-device recognizer: the test drives results
/// by calling [emit] / [finish], so no plugin and no microphone are involved.
class FakeSpeechRecognizer implements SpeechRecognizer {
  FakeSpeechRecognizer({this.initializes = true, this.permitted = true});

  final bool initializes;
  final bool permitted;

  int initializeCalls = 0;
  int stopCalls = 0;
  String? listenedLocaleId;
  bool listening = false;

  void Function(String text, bool isFinal)? _onResult;
  void Function()? _onDone;

  void emit(String text, {required bool isFinal}) =>
      _onResult?.call(text, isFinal);

  void finish() {
    listening = false;
    _onDone?.call();
  }

  @override
  Future<bool> initialize() async {
    initializeCalls++;
    return initializes;
  }

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function() onDone,
    String? localeId,
  }) async {
    listening = true;
    listenedLocaleId = localeId;
    _onResult = onResult;
    _onDone = onDone;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    listening = false;
  }

  @override
  Future<List<SpeechLocale>> locales() async => const [
    SpeechLocale(id: 'en_US', name: 'English (US)'),
  ];
}

void main() {
  test('isAvailable reflects whether the recognizer initializes', () async {
    expect(
      await SystemSttProvider(FakeSpeechRecognizer()).isAvailable(),
      isTrue,
    );
    expect(
      await SystemSttProvider(
        FakeSpeechRecognizer(initializes: false),
      ).isAvailable(),
      isFalse,
    );
  });

  test('emits interim results then the final one', () async {
    final recognizer = FakeSpeechRecognizer();
    final provider = SystemSttProvider(recognizer);
    final results = <SttResult>[];
    final stream = provider.start(localeId: 'zh_CN');
    final done = stream.listen(results.add).asFuture<void>();
    await Future<void>.delayed(Duration.zero);

    recognizer.emit('git', isFinal: false);
    recognizer.emit('git commit', isFinal: true);
    recognizer.finish();
    await done;

    expect(recognizer.listenedLocaleId, 'zh_CN');
    expect(results.map((r) => r.text), ['git', 'git commit']);
    expect(results.map((r) => r.isFinal), [false, true]);
  });

  test('closes the stream when the recognizer finishes on its own', () async {
    final recognizer = FakeSpeechRecognizer();
    final provider = SystemSttProvider(recognizer);
    final done = provider.start().listen((_) {}).asFuture<void>();
    await Future<void>.delayed(Duration.zero);
    recognizer.finish();
    await expectLater(done, completes);
  });

  test('stop closes the stream and stops the recognizer', () async {
    final recognizer = FakeSpeechRecognizer();
    final provider = SystemSttProvider(recognizer);
    final done = provider.start().listen((_) {}).asFuture<void>();
    await Future<void>.delayed(Duration.zero);
    await provider.stop();
    await expectLater(done, completes);
    expect(recognizer.stopCalls, 1);
    expect(recognizer.listening, isFalse);
  });

  test('errors with VoicePermissionDeniedException when the mic is refused',
      () async {
    // Initialization succeeding while permission is refused is the iOS shape of
    // a denied mic; it has to reach the user as the one failure they can fix,
    // not as a generic recognition error.
    final provider = SystemSttProvider(
      FakeSpeechRecognizer(permitted: false),
    );
    await expectLater(
      provider.start(),
      emitsError(isA<VoicePermissionDeniedException>()),
    );
  });

  test('errors with SttException when initialization fails', () async {
    final provider = SystemSttProvider(
      FakeSpeechRecognizer(initializes: false),
    );
    await expectLater(provider.start(), emitsError(isA<SttException>()));
  });

  test('ready resolves true once the recognizer is listening', () async {
    final recognizer = FakeSpeechRecognizer();
    final provider = SystemSttProvider(recognizer);
    provider.start().listen((_) {});
    expect(await provider.ready, isTrue);
    expect(recognizer.listening, isTrue);
    await provider.stop();
  });

  test('ready resolves false when setup fails', () async {
    // False rather than throwing: the stream already carries the error, and a
    // rejected future would double-report it as an unhandled async error.
    final provider = SystemSttProvider(
      FakeSpeechRecognizer(initializes: false),
    );
    provider.start().listen((_) {}, onError: (_) {});
    expect(await provider.ready, isFalse);
  });

  test('testConnection reports zero for on-device recognition', () async {
    // Nothing to connect to. The settings page hides the button for this
    // provider; the zero is here so the interface stays uniform.
    expect(await SystemSttProvider(FakeSpeechRecognizer()).testConnection(), 0);
  });
}
