import 'dart:async';

import 'package:teampilot/services/stt/stt_provider.dart';

/// A provider the test drives: [emit] pushes results, [openSession] resolves
/// `ready`.
class FakeSttProvider implements SttProvider {
  FakeSttProvider({this.availableValue = true, this.readyValue = true});

  final bool availableValue;
  final bool readyValue;

  // Recreated per session in [start]. Session objects must belong to the zone
  // that calls start() — under `testWidgets`, `pump()` only flushes microtasks
  // from the test-body zone, not the setUp zone a setUp-built fake lives in, so
  // a constructor-scoped `ready` future would never resolve through pumps. The
  // real providers reset these in start() for the same session-scoping reason.
  StreamController<SttResult> _results = StreamController<SttResult>.broadcast();
  Completer<bool> _ready = Completer<bool>();

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
    // Fresh session objects in the caller's zone (see the field comment).
    _results = StreamController<SttResult>.broadcast();
    _ready = Completer<bool>();
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
