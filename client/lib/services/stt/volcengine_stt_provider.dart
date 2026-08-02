import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:teampilot/services/stt/pcm_audio_source.dart';
import 'package:teampilot/services/stt/stt_provider.dart';
import 'package:teampilot/services/stt/volcengine_frame_codec.dart';
import 'package:teampilot/utils/logging/logger_utils.dart';

const String _endpoint =
    'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream';
const String _resourceId = 'volc.seedasr.sauc.duration';

/// Volcengine (火山引擎豆包) streaming speech recognition.
///
/// The session is a single binary WebSocket: a JSON config frame, then a run of
/// raw-PCM audio frames, each with an ascending sequence; recognition results
/// arrive as server frames decoded with [decodeVolcServerFrame]. All I/O is
/// injected ([PcmAudioSource], [SttSocketFactory]) so the provider is tested
/// without a real microphone or socket.
class VolcengineSttProvider implements SttProvider {
  VolcengineSttProvider({
    required this.audio,
    required this.socketFactory,
    required this.appId,
    required this.accessToken,
    required this.requestIdFactory,
  });

  final PcmAudioSource audio;
  final SttSocketFactory socketFactory;
  final String appId;
  final String accessToken;
  final String Function() requestIdFactory;

  StreamController<SttResult>? _results;
  SttSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  StreamSubscription<Uint8List>? _audioSub;
  int _sequence = 1;
  bool _stopping = false;
  Completer<bool> _ready = Completer<bool>();

  /// Completed the moment the socket closes, so [stop]'s grace wait can bail
  /// early instead of always sitting out the full window.
  Completer<void> _socketDone = Completer<void>();

  @override
  Future<bool> isAvailable() async =>
      appId.isNotEmpty && accessToken.isNotEmpty;

  @override
  Stream<SttResult> start({String? localeId}) {
    // A fresh future/session per start: a reused provider must report the new
    // session, not the previous verdict (see [SttProvider.ready]).
    _ready = Completer<bool>();
    _socketDone = Completer<void>();
    _sequence = 1;
    _stopping = false;
    final results = StreamController<SttResult>();
    _results = results;

    unawaited(_run(results, localeId));

    return results.stream;
  }

  Future<void> _run(
    StreamController<SttResult> results,
    String? localeId,
  ) async {
    // Refuse before opening the metered session or the microphone: audio that
    // cannot arrive should never cost a handshake.
    if (!await audio.hasPermission()) {
      if (!_ready.isCompleted) _ready.complete(false);
      if (!results.isClosed) {
        results.addError(const VoicePermissionDeniedException());
        await results.close();
      }
      return;
    }

    try {
      final socket = await socketFactory(
        Uri.parse(_endpoint),
        headers: {
          'X-Api-App-Key': appId,
          'X-Api-Access-Key': accessToken,
          'X-Api-Resource-Id': _resourceId,
          'X-Api-Request-Id': requestIdFactory(),
        },
      );
      _socket = socket;
      _socketSub = socket.messages.listen(
        _onSocketData,
        onError: (Object e, StackTrace st) {
          AppLogger.instance.w('Volcengine socket error', error: e,
              stackTrace: st);
          if (!_ready.isCompleted) _ready.complete(false);
          if (!results.isClosed) {
            results.addError(SttException('socket error: $e'));
          }
        },
        onDone: () {
          if (!_socketDone.isCompleted) _socketDone.complete();
          if (!results.isClosed) results.close();
        },
      );

      socket.send(
        buildVolcFrame(
          messageType: VolcMessageType.fullClientRequest,
          serialization: VolcSerialization.json,
          flags: 0x01,
          sequence: _sequence,
          payload: utf8.encode(jsonEncode(_buildConfig(localeId))),
        ),
      );

      final pcm = await audio.start();
      _audioSub = pcm.listen((chunk) {
        _sequence++;
        _socket?.send(
          buildVolcFrame(
            messageType: VolcMessageType.audioOnlyRequest,
            serialization: VolcSerialization.raw,
            flags: 0x00,
            sequence: _sequence,
            payload: chunk,
          ),
        );
      });

      if (!_ready.isCompleted) _ready.complete(true);
    } catch (e, st) {
      AppLogger.instance.w('Volcengine start failed', error: e, stackTrace: st);
      if (!_ready.isCompleted) _ready.complete(false);
      if (!results.isClosed) {
        results.addError(SttException('failed to start session: $e'));
        await results.close();
      }
    }
  }

