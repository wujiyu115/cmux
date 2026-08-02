import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:teampilot/services/stt/aliyun_token_service.dart';
import 'package:teampilot/services/stt/pcm_audio_source.dart';
import 'package:teampilot/services/stt/stt_provider.dart';
import 'package:teampilot/utils/logging/logger_utils.dart';

const String _gatewayHost = 'nls-gateway-cn-shanghai.aliyuncs.com';
const String _gatewayPath = '/ws/v1';
const String _namespace = 'SpeechTranscriber';

/// Alibaba Cloud NLS (智能语音交互) streaming speech recognition.
///
/// The session is a JSON-text WebSocket to the NLS gateway: a
/// `StartTranscription` message, then raw-PCM binary once the gateway
/// acknowledges with `TranscriptionStarted`, with results arriving as
/// `TranscriptionResultChanged` / `SentenceEnd` events. The AccessKey pair
/// signs one token RPC via [AliyunTokenService]; only the token travels in the
/// URL. All I/O is injected ([PcmAudioSource], [SttSocketFactory],
/// [AliyunTokenService]) so the provider is tested without a real microphone,
/// socket or network.
class AliyunSttProvider implements SttProvider {
  AliyunSttProvider({
    required this.audio,
    required this.socketFactory,
    required this.tokenService,
    required this.accessKeyId,
    required this.accessKeySecret,
    required this.appKey,
    required this.idFactory,
    this.serverGrace = const Duration(seconds: 2),
    this.testConnectionTimeout = const Duration(seconds: 10),
  });

  final PcmAudioSource audio;
  final SttSocketFactory socketFactory;
  final AliyunTokenService tokenService;
  final String accessKeyId;
  final String accessKeySecret;
  final String appKey;
  final String Function() idFactory;

  /// How long [stop] waits for the server's trailing sentence before closing.
  /// Injectable so tests do not sit out a real wait; production default 2s.
  final Duration serverGrace;

  /// How long [testConnection] waits for `TranscriptionStarted` before failing.
  /// Injectable so the timeout test does not spend real seconds; production
  /// default 10s.
  final Duration testConnectionTimeout;

  StreamController<SttResult>? _results;
  SttSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  StreamSubscription<Uint8List>? _audioSub;
  String? _taskId;

  /// The PCM gate. PCM sent before `TranscriptionStarted` makes the gateway
  /// silently discard the whole task, so audio is dropped until this flips.
  bool _started = false;
  bool _stopping = false;
  Completer<bool> _ready = Completer<bool>();

  /// Completed the moment the socket closes, so [stop]'s grace wait can bail
  /// early instead of always sitting out the full window.
  Completer<void> _socketDone = Completer<void>();

  @override
  Future<bool> isAvailable() async =>
      accessKeyId.isNotEmpty && accessKeySecret.isNotEmpty && appKey.isNotEmpty;

  /// [localeId] is deliberately ignored: Alibaba binds the recognition language
  /// to the model behind the appKey, not to any request field, so there is no
  /// payload slot to carry it — inventing one would be a no-op the gateway
  /// rejects.
  @override
  Stream<SttResult> start({String? localeId}) {
    // A fresh future/session per start: a reused provider must report the new
    // session, not the previous verdict (see [SttProvider.ready]).
    _ready = Completer<bool>();
    _socketDone = Completer<void>();
    _started = false;
    _stopping = false;
    final results = StreamController<SttResult>();
    _results = results;

    unawaited(_run(results));

    return results.stream;
  }

  Future<void> _run(StreamController<SttResult> results) async {
    // Refuse before minting a token: minting is a signed API call, so doing it
    // for a session the user cannot speak into spends quota for nothing.
    if (!await audio.hasPermission()) {
      if (!_ready.isCompleted) _ready.complete(false);
      if (!results.isClosed) {
        results.addError(const VoicePermissionDeniedException());
        await results.close();
      }
      return;
    }

    try {
      final token = await tokenService.getToken(
        accessKeyId: accessKeyId,
        accessKeySecret: accessKeySecret,
      );
      final socket = await socketFactory(_gatewayUri(token));
      _socket = socket;
      _taskId = idFactory();
      _socketSub = socket.messages.listen(
        (data) => _onMessage(data, results),
        onError: (Object e, StackTrace st) {
          AppLogger.instance.w('Aliyun socket error', error: e, stackTrace: st);
          if (!_ready.isCompleted) _ready.complete(false);
          if (!results.isClosed) results.addError(SttException('socket error: $e'));
        },
        onDone: () {
          if (!_socketDone.isCompleted) _socketDone.complete();
          if (!results.isClosed) results.close();
        },
      );

      socket.send(_message('StartTranscription', _taskId!, payload: {
        'format': 'pcm',
        'sample_rate': 16000,
        'enable_intermediate_result': true,
        'enable_punctuation_prediction': true,
        'enable_inverse_text_normalization': true,
        'max_sentence_silence': 800,
      }));

      final pcm = await audio.start();
      _audioSub = pcm.listen((chunk) {
        // Drop, do not buffer, until TranscriptionStarted opens the gate.
        // Buffering and replaying handshake-era audio afterwards recognizes a
        // sentence shifted in time; dropping it loses only the pre-ack silence.
        if (!_started) return;
        _socket?.send(chunk);
      });
    } catch (e, st) {
      AppLogger.instance.w('Aliyun start failed', error: e, stackTrace: st);
      if (!_ready.isCompleted) _ready.complete(false);
      if (!results.isClosed) {
        results.addError(e is SttException ? e : SttException('failed to start session: $e'));
        await results.close();
      }
    }
  }

