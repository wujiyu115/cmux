import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/stt/stt_provider.dart';
import 'package:teampilot/services/stt/volcengine_frame_codec.dart';
import 'package:teampilot/services/stt/volcengine_stt_provider.dart';

import 'stt_test_doubles.dart';

void main() {
  late FakeSttSocket socket;
  late FakePcmAudioSource audio;
  late Uri connectedTo;
  late Map<String, String>? sentHeaders;

  VolcengineSttProvider build({bool permitted = true}) {
    audio = FakePcmAudioSource(permitted: permitted);
    socket = FakeSttSocket();
    return VolcengineSttProvider(
      audio: audio,
      socketFactory: (url, {headers}) async {
        connectedTo = url;
        sentHeaders = headers;
        return socket;
      },
      appId: 'app-id',
      accessToken: 'access-token',
      requestIdFactory: () => 'request-id',
    );
  }

  /// The parsed frames the provider wrote, in order.
  List<VolcFrame> writtenFrames() =>
      socket.sent.map((f) => parseVolcFrame(f as List<int>)).toList();

  /// A server result frame carrying [text].
  ///
  /// Built with [buildVolcFrame] using `flags: 0x01`, which places an int32
  /// sequence at offset 4 followed by the uint32 body length — exactly the
  /// layout [decodeVolcServerFrame] reads when `flags & 0x01` is set. (The
  /// brief's original `flags: 0x00` produced an encoder-only layout that the
  /// real inbound decoder cannot parse, since it would read the sequence field
  /// as the payload length.)
  Uint8List resultFrame({
    required String text,
    required bool definite,
    int sequence = 1,
  }) {
    return buildVolcFrame(
      messageType: VolcMessageType.fullServerResponse,
      serialization: VolcSerialization.json,
      flags: 0x01,
      sequence: sequence,
      payload: utf8.encode(
        jsonEncode({
          'result': {
            'text': text,
            'utterances': [
              {'text': text, 'definite': definite},
            ],
          },
        }),
      ),
    );
  }

  /// A server *error* frame shaped the way [decodeVolcServerFrame] expects:
  /// a 4-byte header, then (no sequence / no event because flags are clear)
  /// an int32 error code, a uint32 message length, and the PLAIN UTF-8 message
  /// (never gzipped). [buildVolcFrame] cannot produce this — it gzips the body
  /// and lays out sequence+length instead of code+length — so we build it by
  /// hand to exercise the real inbound decoder.
  Uint8List serverErrorFrame({
    required int code,
    required String message,
  }) {
    final msg = utf8.encode(message);
    final frame = Uint8List(12 + msg.length);
    frame[0] = 0x11; // header size 1 => 4 bytes.
    frame[1] = (VolcMessageType.errorResponse << 4) | 0x00; // no seq, no event.
    frame[2] = (VolcSerialization.json << 4) | 0x00;
    frame[3] = 0x00;
    final header = ByteData.sublistView(frame, 0, 12);
    header.setInt32(4, code);
    header.setUint32(8, msg.length);
    frame.setRange(12, 12 + msg.length, msg);
    return frame;
  }

  test('connects with the documented endpoint and headers', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(connectedTo.scheme, 'wss');
    expect(connectedTo.host, 'openspeech.bytedance.com');
    expect(connectedTo.path, '/api/v3/sauc/bigmodel_nostream');
    expect(sentHeaders, {
      'X-Api-App-Key': 'app-id',
      'X-Api-Access-Key': 'access-token',
      'X-Api-Resource-Id': 'volc.seedasr.sauc.duration',
      'X-Api-Request-Id': 'request-id',
    });
    await provider.stop();
  });

  test('sends the config frame before any audio', () async {
    final provider = build();
    provider.start(localeId: 'en-US').listen((_) {});
    await Future<void>.delayed(Duration.zero);

    final first = writtenFrames().first;
    expect(first.messageType, VolcMessageType.fullClientRequest);
    final config = jsonDecode(utf8.decode(first.payload)) as Map;
    expect((config['audio'] as Map)['rate'], 16000);
    expect((config['audio'] as Map)['language'], 'en-US');
    expect((config['request'] as Map)['enable_punc'], isTrue);
    expect((config['request'] as Map)['enable_itn'], isTrue);
    await provider.stop();
  });

  test('defaults the language to zh-CN when no locale is chosen', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    final config =
        jsonDecode(utf8.decode(writtenFrames().first.payload)) as Map;
    expect((config['audio'] as Map)['language'], 'zh-CN');
    await provider.stop();
  });

  test('forwards audio chunks as raw-serialization frames, in order', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    audio.emit(Uint8List.fromList(List.filled(320, 1)));
    audio.emit(Uint8List.fromList(List.filled(320, 2)));
    await Future<void>.delayed(Duration.zero);

    final frames = writtenFrames();
    expect(frames, hasLength(3), reason: 'config + two audio frames');
    expect(frames[1].messageType, VolcMessageType.audioOnlyRequest);
    expect(frames[1].payload.first, 1);
    expect(frames[2].payload.first, 2);
    expect(
      frames[2].sequence,
      greaterThan(frames[1].sequence),
      reason: 'the server orders audio by sequence',
    );
    await provider.stop();
  });

  test('stop sends a negative-sequence last packet', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    audio.emit(Uint8List.fromList(List.filled(320, 1)));
    await Future<void>.delayed(Duration.zero);

    await provider.stop();

    final last = writtenFrames().last;
    expect(last.sequence, isNegative, reason: 'negation marks the end');
    expect(last.flags, 0x03);
    expect(audio.stopped, isTrue);
  });

  test('emits an interim result then a definite one', () async {
    final provider = build();
    final results = <SttResult>[];
    provider.start().listen(results.add);
    await Future<void>.delayed(Duration.zero);

    socket.deliver(resultFrame(text: 'git', definite: false));
    socket.deliver(resultFrame(text: 'git commit', definite: true));
    await Future<void>.delayed(Duration.zero);

    expect(results.map((r) => r.text), ['git', 'git commit']);
    expect(results.map((r) => r.isFinal), [false, true]);
    await provider.stop();
  });

  test('turns an error frame into an SttException on the stream', () async {
    final provider = build();
    final stream = provider.start();
    final errors = <Object>[];
    stream.listen((_) {}, onError: errors.add);
    await Future<void>.delayed(Duration.zero);

    // A server-shaped error frame (see [serverErrorFrame]); the provider
    // decodes it with decodeVolcServerFrame and surfaces the plain-text message.
    socket.deliver(serverErrorFrame(code: 45000001, message: 'invalid token'));
    await Future<void>.delayed(Duration.zero);

    expect(errors.single, isA<SttException>());
    expect((errors.single as SttException).message, contains('invalid token'));
    await provider.stop();
  });

  test('errors with VoicePermissionDeniedException and never connects',
      () async {
    // Opening a paid cloud session the user cannot speak into wastes a
    // handshake and leaks the fact that they tried; refuse before connecting.
    final provider = build(permitted: false);
    await expectLater(
      provider.start(),
      emitsError(isA<VoicePermissionDeniedException>()),
    );
    expect(audio.started, isFalse);
  });

  test('ready resolves true once the config frame is out', () async {
    final provider = build();
    provider.start().listen((_) {});
    expect(await provider.ready, isTrue);
    expect(audio.started, isTrue);
    await provider.stop();
  });

  test('ready resolves false when the mic is refused', () async {
    final provider = build(permitted: false);
    provider.start().listen((_) {}, onError: (_) {});
    expect(await provider.ready, isFalse);
  });

  test('closes the socket and the microphone on stop', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await provider.stop();
    expect(socket.closed, isTrue);
    expect(audio.stopped, isTrue);
  });

  test('stop is safe to call twice', () async {
    // The composer stops on close, on mode change and on dispose; two of those
    // can fire for one user action.
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await provider.stop();
    await expectLater(provider.stop(), completes);
  });
}
