import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// A recognition language, as the picker shows it.
class SpeechLocale {
  const SpeechLocale({required this.id, required this.name});

  final String id;
  final String name;
}

/// The slice of on-device speech recognition this app uses.
///
/// `SpeechToText` is a concrete plugin class, so depending on it directly would
/// put a real recognizer and a real microphone in every test. Providers depend
/// on this instead and their tests hand-write a stand-in.
abstract class SpeechRecognizer {
  Future<bool> initialize();
  Future<bool> hasPermission();
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function() onDone,
    String? localeId,
  });
  Future<void> stop();
  Future<List<SpeechLocale>> locales();
}

class PluginSpeechRecognizer implements SpeechRecognizer {
  PluginSpeechRecognizer({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  void Function()? _onDone;

  @override
  Future<bool> initialize() => _speech.initialize(
    // The plugin reports the end of a listening turn through its status
    // listener, not through the result callback, so [onDone] is wired here.
    onStatus: (status) {
      if (status == 'done' || status == 'notListening') {
        // Ported from the Nexterm reference (system_stt_provider.dart): the
        // final recognition result can arrive a beat *after* the status flips
        // to 'done'/'notListening'. Closing immediately would race that last
        // result and drop it, so settle for 200 ms before signalling done.
        Future.delayed(const Duration(milliseconds: 200), () {
          _onDone?.call();
        });
      }
    },
  );

  @override
  Future<bool> hasPermission() async => _speech.hasPermission;

  @override
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function() onDone,
    String? localeId,
  }) {
    _onDone = onDone;
    return _speech.listen(
      onResult: (SpeechRecognitionResult result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        localeId: localeId,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<List<SpeechLocale>> locales() async {
    final locales = await _speech.locales();
    return locales
        .map((l) => SpeechLocale(id: l.localeId, name: l.name))
        .toList();
  }
}
