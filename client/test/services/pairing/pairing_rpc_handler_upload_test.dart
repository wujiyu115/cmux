import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/services/pairing/pairing_frames.dart';
import 'package:teampilot/services/pairing/pairing_rpc_handler.dart';
import 'package:teampilot/services/pairing/pairing_upload_receiver.dart';
import 'package:teampilot/services/pairing/recent_pty_buffer.dart';
import 'package:teampilot/services/pairing/pairing_upload_target.dart';
import 'package:teampilot/services/pairing/session_catalog.dart';
import 'package:teampilot/services/pairing/upload_limits.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/workspace_dnd/runtime_target.dart';

import '../../support/pairing_upload_doubles.dart';

class _MockSession extends Mock implements TerminalSession {}

/// Hand-rolled fake so the test can assert the handler's calls into the
/// receiver (begin call count, chunk args, abandonAll on dispose) and drive
/// each result independently. Private members of the real receiver are not
/// part of the interface, so `implements` only needs the public surface.
class _RecordingReceiver implements PairingUploadReceiver {
  final List<Map<String, Object?>> beginCalls = [];
  final List<List<Object?>> chunkCalls = [];
  final List<int> abandonedIds = [];
  int commitCount = 0;
  int abandonAllCount = 0;

  UploadBeginResult beginResult = const UploadBeginResult.ok(7, 64);
  UploadCommitResult commitResult = const UploadCommitResult.ok(
    '/home/dev/app/photo.jpg',
  );

  @override
  Future<UploadBeginResult> begin({
    required String workspaceId,
    required String cwd,
    required String filename,
    required int size,
  }) async {
    beginCalls.add({
      'workspaceId': workspaceId,
      'cwd': cwd,
      'filename': filename,
      'size': size,
    });
    return beginResult;
  }

  @override
  void chunk(int transferId, int chunkIndex, List<int> bytes) {
    chunkCalls.add([transferId, chunkIndex, bytes]);
  }

  @override
  Future<UploadCommitResult> commit(int transferId) async {
    commitCount++;
    return commitResult;
  }

  @override
  Future<void> abandon(int id) async => abandonedIds.add(id);

  @override
  Future<void> abandonAll() async => abandonAllCount++;

  @override
  PairingUploadOpener get openTarget => throw UnimplementedError();

  @override
  void Function(int transferId, int received) get onAck =>
      throw UnimplementedError();

  @override
  PairingUploadCaps get caps => const PairingUploadCaps();

  @override
  int get chunkSize => 64;

  @override
  int get maxConcurrentTransfers => 4;
}

Uint8List _json(Map<String, Object?> data) => PairingCodec.encodeJson(data);

