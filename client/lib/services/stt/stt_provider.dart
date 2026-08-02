/// Which recognition backend is in use.
enum SttProviderType { system, volcengine, aliyun }

/// One recognition result. [isFinal] separates a settled sentence from an
/// interim guess; only final results are inserted into the composer.
class SttResult {
  const SttResult({required this.text, required this.isFinal});

  final String text;
  final bool isFinal;
}

/// The OS refused microphone access.
///
/// Distinct from [SttException] because it is the one failure the user can fix,
/// and the fix is outside the app.
class VoicePermissionDeniedException implements Exception {
  const VoicePermissionDeniedException();

  @override
  String toString() => 'VoicePermissionDeniedException';
}

/// Any other recognition failure: handshake, auth, transport, recognizer.
class SttException implements Exception {
  const SttException(this.message);

  final String message;

  @override
  String toString() => 'SttException: $message';
}

/// The slice of a WebSocket the cloud providers use.
///
/// Deliberately narrower than `WebSocketChannel`: a test's stand-in for that
/// class has to stub a dozen `StreamChannel` members it never uses, so the seam
/// is defined here instead and the real socket adapts to it
/// ([WebSocketSttSocket] in `stt_socket.dart`).
abstract class SttSocket {
  /// Incoming frames — `String` for the JSON protocols, `List<int>` for binary.
  Stream<dynamic> get messages;

  void send(Object data);

  Future<void> close();
}

/// Injection seam for the two cloud providers' sockets, so their tests run
/// against a fake socket instead of the network.
typedef SttSocketFactory =
    Future<SttSocket> Function(Uri url, {Map<String, String>? headers});

/// One speech-recognition backend.
///
/// [start] emits until [stop] is called, the backend closes the session, or it
/// fails — a failure arrives as a stream error carrying
/// [VoicePermissionDeniedException] or [SttException].
abstract class SttProvider {
  /// Whether this backend can run at all: the recognizer initializes, or the
  /// credentials it needs are present.
  Future<bool> isAvailable();

  Stream<SttResult> start({String? localeId});

  /// Completes `true` once the session is live and speech will be recognized,
  /// `false` if setup failed.
  ///
  /// Only valid after [start]. The UI needs this because a cloud session can
  /// take a second or two to mint a token and finish a handshake, and a mic
  /// button that looks idle through that window reads as an unresponsive tap.
  /// It resolves `false` rather than throwing so the stream stays the single
  /// error channel — a rejected future nobody awaited would surface as an
  /// unhandled async error instead of as a message to the user.
  ///
  /// Scoped to one session: each [start] installs a fresh future that
  /// supersedes the previous one, so a provider reused across a
  /// stop-then-start cycle reports the new session rather than the old
  /// verdict. Reading it before the first [start] is not defined — callers
  /// only ever reach it by way of the stream [start] handed them.
  Future<bool> get ready;

  Future<void> stop();

  /// Round-trip milliseconds to a working session. Throws on failure — the
  /// settings page uses it to tell the user whether their credentials work.
  Future<int> testConnection();

  void dispose();
}
