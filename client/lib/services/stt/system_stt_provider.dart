import 'dart:async';

import 'package:teampilot/services/stt/speech_recognizer.dart';
import 'package:teampilot/services/stt/stt_provider.dart';

/// On-device speech recognition, driven by the platform recognizer.
///
/// The one backend that needs no credentials: recognition runs on the device
/// through [SpeechRecognizer], so there is nothing to connect to and
/// [testConnection] is a no-op.
class SystemSttProvider implements SttProvider {
  SystemSttProvider(this._recognizer);

  final SpeechRecognizer _recognizer;

  StreamController<SttResult>? _controller;
  Completer<bool> _ready = Completer<bool>();

  @override
  Future<bool> isAvailable() => _recognizer.initialize();

  @override
  Stream<SttResult> start({String? localeId}) {
    // A fresh future per session: a provider reused across stop-then-start must
    // report the new session, not the previous verdict (see [SttProvider.ready]).
    _ready = Completer<bool>();
    final controller = StreamController<SttResult>();
    _controller = controller;

    unawaited(_begin(controller, localeId));

    return controller.stream;
  }

  Future<void> _begin(
    StreamController<SttResult> controller,
    String? localeId,
  ) async {
    if (!await _recognizer.initialize()) {
      if (!_ready.isCompleted) _ready.complete(false);
      controller.addError(const SttException('speech recognizer unavailable'));
      await controller.close();
      return;
    }
    if (!await _recognizer.hasPermission()) {
      if (!_ready.isCompleted) _ready.complete(false);
      controller.addError(const VoicePermissionDeniedException());
      await controller.close();
      return;
    }

    await _recognizer.listen(
      onResult: (text, isFinal) {
        if (!controller.isClosed) {
          controller.add(SttResult(text: text, isFinal: isFinal));
        }
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      localeId: localeId,
    );
    if (!_ready.isCompleted) _ready.complete(true);
  }

  @override
  Future<bool> get ready => _ready.future;

  @override
  Future<void> stop() async {
    await _recognizer.stop();
    // Never leave a caller awaiting a session that will never go live.
    if (!_ready.isCompleted) _ready.complete(false);
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  @override
  Future<int> testConnection() async => 0;

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
  }
}
