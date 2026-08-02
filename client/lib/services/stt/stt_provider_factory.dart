import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../repositories/voice_input_repository.dart';
import 'aliyun_stt_provider.dart';
import 'aliyun_token_service.dart';
import 'pcm_audio_source.dart';
import 'speech_recognizer.dart';
import 'stt_provider.dart';
import 'stt_socket.dart';
import 'system_stt_provider.dart';
import 'volcengine_stt_provider.dart';

/// Builds the concrete [SttProvider] for [type], wiring in its real audio
/// source, socket, and (for Aliyun) token service. Passed to [VoiceInputCubit]
/// so the cubit stays free of platform plugins and tests can swap in a fake.
SttProvider buildSttProvider(SttProviderType type, VoiceCredentials creds) =>
    switch (type) {
      SttProviderType.system => SystemSttProvider(PluginSpeechRecognizer()),
      SttProviderType.volcengine => VolcengineSttProvider(
        audio: RecordPcmAudioSource(),
        socketFactory: WebSocketSttSocket.connect,
        appId: creds.volcAppId,
        accessToken: creds.volcAccessToken,
        requestIdFactory: () => const Uuid().v4(),
      ),
      SttProviderType.aliyun => AliyunSttProvider(
        audio: RecordPcmAudioSource(),
        socketFactory: WebSocketSttSocket.connect,
        tokenService: AliyunTokenService(
          client: http.Client(),
          nonceFactory: () => const Uuid().v4(),
          now: DateTime.now,
        ),
        accessKeyId: creds.aliyunAccessKeyId,
        accessKeySecret: creds.aliyunAccessKeySecret,
        appKey: creds.aliyunAppKey,
        // Alibaba wants a 32-char hex id; a v4 UUID minus its four hyphens is
        // exactly 32 hex chars.
        idFactory: () => const Uuid().v4().replaceAll('-', ''),
      ),
    };