void main() {
  late _MockSession session;
  late StreamController<Uint8List> mirror;
  late SessionCatalog catalog;
  late List<Uint8List> sent;
  late _RecordingReceiver receiver;
  late PairingRpcHandler handler;

  setUp(() {
    session = _MockSession();
    mirror = StreamController<Uint8List>.broadcast();
    when(() => session.mirrorOutput).thenAnswer((_) => mirror.stream);
    when(() => session.viewWidth).thenReturn(100);
    when(() => session.viewHeight).thenReturn(30);
    when(() => session.recentBuffer).thenReturn(RecentPtyBuffer());
    when(() => session.attachMirror()).thenReturn(null);
    when(() => session.detachMirror()).thenReturn(null);
    // The subscribe path reads it to build the mirror's mode resync.
    when(() => session.cursorVisible).thenReturn(true);
    when(() => session.runtimeTarget).thenReturn(
      const RuntimeTarget.localPosix(workingDirectory: '/home/dev/app'),
    );

    catalog = SessionCatalog()
      ..addSource(
        () => [
          SessionCatalogEntry(
            const PairedSessionRef(
              catalogId: 'ws:p1',
              title: 'shell',
              subtitle: 'zsh',
              workspaceId: 'ws-1',
              paneId: 'p1',
            ),
            session,
          ),
        ],
      );
    sent = [];
    receiver = _RecordingReceiver();
    handler = PairingRpcHandler(
      catalog: catalog,
      send: sent.add,
      uploadOpener: noopUploadOpener,
      uploadReceiver: receiver,
    );
  });

  tearDown(() {
    handler.dispose();
    mirror.close();
  });

  /// Subscribes to `ws:p1` and returns the assigned `sub` id.
  int subscribe() {
    handler.handle(
      PairingCodec.decode(
        _json({
          'id': 1,
          'method': 'terminal.subscribe',
          'params': {'catalogId': 'ws:p1'},
        }),
      ),
    );
    final result = PairingCodec.decode(sent.first) as JsonFrame;
    sent.clear();
    return (result.data['result'] as Map)['sub'] as int;
  }

  Iterable<JsonFrame> jsonFrames() =>
      sent.map(PairingCodec.decode).whereType<JsonFrame>();

  JsonFrame lastJson() => jsonFrames().last;

  test('upload.begin on a subscribed sub replies ok and calls receiver.begin '
      'with the pane workspaceId and cwd', () async {
    final sub = subscribe();
    handler.handle(
      PairingCodec.decode(
        _json({
          'id': 2,
          'method': 'upload.begin',
          'params': {'sub': sub, 'filename': 'photo.jpg', 'size': 1234},
        }),
      ),
    );
    // begin now opens the destination, so the reply lands a microtask later.
    await Future<void>.delayed(Duration.zero);

    final result = lastJson().data['result'] as Map;
    expect(result['ok'], true);
    expect(result['transferId'], 7);
    expect(result['chunkSize'], 64);

    expect(receiver.beginCalls, hasLength(1));
    expect(receiver.beginCalls.single['workspaceId'], 'ws-1');
    expect(receiver.beginCalls.single['cwd'], '/home/dev/app');
    expect(receiver.beginCalls.single['filename'], 'photo.jpg');
    expect(receiver.beginCalls.single['size'], 1234);
  });

  test('upload.begin on an unsubscribed sub replies no_target and never '
      'calls receiver.begin', () async {
    handler.handle(
      PairingCodec.decode(
        _json({
          'id': 2,
          'method': 'upload.begin',
          'params': {'sub': 999, 'filename': 'photo.jpg', 'size': 1234},
        }),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final result = lastJson().data['result'] as Map;
    expect(result['ok'], false);
    expect(result['code'], 'no_target');
    expect(receiver.beginCalls, isEmpty);
  });

  test('an UploadFrame is handed to receiver.chunk with transferId/index/bytes',
      () {
    handler.handle(
      PairingCodec.decode(
        PairingCodec.encodeUpload(5, 2, Uint8List.fromList([9, 8, 7])),
      ),
    );

    expect(receiver.chunkCalls, hasLength(1));
    expect(receiver.chunkCalls.single[0], 5);
    expect(receiver.chunkCalls.single[1], 2);
    expect(receiver.chunkCalls.single[2], [9, 8, 7]);
  });

  group('ack wiring', () {
    // *When* to ack is the receiver's decision (a chunk that triggers a flush is
    // acked only after the write lands), so these run against the real receiver
    // and only assert that the handler turns its callback into the right frame.
    late FakeUploadOpener opener;
    late PairingRpcHandler real;

    setUp(() {
      opener = FakeUploadOpener();
      real = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: opener.call,
      );
    });

    tearDown(() => real.dispose());

    /// Subscribes on [real] and begins a 3-byte photo, returning its transferId.
    Future<({int sub, int transferId})> beginOnReal() async {
      real.handle(
        PairingCodec.decode(
          _json({
            'id': 1,
            'method': 'terminal.subscribe',
            'params': {'catalogId': 'ws:p1'},
          }),
        ),
      );
      final sub =
          ((PairingCodec.decode(sent.first) as JsonFrame).data['result']
                  as Map)['sub']
              as int;
      sent.clear();
      real.handle(
        PairingCodec.decode(
          _json({
            'id': 2,
            'method': 'upload.begin',
            'params': {'sub': sub, 'filename': 'photo.jpg', 'size': 3},
          }),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final result =
          (PairingCodec.decode(sent.last) as JsonFrame).data['result'] as Map;
      sent.clear();
      return (sub: sub, transferId: result['transferId']! as int);
    }

    Iterable<JsonFrame> acks() => sent
        .map(PairingCodec.decode)
        .whereType<JsonFrame>()
        .where((f) => f.data['method'] == 'upload.ack');

    test('an accepted chunk emits an upload.ack with transferId and received',
        () async {
      final t = await beginOnReal();
      real.handle(
        PairingCodec.decode(
          PairingCodec.encodeUpload(t.transferId, 0, Uint8List.fromList([1, 2])),
        ),
      );

      final params = acks().single.data['params'] as Map;
      expect(params['transferId'], t.transferId);
      expect(params['received'], 2);
    });

    test('a rejected chunk emits no upload.ack', () async {
      final t = await beginOnReal();
      // Index 1 with nothing at 0: a gap, which abandons the transfer.
      real.handle(
        PairingCodec.decode(
          PairingCodec.encodeUpload(t.transferId, 1, Uint8List.fromList([1])),
        ),
      );

      expect(acks(), isEmpty);
    });

    test('a chunk for an unknown transfer emits no upload.ack', () async {
      await beginOnReal();
      real.handle(
        PairingCodec.decode(
          PairingCodec.encodeUpload(999, 0, Uint8List.fromList([1])),
        ),
      );

      expect(acks(), isEmpty);
    });
  });

  test('upload.commit replies ok with the path from the receiver', () async {
    receiver.commitResult = const UploadCommitResult.ok('/home/dev/app/x.png');
    handler.handle(
      PairingCodec.decode(
        _json({
          'id': 3,
          'method': 'upload.commit',
          'params': {'transferId': 7},
        }),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(receiver.commitCount, 1);
    final result = lastJson().data['result'] as Map;
    expect(result['ok'], true);
    expect(result['path'], '/home/dev/app/x.png');
  });

  test('upload.commit relays the receiver error code', () async {
    receiver.commitResult = const UploadCommitResult.error('write_failed');
    handler.handle(
      PairingCodec.decode(
        _json({
          'id': 3,
          'method': 'upload.commit',
          'params': {'transferId': 7},
        }),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final result = lastJson().data['result'] as Map;
    expect(result['ok'], false);
    expect(result['code'], 'write_failed');
  });

  test('upload.abort abandons the transfer and replies ok', () {
    handler.handle(
      PairingCodec.decode(
        _json({
          'id': 4,
          'method': 'upload.abort',
          'params': {'transferId': 7},
        }),
      ),
    );

    expect(receiver.abandonedIds, [7]);
    expect((lastJson().data['result'] as Map)['ok'], true);
  });

  test('upload.abort for an unknown transfer still replies ok', () {
    // The phone aborts because the user tapped cancel; it has nothing useful to
    // do with a failure, and the benign race where the commit already landed must
    // not surface as an error.
    handler.handle(
      PairingCodec.decode(
        _json({
          'id': 4,
          'method': 'upload.abort',
          'params': {'transferId': 999},
        }),
      ),
    );

    expect((lastJson().data['result'] as Map)['ok'], true);
  });

  test('upload.abort without a transferId replies ok and abandons nothing', () {
    handler.handle(
      PairingCodec.decode(
        _json({'id': 4, 'method': 'upload.abort', 'params': <String, Object?>{}}),
      ),
    );

    expect(receiver.abandonedIds, isEmpty);
    expect((lastJson().data['result'] as Map)['ok'], true);
  });

  test('dispose abandons every unfinished transfer', () {
    // Not only to release memory: each live transfer owns a part-file in the
    // user's working directory, and abandoning is what deletes it.
    handler.dispose();
    expect(receiver.abandonAllCount, 1);
  });
}
