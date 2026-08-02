import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/stt/aliyun_stt_provider.dart';
import 'package:teampilot/services/stt/aliyun_token_service.dart';
import 'package:teampilot/services/stt/stt_provider.dart';

import 'stt_test_doubles.dart';

void main() {
  late FakeSttSocket socket;
  late FakePcmAudioSource audio;
  late Uri connectedTo;
  late int idCalls;
  late int tokenCalls;

  AliyunSttProvider build({
    bool permitted = true,
    int tokenStatus = 200,
    // Zero grace so stop() never sits out the production 2s wait; the
    // Future.any race is still exercised, it just resolves on the (zero) timer
    // or the socket, whichever lands first.
    Duration serverGrace = Duration.zero,
    Duration testConnectionTimeout = const Duration(seconds: 10),
  }) {
    audio = FakePcmAudioSource(permitted: permitted);
    socket = FakeSttSocket();
    idCalls = 0;
    tokenCalls = 0;
    return AliyunSttProvider(
      audio: audio,
      socketFactory: (url, {headers}) async {
        connectedTo = url;
        return socket;
      },
      tokenService: AliyunTokenService(
        client: MockClient(
          (_) async {
            tokenCalls++;
            return http.Response(
              jsonEncode({
                'Token': {'Id': 'the-token', 'ExpireTime': 4102444800},
              }),
              tokenStatus,
            );
          },
        ),
        nonceFactory: () => 'nonce',
        now: () => DateTime.utc(2026, 8, 2, 12),
      ),
      accessKeyId: 'id',
      accessKeySecret: 'secret',
      appKey: 'app-key',
      idFactory: () => 'id-${++idCalls}',
      serverGrace: serverGrace,
      testConnectionTimeout: testConnectionTimeout,
    );
  }

  /// The JSON messages the provider wrote, in order.
  List<Map<String, dynamic>> jsonSent() => socket.sent
      .whereType<String>()
      .map((s) => jsonDecode(s) as Map<String, dynamic>)
      .toList();

  /// The binary payloads the provider wrote.
  List<Object> binarySent() =>
      socket.sent.where((s) => s is! String).toList();

  /// A server event.
  String event(String name, {Map<String, dynamic>? payload}) => jsonEncode({
    'header': {'name': name, 'status': 20000000},
    if (payload != null) 'payload': payload,
  });

  test('puts the minted token in the gateway URL', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(connectedTo.host, 'nls-gateway-cn-shanghai.aliyuncs.com');
    expect(connectedTo.path, '/ws/v1');
    expect(connectedTo.queryParameters['token'], 'the-token');
    await provider.stop();
  });

  test('sends StartTranscription with the documented payload', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    final start = jsonSent().single;
    expect(start['header']['name'], 'StartTranscription');
    expect(start['header']['namespace'], 'SpeechTranscriber');
    expect(start['header']['appkey'], 'app-key');
    expect(start['payload']['sample_rate'], 16000);
    expect(start['payload']['max_sentence_silence'], 800);
    expect(start['payload']['enable_punctuation_prediction'], isTrue);
    expect(start['payload']['enable_inverse_text_normalization'], isTrue);
    await provider.stop();
  });

  test('does not send PCM before TranscriptionStarted arrives', () async {
    // Audio sent ahead of the acknowledgement is discarded and the gateway
    // drops the task — the symptom is a session that connects fine and
    // recognizes nothing, with no error anywhere.
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    audio.emit(Uint8List.fromList(List.filled(320, 7)));
    await Future<void>.delayed(Duration.zero);
    expect(binarySent(), isEmpty);

    socket.deliver(event('TranscriptionStarted'));
    await Future<void>.delayed(Duration.zero);
    audio.emit(Uint8List.fromList(List.filled(320, 8)));
    await Future<void>.delayed(Duration.zero);
    expect(binarySent(), hasLength(1));
    await provider.stop();
  });

  test('reuses one task_id and a fresh message_id per message', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    socket.deliver(event('TranscriptionStarted'));
    await Future<void>.delayed(Duration.zero);
    await provider.stop();

    final messages = jsonSent();
    expect(messages, hasLength(2), reason: 'start then stop');
    final taskIds = messages.map((m) => m['header']['task_id']).toSet();
    expect(taskIds, hasLength(1), reason: 'one task per session');
    final messageIds = messages.map((m) => m['header']['message_id']).toSet();
    expect(messageIds, hasLength(2), reason: 'ids are per message');
  });

  test('maps TranscriptionResultChanged to a partial result', () async {
    final provider = build();
    final results = <SttResult>[];
    provider.start().listen(results.add);
    await Future<void>.delayed(Duration.zero);
    socket.deliver(event('TranscriptionStarted'));
    socket.deliver(
      event('TranscriptionResultChanged', payload: {'result': 'git'}),
    );
    await Future<void>.delayed(Duration.zero);

    expect(results.single.text, 'git');
    expect(results.single.isFinal, isFalse);
    await provider.stop();
  });

  test('maps SentenceEnd to a final result', () async {
    final provider = build();
    final results = <SttResult>[];
    provider.start().listen(results.add);
    await Future<void>.delayed(Duration.zero);
    socket.deliver(event('TranscriptionStarted'));
    socket.deliver(event('SentenceEnd', payload: {'result': 'git commit'}));
    await Future<void>.delayed(Duration.zero);

    expect(results.single.text, 'git commit');
    expect(results.single.isFinal, isTrue);
    await provider.stop();
  });

  test('turns TaskFailed into an SttException on the stream', () async {
    final provider = build();
    final errors = <Object>[];
    provider.start().listen((_) {}, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    socket.deliver(
      jsonEncode({
        'header': {'name': 'TaskFailed', 'status': 40000000},
        'payload': {'status_text': 'gateway rejected the task'},
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(errors.single, isA<SttException>());
  });

  test('closes the stream on TranscriptionCompleted', () async {
    final provider = build();
    final done = provider.start().listen((_) {}).asFuture<void>();
    await Future<void>.delayed(Duration.zero);
    socket.deliver(event('TranscriptionStarted'));
    socket.deliver(event('TranscriptionCompleted'));
    await expectLater(done, completes);
  });

  test('errors with VoicePermissionDeniedException before minting a token',
      () async {
    // Minting a token is a signed API call. Doing it for a session the user
    // cannot speak into spends quota for nothing.
    final provider = build(permitted: false);
    await expectLater(
      provider.start(),
      emitsError(isA<VoicePermissionDeniedException>()),
    );
    expect(audio.started, isFalse);
    expect(tokenCalls, isZero, reason: 'no signed token call before mic check');
  });

  test('errors with SttException when the token call fails', () async {
    final provider = build(tokenStatus: 403);
    await expectLater(provider.start(), emitsError(isA<SttException>()));
  });

  test('ready resolves true only after TranscriptionStarted', () async {
    // This is the visible half of the PCM gate: the mic button must not claim
    // to be listening while the gateway is still discarding audio.
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    var resolved = false;
    // ignore: unawaited_futures
    provider.ready.then((_) => resolved = true);
    await Future<void>.delayed(Duration.zero);
    expect(resolved, isFalse);

    socket.deliver(event('TranscriptionStarted'));
    expect(await provider.ready, isTrue);
    await provider.stop();
  });

  test('ready resolves false when the token call fails', () async {
    final provider = build(tokenStatus: 403);
    provider.start().listen((_) {}, onError: (_) {});
    expect(await provider.ready, isFalse);
  });

  test('stop sends StopTranscription and closes both ends', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    socket.deliver(event('TranscriptionStarted'));
    await Future<void>.delayed(Duration.zero);

    await provider.stop();

    expect(jsonSent().last['header']['name'], 'StopTranscription');
    expect(socket.closed, isTrue);
    expect(audio.stopped, isTrue);
  });

  test('stop is safe to call twice', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await provider.stop();
    await expectLater(provider.stop(), completes);
  });

  test('isAvailable requires all three credentials', () async {
    expect(await build().isAvailable(), isTrue);
    final missingAppKey = AliyunSttProvider(
      audio: FakePcmAudioSource(),
      socketFactory: (url, {headers}) async => FakeSttSocket(),
      tokenService: AliyunTokenService(
        client: MockClient((_) async => http.Response('{}', 200)),
        nonceFactory: () => 'nonce',
        now: DateTime.now,
      ),
      accessKeyId: 'id',
      accessKeySecret: 'secret',
      appKey: '',
      idFactory: () => 'id',
    );
    expect(await missingAppKey.isAvailable(), isFalse);
  });

  test('testConnection measures latency to TranscriptionStarted', () async {
    final provider = build();
    final probe = provider.testConnection();
    await Future<void>.delayed(Duration.zero);

    // The probe opened the documented gateway and sent a StartTranscription —
    // asserting these, not a Stopwatch reading that is >= 0 by construction.
    expect(connectedTo.host, 'nls-gateway-cn-shanghai.aliyuncs.com');
    final sent = jsonSent().single;
    expect(sent['header']['name'], 'StartTranscription');

    socket.deliver(event('TranscriptionStarted'));
    await probe;
    expect(socket.closed, isTrue, reason: 'probe must not leak the session');
  });

  test('testConnection throws SttException on TaskFailed', () async {
    final provider = build();
    final probe = provider.testConnection();
    await Future<void>.delayed(Duration.zero);

    socket.deliver(
      jsonEncode({
        'header': {'name': 'TaskFailed', 'status': 40000000},
        'payload': {'status_text': 'gateway rejected the task'},
      }),
    );

    await expectLater(probe, throwsA(isA<SttException>()));
    expect(socket.closed, isTrue);
  });

  test('testConnection throws TimeoutException when the server never replies',
      () async {
    // Zero timeout so the test does not spend the production 10 real seconds.
    final provider = build(testConnectionTimeout: Duration.zero);
    await expectLater(
      provider.testConnection(),
      throwsA(isA<TimeoutException>()),
    );
    expect(socket.closed, isTrue);
  });
}
