import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/services/pairing/pairing_frames.dart';
import 'package:teampilot/services/pairing/pairing_rpc_handler.dart';
import 'package:teampilot/services/pairing/pairing_upload_receiver.dart';
import 'package:teampilot/services/pairing/recent_pty_buffer.dart';
import 'package:teampilot/services/pairing/session_catalog.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/workspace_dnd/runtime_target.dart';

class _MockSession extends Mock implements TerminalSession {}

/// Hand-rolled fake so the test can assert the handler's calls into the
/// receiver (begin call count, chunk args, abandonAll on dispose) and drive
/// each result independently. Private members of the real receiver are not
/// part of the interface, so `implements` only needs the public surface.
class _RecordingReceiver implements PairingUploadReceiver {
  final List<Map<String, Object?>> beginCalls = [];
  final List<List<Object?>> chunkCalls = [];
  int commitCount = 0;
  int abandonAllCount = 0;

  UploadBeginResult beginResult = const UploadBeginResult.ok(7, 64);
  UploadChunkResult chunkResult = const UploadChunkResult.ok(3);
  UploadCommitResult commitResult = const UploadCommitResult.ok(
    '/home/dev/app/photo.jpg',
  );

  @override
  UploadBeginResult begin({
    required String workspaceId,
    required String cwd,
    required String filename,
    required int size,
  }) {
    beginCalls.add({
      'workspaceId': workspaceId,
      'cwd': cwd,
      'filename': filename,
      'size': size,
    });
    return beginResult;
  }

  @override
  UploadChunkResult chunk(int transferId, int chunkIndex, List<int> bytes) {
    chunkCalls.add([transferId, chunkIndex, bytes]);
    return chunkResult;
  }

  @override
  Future<UploadCommitResult> commit(int transferId) async {
    commitCount++;
    return commitResult;
  }

  @override
  void abandon(int id) {}

  @override
  void abandonAll() => abandonAllCount++;

  @override
  PairingUploadSink get sink => throw UnimplementedError();

  @override
  int get maxBytes => 0;

  @override
  int get chunkSize => 64;
}

Future<String> _noopSink({
  required String workspaceId,
  required String cwd,
  required String filename,
  required List<int> bytes,
}) async => '';

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
      uploadSink: _noopSink,
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
      'with the pane workspaceId and cwd', () {
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
      'calls receiver.begin', () {
    handler.handle(
      PairingCodec.decode(
        _json({
          'id': 2,
          'method': 'upload.begin',
          'params': {'sub': 999, 'filename': 'photo.jpg', 'size': 1234},
        }),
      ),
    );

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

  test('an accepted chunk emits an upload.ack with transferId and received', () {
    receiver.chunkResult = const UploadChunkResult.ok(42);
    handler.handle(
      PairingCodec.decode(
        PairingCodec.encodeUpload(5, 0, Uint8List.fromList([1, 2, 3])),
      ),
    );

    final ack = jsonFrames().firstWhere(
      (f) => f.data['method'] == 'upload.ack',
    );
    final params = ack.data['params'] as Map;
    expect(params['transferId'], 5);
    expect(params['received'], 42);
  });

  test('a rejected chunk emits no upload.ack', () {
    receiver.chunkResult = const UploadChunkResult.error('write_failed');
    handler.handle(
      PairingCodec.decode(
        PairingCodec.encodeUpload(5, 0, Uint8List.fromList([1, 2, 3])),
      ),
    );

    expect(
      jsonFrames().where((f) => f.data['method'] == 'upload.ack'),
      isEmpty,
    );
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

  test('dispose abandons every unfinished transfer', () {
    handler.dispose();
    expect(receiver.abandonAllCount, 1);
  });
}
