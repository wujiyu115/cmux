import 'dart:typed_data';

import 'package:record/record.dart';

/// A stream of raw 16 kHz / 16-bit / mono PCM — the format both cloud
/// recognizers want.
///
/// Abstract for the same reason as [SpeechRecognizer]: `AudioRecorder` is a
/// concrete plugin class, and the cloud providers' tests must not open a
/// microphone.
abstract class PcmAudioSource {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> dispose();
}

class RecordPcmAudioSource implements PcmAudioSource {
  RecordPcmAudioSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      numChannels: 1,
      sampleRate: 16000,
    ),
  );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() async => _recorder.dispose();
}
