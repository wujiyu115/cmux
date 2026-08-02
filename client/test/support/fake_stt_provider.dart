import 'dart:async';

import 'package:teampilot/services/stt/stt_provider.dart';

/// A provider the test drives: [emit] pushes results, [openSession] resolves
/// `ready`.
class FakeSttProvider implements SttProvider {
  FakeSttProvider({this.availableValue = true, this.readyValue = true});

  final bool availableValue;
  final bool readyValue;

  final _results = StreamController<SttResult>.broadcast();
  final _ready = Completer<bool>();

  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  String? startedLocaleId;
  int testConnectionMillis = 42;
  Object? testConnectionError;

  @override
  Future<bool> isAvailable() async => availableValue;

  @override
  Stream<SttResult> start({String? localeId}) {
    startCalls++;
    startedLocaleId = localeId;
    if (readyValue) {
      openSession();
    } else {
      if (!_ready.isCompleted) _ready.complete(false);
    }
    return _results.stream;
  }

  @override
  Future<bool> get ready => _ready.future;

  @override
  Future<void> stop() async {
    stopCalls++;
    if (!_results.isClosed) await _results.close();
  }

  @override
  Future<int> testConnection() async {
    final error = testConnectionError;
    if (error != null) throw error;
    return testConnectionMillis;
  }

  @override
  void dispose() => disposeCalls++;

  void openSession() {
    if (!_ready.isCompleted) _ready.complete(true);
  }

  void emit(String text, {required bool isFinal}) =>
      _results.add(SttResult(text: text, isFinal: isFinal));

  void fail(Object error) => _results.addError(error);

  Future<void> endSession() async {
    if (!_results.isClosed) await _results.close();
  }
}