  void _onMessage(dynamic data, StreamController<SttResult> results) {
    // The gateway only sends JSON text; binary in is not part of the protocol.
    if (data is! String || results.isClosed) return;
    final decoded = _tryDecode(data);
    final header = decoded?['header'];
    if (header is! Map) return;
    final name = header['name'];
    final payload = decoded?['payload'];
    final result = payload is Map ? payload['result'] : null;

    switch (name) {
      case 'TranscriptionStarted':
        _started = true;
        if (!_ready.isCompleted) _ready.complete(true);
      case 'TranscriptionResultChanged':
        if (result is String && result.isNotEmpty) {
          results.add(SttResult(text: result, isFinal: false));
        }
      case 'SentenceEnd':
        if (result is String && result.isNotEmpty) {
          results.add(SttResult(text: result, isFinal: true));
        }
      case 'TranscriptionCompleted':
        results.close();
      case 'TaskFailed':
        if (!_ready.isCompleted) _ready.complete(false);
        final text = payload is Map ? payload['status_text'] : null;
        results.addError(SttException(text is String ? text : 'task failed'));
      // Unknown events are ignored.
    }
  }

  @override
  Future<bool> get ready => _ready.future;

  @override
  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;

    final taskId = _taskId;
    if (_socket != null && taskId != null) {
      _socket!.send(_message('StopTranscription', taskId));
    }
    await audio.stop();

    // Give the server up to [serverGrace] to emit the sentence it recognized
    // from audio already sent — closing at once drops that trailing result. But
    // bail the instant the socket closes so a server that has already hung up
    // never makes us sit out the whole window.
    await Future.any([
      _socketDone.future,
      Future<void>.delayed(serverGrace),
    ]);

    await _audioSub?.cancel();
    _audioSub = null;
    await _socketSub?.cancel();
    _socketSub = null;
    await _socket?.close();
    _socket = null;
    // Never leave a caller awaiting a session that will never go live.
    if (!_ready.isCompleted) _ready.complete(false);
    final results = _results;
    if (results != null && !results.isClosed) await results.close();
  }

  @override
  Future<int> testConnection() async {
    final stopwatch = Stopwatch()..start();
    // Throws SttException on a failed mint — the settings page surfaces it.
    final token = await tokenService.getToken(
      accessKeyId: accessKeyId,
      accessKeySecret: accessKeySecret,
    );
    final socket = await socketFactory(_gatewayUri(token));
    final taskId = idFactory();
    final completer = Completer<void>();
    final sub = socket.messages.listen(
      (dynamic data) {
        if (data is! String || completer.isCompleted) return;
        final header = _tryDecode(data)?['header'];
        final name = header is Map ? header['name'] : null;
        if (name == 'TranscriptionStarted') {
          completer.complete();
        } else if (name == 'TaskFailed') {
          completer.completeError(const SttException('task failed'));
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    socket.send(_message('StartTranscription', taskId, payload: {
      'format': 'pcm',
      'sample_rate': 16000,
    }));

    try {
      await completer.future.timeout(testConnectionTimeout);
    } finally {
      await sub.cancel();
      await socket.close();
    }
    stopwatch.stop();
    return stopwatch.elapsedMilliseconds;
  }

  @override
  void dispose() {
    _audioSub?.cancel();
    _socketSub?.cancel();
    _socket?.close();
    final results = _results;
    if (results != null && !results.isClosed) results.close();
    audio.dispose();
  }

  Uri _gatewayUri(String token) => Uri(
    scheme: 'wss',
    host: _gatewayHost,
    path: _gatewayPath,
    queryParameters: {'token': token},
  );

  String _message(String name, String taskId, {Map<String, dynamic>? payload}) =>
      jsonEncode({
        'header': {
          'appkey': appKey,
          'message_id': idFactory(),
          'task_id': taskId,
          'namespace': _namespace,
          'name': name,
        },
        if (payload != null) 'payload': payload,
      });

  Map<String, dynamic>? _tryDecode(String data) {
    try {
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