  void _onSocketData(dynamic data) {
    if (data is! List<int>) return;
    final VolcFrame frame;
    try {
      frame = decodeVolcServerFrame(data);
    } on FormatException catch (e, st) {
      AppLogger.instance.w('Volcengine: dropping malformed server frame',
          error: e, stackTrace: st);
      return;
    }
    _handleServerFrame(frame);
  }

  void _handleServerFrame(VolcFrame frame) {
    final results = _results;
    if (results == null || results.isClosed) return;

    if (frame.messageType == VolcMessageType.errorResponse) {
      final message = frame.errorMessage ?? 'unknown error';
      if (!_ready.isCompleted) _ready.complete(false);
      results.addError(
        SttException('Volcengine error (${frame.errorCode}): $message'),
      );
      return;
    }
    if (frame.messageType != VolcMessageType.fullServerResponse) return;
    if (frame.payload.isEmpty) return;

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(frame.payload));
    } catch (_) {
      return; // A result body we cannot parse is dropped, not fatal.
    }
    if (decoded is! Map) return;
    final result = decoded['result'];
    if (result is! Map) return;

    final text = (result['text'] as String?) ?? '';
    if (text.isEmpty) return; // Empty interim frames carry no signal.

    final utterances = result['utterances'];
    final isLast = (frame.flags & 0x02) != 0;
    final isFinal = isLast ||
        (utterances is List &&
            utterances.isNotEmpty &&
            utterances.last is Map &&
            (utterances.last as Map)['definite'] == true);

    results.add(SttResult(text: text, isFinal: isFinal));
  }

  @override
  Future<bool> get ready => _ready.future;

  @override
  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;

    _socket?.send(
      buildVolcFrame(
        messageType: VolcMessageType.audioOnlyRequest,
        serialization: VolcSerialization.raw,
        flags: 0x03,
        sequence: -_sequence,
        payload: const [],
      ),
    );
    await audio.stop();

    // Give the server up to 3s to emit the sentence it recognized from the
    // audio already sent — closing immediately drops that trailing result. But
    // bail the instant the socket closes so a server that has already hung up
    // never makes us sit out the whole window.
    await Future.any([
      _socketDone.future,
      Future<void>.delayed(const Duration(seconds: 3)),
    ]);

    await _audioSub?.cancel();
    _audioSub = null;
    await _socketSub?.cancel();
    _socketSub = null;
    await _socket?.close();
    _socket = null;
    final results = _results;
    if (results != null && !results.isClosed) await results.close();
  }

  @override
  Future<int> testConnection() async {
    final stopwatch = Stopwatch()..start();
    final socket = await socketFactory(
      Uri.parse(_endpoint),
      headers: {
        'X-Api-App-Key': appId,
        'X-Api-Access-Key': accessToken,
        'X-Api-Resource-Id': _resourceId,
        'X-Api-Request-Id': requestIdFactory(),
      },
    );
    final completer = Completer<void>();
    final sub = socket.messages.listen(
      (dynamic data) {
        if (data is! List<int> || completer.isCompleted) return;
        try {
          final frame = decodeVolcServerFrame(data);
          if (frame.messageType == VolcMessageType.errorResponse) {
            completer.completeError(
              SttException(
                'Volcengine error (${frame.errorCode}): '
                '${frame.errorMessage ?? 'unknown error'}',
              ),
            );
          } else if (frame.messageType == VolcMessageType.fullServerResponse) {
            completer.complete();
          }
        } on FormatException {
          // Ignore a malformed probe frame; wait for a clean one or timeout.
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    socket.send(
      buildVolcFrame(
        messageType: VolcMessageType.fullClientRequest,
        serialization: VolcSerialization.json,
        flags: 0x01,
        sequence: 1,
        payload: utf8.encode(jsonEncode(_buildConfig(null))),
      ),
    );
    // One second of silence as the last packet, enough for the server to reply.
    socket.send(
      buildVolcFrame(
        messageType: VolcMessageType.audioOnlyRequest,
        serialization: VolcSerialization.raw,
        flags: 0x03,
        sequence: -2,
        payload: Uint8List(16000 * 2),
      ),
    );

    try {
      await completer.future.timeout(const Duration(seconds: 10));
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
}

/// The Volcengine session configuration payload. `enable_punc` / `enable_itn`
/// stay `true` by product decision. Language defaults to `zh-CN`.
Map<String, dynamic> _buildConfig(String? localeId) => {
      'audio': {
        'format': 'pcm',
        'rate': 16000,
        'bits': 16,
        'channel': 1,
        'language': localeId ?? 'zh-CN',
      },
      'request': {
        'model_name': 'bigmodel',
        'enable_itn': true,
        'enable_punc': true,
        'result_type': 'full',
        'show_utterances': true,
      },
    };
