import 'dart:async';
import 'dart:typed_data';

import 'package:teampilot/services/stt/pcm_audio_source.dart';
import 'package:teampilot/services/stt/stt_provider.dart';

/// A socket the test drives by hand: [sent] records everything the provider
/// wrote, [deliver] pushes a frame back as if the server had sent it.
class FakeSttSocket implements SttSocket {
  final _incoming = StreamController<dynamic>();
  final sent = <Object>[];
  var closed = false;

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(Object data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  void deliver(Object frame) => _incoming.add(frame);

  void failWith(Object error) => _incoming.addError(error);

  /// Server hung up without saying anything.
  Future<void> endStream() async {
    if (!_incoming.isClosed) await _incoming.close();
  }
}

/// A microphone the test drives by hand.
class FakePcmAudioSource implements PcmAudioSource {
  FakePcmAudioSource({this.permitted = true});

  final bool permitted;
  final _chunks = StreamController<Uint8List>();
  var started = false;
  var stopped = false;
  var disposed = false;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<Stream<Uint8List>> start() async {
    started = true;
    return _chunks.stream;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_chunks.isClosed) await _chunks.close();
  }

  @override
  Future<void> dispose() async => disposed = true;

  void emit(Uint8List pcm) => _chunks.add(pcm);
}
