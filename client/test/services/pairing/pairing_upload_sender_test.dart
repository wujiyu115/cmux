import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/pairing_frames.dart';
import 'package:teampilot/services/pairing/pairing_upload_sender.dart';
import 'package:teampilot/services/pairing/upload_source.dart';

void main() {
  late List<({String method, Map<String, Object?> params})> calls;
  late List<Uint8List> sentFrames;
  late StreamController<PairingUploadAck> acks;
  late Map<String, Object?> beginReply;
  late Map<String, Object?> commitReply;
  late Object? rpcError;

  /// The upload frames the sender wrote, decoded.
  List<UploadFrame> uploads() =>
      sentFrames.map((f) => PairingCodec.decode(f) as UploadFrame).toList();

  PairingUploadSender build({
    int windowChunks = 2,
    Duration ackTimeout = const Duration(seconds: 30),
  }) {
    return PairingUploadSender(
      windowChunks: windowChunks,
      ackTimeout: ackTimeout,
      acks: acks.stream,
      send: sentFrames.add,
      rpc: (method, params) async {
        calls.add((method: method, params: params));
        final error = rpcError;
        if (error != null) throw error;
        return method == 'upload.begin' ? beginReply : commitReply;
      },
    );
  }

  setUp(() {
    calls = [];
    sentFrames = [];
    acks = StreamController<PairingUploadAck>.broadcast();
    rpcError = null;
    beginReply = {'ok': true, 'transferId': 7, 'chunkSize': 4};
    commitReply = {'ok': true, 'path': '/home/dev/app/photo.jpg'};
  });

  tearDown(() => acks.close());

  Uint8List payload(int length) =>
      Uint8List.fromList(List.generate(length, (i) => i % 256));

  test('begins, chunks in order, then commits and returns the host path',
      () async {
    final path = await build(windowChunks: 100).upload(
      sub: 3,
      filename: 'photo.jpg',
      source: MemoryUploadSource(payload(10)),
    );

    expect(path, '/home/dev/app/photo.jpg');
    expect(calls.first.method, 'upload.begin');
    expect(calls.first.params, {'sub': 3, 'filename': 'photo.jpg', 'size': 10});
    expect(calls.last.method, 'upload.commit');
    expect(calls.last.params, {'transferId': 7});

    final frames = uploads();
    expect(frames, hasLength(3), reason: '10 bytes at a chunk size of 4');
    expect(frames.map((f) => f.chunkIndex), [0, 1, 2]);
    expect(frames.every((f) => f.transferId == 7), isTrue);
    expect(frames[0].bytes, hasLength(4));
    expect(frames[2].bytes, hasLength(2), reason: 'the tail is short');
  });

  test('slices by the chunk size the host chose, not a hardcoded one',
      () async {
    // The host dictates chunk size so it can be retuned without shipping a new
    // phone build.
    beginReply = {'ok': true, 'transferId': 1, 'chunkSize': 3};
    await build(
      windowChunks: 100,
    ).upload(sub: 1, filename: 'a.png', source: MemoryUploadSource(payload(9)));
    expect(uploads(), hasLength(3));
    expect(uploads().first.bytes, hasLength(3));
  });

  test('holds at the credit window until an ack arrives', () async {
    // The point of the window: without it, 25 MB of chunks go into an unbounded
    // socket buffer at once. windowChunks 2 x chunkSize 4 = 8 bytes in flight.
    final sender = build(windowChunks: 2);
    final done = sender.upload(sub: 1, filename: 'a.png', source: MemoryUploadSource(payload(20)));

    await Future<void>.delayed(Duration.zero);
    expect(uploads(), hasLength(2), reason: 'window full, must wait');

    acks.add(const PairingUploadAck(transferId: 7, received: 8));
    await Future<void>.delayed(Duration.zero);
    expect(uploads(), hasLength(4), reason: 'window reopened by one full ack');

    acks.add(const PairingUploadAck(transferId: 7, received: 20));
    await done;
    expect(uploads(), hasLength(5));
  });

  test('ignores acks belonging to a different transfer', () async {
    final sender = build(windowChunks: 2);
    final done = sender.upload(sub: 1, filename: 'a.png', source: MemoryUploadSource(payload(20)));
    await Future<void>.delayed(Duration.zero);

    acks.add(const PairingUploadAck(transferId: 999, received: 20));
    await Future<void>.delayed(Duration.zero);
    expect(uploads(), hasLength(2), reason: 'still blocked');

    acks.add(const PairingUploadAck(transferId: 7, received: 20));
    await done;
  });

  test('throws with the host code and sends nothing when begin is refused',
      () async {
    // A rejected begin must not put a single byte on the wire.
    beginReply = {'ok': false, 'code': 'too_large'};
    await expectLater(
      build().upload(sub: 1, filename: 'huge.png', source: MemoryUploadSource(payload(20))),
      throwsA(
        isA<PairingUploadException>().having((e) => e.code, 'code', 'too_large'),
      ),
    );
    expect(sentFrames, isEmpty);
    expect(calls.map((c) => c.method), ['upload.begin']);
  });

  test('throws when commit reports a failure', () async {
    commitReply = {'ok': false, 'code': 'write_failed'};
    await expectLater(
      build(
        windowChunks: 100,
      ).upload(sub: 1, filename: 'a.png', source: MemoryUploadSource(payload(4))),
      throwsA(
        isA<PairingUploadException>().having(
          (e) => e.code,
          'code',
          'write_failed',
        ),
      ),
    );
  });

  test('propagates an rpc failure and never commits', () async {
    rpcError = TimeoutException('RPC upload.begin timed out');
    await expectLater(
      build().upload(sub: 1, filename: 'a.png', source: MemoryUploadSource(payload(4))),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls.map((c) => c.method), ['upload.begin']);
  });

  test('times out waiting for an ack that never comes', () async {
    final sender = build(
      windowChunks: 1,
      ackTimeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      sender.upload(sub: 1, filename: 'a.png', source: MemoryUploadSource(payload(20))),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('reports progress monotonically, ending at the total', () async {
    final seen = <int>[];
    await build(windowChunks: 100).upload(
      sub: 1,
      filename: 'a.png',
      source: MemoryUploadSource(payload(10)),
      onProgress: (sent, total) {
        expect(total, 10);
        seen.add(sent);
      },
    );
    expect(seen, [4, 8, 10]);
  });

  test('handles an empty payload without sending a chunk', () async {
    // Degenerate but reachable if a picker returns a zero-byte file; it must
    // commit rather than hang.
    final path = await build().upload(
      sub: 1,
      filename: 'a.png',
      source: MemoryUploadSource(Uint8List(0)),
    );
    expect(path, '/home/dev/app/photo.jpg');
    expect(sentFrames, isEmpty);
    expect(calls.map((c) => c.method), ['upload.begin', 'upload.commit']);
  });

  test('a source that runs short of its declared length still commits, and the '
      'host rejects it', () async {
    // The truncation guard is the host's `received != declaredSize` check, not a
    // local one: stopping at the short read and letting the host refuse the
    // commit is what keeps a half-written file off the desktop.
    commitReply = {'ok': false, 'code': 'write_failed'};
    await expectLater(
      build(windowChunks: 100).upload(
        sub: 1,
        filename: 'clip.mp4',
        source: _ShortSource(declared: 10, available: 6),
      ),
      throwsA(
        isA<PairingUploadException>().having(
          (e) => e.code,
          'code',
          'write_failed',
        ),
      ),
    );
    expect(calls.map((c) => c.method), ['upload.begin', 'upload.commit']);
    expect(calls.first.params['size'], 10, reason: 'begin declares the stat');
    expect(
      uploads().fold<int>(0, (sum, f) => sum + f.bytes.length),
      6,
      reason: 'only what was actually readable went on the wire',
    );
  });

  group('cancel', () {
    test('cancelling during begin sends no chunk and aborts the transfer',
        () async {
      // The host has already created a part-file by the time begin replies, so
      // this has to reach it even though nothing was ever sent.
      final sender = build(windowChunks: 100);
      sender.cancel();

      await expectLater(
        sender.upload(
          sub: 1,
          filename: 'clip.mp4',
          source: MemoryUploadSource(payload(10)),
        ),
        throwsA(isA<PairingUploadCancelled>()),
      );
      expect(sentFrames, isEmpty);
      expect(calls.map((c) => c.method), ['upload.begin', 'upload.abort']);
      expect(calls.last.params['transferId'], 7);
    });

    test('cancelling while blocked on the ack window releases the wait',
        () async {
      // Without waking the ack wait, cancel would not take effect until the
      // 30-second timeout — on a slow link that is the whole point of the button.
      final sender = build(windowChunks: 2);
      final done = sender.upload(
        sub: 1,
        filename: 'clip.mp4',
        source: MemoryUploadSource(payload(20)),
      );
      await pumpEventQueue();
      expect(uploads(), hasLength(2), reason: 'window full, no acks yet');

      sender.cancel();

      await expectLater(done, throwsA(isA<PairingUploadCancelled>()));
      expect(uploads(), hasLength(2), reason: 'nothing more went out');
      expect(calls.map((c) => c.method), ['upload.begin', 'upload.abort']);
    });

    test('cancelling mid-stream stops at a chunk boundary', () async {
      final sender = build(windowChunks: 100);
      final done = sender.upload(
        sub: 1,
        filename: 'clip.mp4',
        source: _CancelAfterFirstRead(sender: sender, bytes: payload(20)),
      );

      await expectLater(done, throwsA(isA<PairingUploadCancelled>()));
      expect(uploads(), hasLength(1), reason: 'the chunk in hand still went out');
      expect(calls.map((c) => c.method), ['upload.begin', 'upload.abort']);
    });

    test('a commit that lands after cancel does not return a path', () async {
      // Benign race: the host dropped the transfer before writing, so the file
      // lands. Discarding the path is what keeps it out of the composer.
      final sender = build(windowChunks: 100);
      final done = sender.upload(
        sub: 1,
        filename: 'clip.mp4',
        source: _CancelAtEof(sender: sender, bytes: payload(4)),
      );

      await expectLater(done, throwsA(isA<PairingUploadCancelled>()));
      expect(calls.map((c) => c.method), ['upload.begin', 'upload.commit']);
    });

    test('cancel is idempotent and harmless after the upload finished',
        () async {
      final sender = build(windowChunks: 100);
      await sender.upload(
        sub: 1,
        filename: 'a.png',
        source: MemoryUploadSource(payload(4)),
      );
      sender.cancel();
      sender.cancel();
      expect(sender.isCancelled, isTrue);
      expect(calls.map((c) => c.method), ['upload.begin', 'upload.commit']);
    });
  });

  test('stops listening to acks once the upload settles', () async {
    // A leaked subscription on a broadcast stream would outlive every upload,
    // one per attempt, for the life of the connection.
    await build(
      windowChunks: 100,
    ).upload(sub: 1, filename: 'a.png', source: MemoryUploadSource(payload(4)));
    expect(acks.hasListener, isFalse);
  });
}

/// Claims [declared] bytes but only ever yields [available] — a file truncated
/// between the pick and the transfer.
class _ShortSource implements UploadSource {
  _ShortSource({required this.declared, required this.available});

  final int declared;
  final int available;
  int _offset = 0;

  @override
  int get length => declared;

  @override
  Future<Uint8List> read(int maxBytes) async {
    final end = _offset + maxBytes;
    final stop = end < available ? end : available;
    final out = Uint8List(stop - _offset);
    _offset = stop;
    return out;
  }

  @override
  Future<void> close() async {}
}

/// Cancels its sender the moment the first chunk has been read, so the loop
/// notices at the next boundary.
class _CancelAfterFirstRead implements UploadSource {
  _CancelAfterFirstRead({required this.sender, required this.bytes})
    : _inner = MemoryUploadSource(bytes);

  final PairingUploadSender sender;
  final Uint8List bytes;
  final MemoryUploadSource _inner;
  var _reads = 0;

  @override
  int get length => bytes.length;

  @override
  Future<Uint8List> read(int maxBytes) async {
    final out = await _inner.read(maxBytes);
    if (_reads++ == 0) sender.cancel();
    return out;
  }

  @override
  Future<void> close() => _inner.close();
}

/// Cancels its sender only once the payload is exhausted, so the loop exits
/// normally and the cancel lands while `upload.commit` is in flight.
class _CancelAtEof implements UploadSource {
  _CancelAtEof({required this.sender, required this.bytes});

  final PairingUploadSender sender;
  final Uint8List bytes;
  var _offset = 0;

  @override
  int get length => bytes.length;

  @override
  Future<Uint8List> read(int maxBytes) async {
    final end = _offset + maxBytes;
    final stop = end < bytes.length ? end : bytes.length;
    final out = Uint8List.sublistView(bytes, _offset, stop);
    _offset = stop;
    if (_offset >= bytes.length) sender.cancel();
    return out;
  }

  @override
  Future<void> close() async {}
}
