import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/services/pairing/pairing_frames.dart';
import 'package:teampilot/services/pairing/pairing_rpc_handler.dart';
import 'package:teampilot/services/pairing/pairing_workspace_index.dart';
import 'package:teampilot/services/pairing/recent_pty_buffer.dart';
import 'package:teampilot/services/pairing/session_catalog.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

class _MockSession extends Mock implements TerminalSession {}

Uint8List _json(Map<String, Object?> data) => PairingCodec.encodeJson(data);

Future<String> _noopSink({
  required String workspaceId,
  required String cwd,
  required String filename,
  required List<int> bytes,
}) async => '';

void main() {
  setUpAll(() => registerFallbackValue(Uint8List(0)));

  late _MockSession session;
  late StreamController<Uint8List> mirror;
  late SessionCatalog catalog;
  late List<Uint8List> sent;
  late PairingRpcHandler handler;

  SessionCatalogEntry makeEntry() => SessionCatalogEntry(
    const PairedSessionRef(
      catalogId: 'ws:p1',
      title: 'shell',
      subtitle: 'zsh',
      workspaceId: 'wsA',
      paneId: 'p1',
    ),
    session,
  );

  setUp(() {
    session = _MockSession();
    mirror = StreamController<Uint8List>.broadcast();
    when(() => session.mirrorOutput).thenAnswer((_) => mirror.stream);
    when(() => session.viewWidth).thenReturn(100);
    when(() => session.viewHeight).thenReturn(30);
    when(() => session.recentBuffer).thenReturn(null);
    when(() => session.writeRemoteInput(any())).thenReturn(null);
    when(() => session.onTerminalPtyResize(any(), any())).thenReturn(null);
    when(() => session.attachMirror()).thenReturn(null);
    when(() => session.detachMirror()).thenReturn(null);

    catalog = SessionCatalog()..addSource(() => [makeEntry()]);
    sent = [];
    handler = PairingRpcHandler(
      catalog: catalog,
      send: sent.add,
      uploadSink: _noopSink,
      batchWindow: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    handler.dispose();
    mirror.close();
  });

  PairingFrame decodeLast() => PairingCodec.decode(sent.last);

  test('session.list reports catalog entries with live cols/rows', () {
    handler.handle(PairingCodec.decode(_json({'id': 1, 'method': 'session.list'})));
    final frame = decodeLast() as JsonFrame;
    final sessions = (frame.data['result'] as Map)['sessions'] as List;
    expect(sessions, hasLength(1));
    final s = sessions.single as Map;
    expect(s['catalogId'], 'ws:p1');
    expect(s['cols'], 100);
    expect(s['rows'], 30);
  });

  test('subscribe replies sub/cols/rows/seq and sends snapshot first', () async {
    final buffer = RecentPtyBuffer()..append(Uint8List.fromList([1, 2, 3]));
    when(() => session.recentBuffer).thenReturn(buffer);

    handler.handle(
      PairingCodec.decode(_json({
        'id': 7,
        'method': 'terminal.subscribe',
        'params': {'catalogId': 'ws:p1'},
      })),
    );

    // Two frames: the RPC result, then the snapshot binary frame.
    final result = PairingCodec.decode(sent[0]) as JsonFrame;
    final res = result.data['result'] as Map;
    expect(res['sub'], 1);
    expect(res['cols'], 100);
    expect(res['rows'], 30);
    expect(res['seq'], 3);

    final snap = PairingCodec.decode(sent[1]) as SnapshotFrame;
    expect(snap.sub, 1);
    expect(snap.seq, 3);
    expect(snap.bytes, Uint8List.fromList([1, 2, 3]));
  });

  test('live output after subscribe is batched into an output frame', () async {
    final buffer = RecentPtyBuffer();
    when(() => session.recentBuffer).thenReturn(buffer);
    handler.handle(
      PairingCodec.decode(_json({
        'id': 1,
        'method': 'terminal.subscribe',
        'params': {'catalogId': 'ws:p1'},
      })),
    );
    sent.clear();

    buffer.append(Uint8List.fromList([9, 9]));
    mirror.add(Uint8List.fromList([9, 9]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final out = decodeLast() as OutputFrame;
    expect(out.sub, 1);
    expect(out.bytes, Uint8List.fromList([9, 9]));
    expect(out.seq, 2);
  });

  test('subscribe to an unknown catalogId replies error', () {
    handler.handle(
      PairingCodec.decode(_json({
        'id': 3,
        'method': 'terminal.subscribe',
        'params': {'catalogId': 'nope'},
      })),
    );
    final frame = decodeLast() as JsonFrame;
    expect(frame.data['error'], contains('no such session'));
  });

  test('input frame forwards raw bytes to the session', () {
    // Subscribe first so the sub exists.
    when(() => session.recentBuffer).thenReturn(RecentPtyBuffer());
    handler.handle(
      PairingCodec.decode(_json({
        'id': 1,
        'method': 'terminal.subscribe',
        'params': {'catalogId': 'ws:p1'},
      })),
    );
    handler.handle(
      PairingCodec.decode(PairingCodec.encodeInput(1, Uint8List.fromList([65, 66]))),
    );
    final captured = verify(() => session.writeRemoteInput(captureAny()))
        .captured
        .single as Uint8List;
    expect(captured, Uint8List.fromList([65, 66]));
  });

  test('resize forwards cols/rows to the session', () {
    when(() => session.recentBuffer).thenReturn(RecentPtyBuffer());
    handler.handle(
      PairingCodec.decode(_json({
        'id': 1,
        'method': 'terminal.subscribe',
        'params': {'catalogId': 'ws:p1'},
      })),
    );
    handler.handle(
      PairingCodec.decode(_json({
        'method': 'terminal.resize',
        'params': {'sub': 1, 'cols': 120, 'rows': 40},
      })),
    );
    verify(() => session.onTerminalPtyResize(120, 40)).called(1);
  });

  test('unsubscribe sends terminal.closed and cancels the listener', () {
    when(() => session.recentBuffer).thenReturn(RecentPtyBuffer());
    handler.handle(
      PairingCodec.decode(_json({
        'id': 1,
        'method': 'terminal.subscribe',
        'params': {'catalogId': 'ws:p1'},
      })),
    );
    sent.clear();
    handler.handle(
      PairingCodec.decode(_json({
        'method': 'terminal.unsubscribe',
        'params': {'sub': 1},
      })),
    );
    final closed = sent
        .map(PairingCodec.decode)
        .whereType<JsonFrame>()
        .firstWhere((f) => f.data['method'] == 'terminal.closed');
    expect((closed.data['params'] as Map)['sub'], 1);
  });

  test('subscribe attaches the desktop mirror takeover once', () {
    when(() => session.recentBuffer).thenReturn(RecentPtyBuffer());
    handler.handle(
      PairingCodec.decode(_json({
        'id': 1,
        'method': 'terminal.subscribe',
        'params': {'catalogId': 'ws:p1'},
      })),
    );
    verify(() => session.attachMirror()).called(1);
    verifyNever(() => session.detachMirror());
  });

  test('unsubscribe detaches the mirror takeover', () {
    when(() => session.recentBuffer).thenReturn(RecentPtyBuffer());
    handler.handle(
      PairingCodec.decode(_json({
        'id': 1,
        'method': 'terminal.subscribe',
        'params': {'catalogId': 'ws:p1'},
      })),
    );
    handler.handle(
      PairingCodec.decode(_json({
        'method': 'terminal.unsubscribe',
        'params': {'sub': 1},
      })),
    );
    verify(() => session.detachMirror()).called(1);
  });

  test('dispose detaches every live mirror (dropped-link path)', () {
    when(() => session.recentBuffer).thenReturn(RecentPtyBuffer());
    handler.handle(
      PairingCodec.decode(_json({
        'id': 1,
        'method': 'terminal.subscribe',
        'params': {'catalogId': 'ws:p1'},
      })),
    );
    handler.dispose();
    // Never got an unsubscribe — the desktop still has to be released.
    verify(() => session.detachMirror()).called(1);
  });

  test('unknown method replies with an error', () {
    handler.handle(
      PairingCodec.decode(_json({'id': 5, 'method': 'bogus.method'})),
    );
    final frame = decodeLast() as JsonFrame;
    expect(frame.data['error'], contains('unknown method'));
  });

  test('after dispose no frames are produced', () {
    handler.dispose();
    handler.handle(
      PairingCodec.decode(_json({'id': 1, 'method': 'session.list'})),
    );
    expect(sent, isEmpty);
  });

  group('workspace.list', () {
    test('unsupported when no index provider is injected', () async {
      handler.handle(
        PairingCodec.decode(_json({'id': 1, 'method': 'workspace.list'})),
      );
      await Future<void>.delayed(Duration.zero);
      final frame = decodeLast() as JsonFrame;
      expect(frame.data['error'], contains('unsupported'));
    });

    test('groups live panes under their owning workspace', () async {
      final otherPane = SessionCatalogEntry(
        const PairedSessionRef(
          catalogId: 'ws:p2',
          title: 'other term',
          subtitle: '/tmp',
          workspaceId: 'wsB',
          paneId: 'p2',
        ),
        session,
      );
      catalog = SessionCatalog()..addSource(() => [makeEntry(), otherPane]);
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadSink: _noopSink,
        workspaceIndex: () async => const [
          PairingWorkspaceInfo(workspaceId: 'wsA', title: 'Workspace A'),
          PairingWorkspaceInfo(workspaceId: 'wsC', title: 'Dormant'),
        ],
      );

      handler.handle(
        PairingCodec.decode(_json({'id': 9, 'method': 'workspace.list'})),
      );
      await Future<void>.delayed(Duration.zero);

      final frame = decodeLast() as JsonFrame;
      final workspaces = (frame.data['result'] as Map)['workspaces'] as List;
      expect(workspaces, hasLength(2));

      final wsA = workspaces[0] as Map;
      expect(wsA['workspaceId'], 'wsA');
      // Only wsA's own pane — wsB's pane belongs to a workspace not listed.
      final panes = wsA['panes'] as List;
      expect(panes, hasLength(1));
      final pane = panes.single as Map;
      expect(pane['catalogId'], 'ws:p1');
      expect(pane['paneId'], 'p1');
      expect(pane['live'], true);
      expect(pane['cols'], 100);
      expect(pane['rows'], 30);

      // A workspace with nothing running still lists, so the phone can start one.
      final wsC = workspaces[1] as Map;
      expect(wsC['workspaceId'], 'wsC');
      expect(wsC['panes'], isEmpty);
      expect(wsC.containsKey('sessions'), false);
    });
  });

  group('session.activate', () {
    test('unsupported when no activator is injected', () async {
      handler.handle(
        PairingCodec.decode(_json({
          'id': 1,
          'method': 'session.activate',
          'params': {'workspaceId': 'wsA', 'paneId': 'p1'},
        })),
      );
      await Future<void>.delayed(Duration.zero);
      final frame = decodeLast() as JsonFrame;
      expect(frame.data['error'], contains('unsupported'));
    });

    test('returns catalogId once the activator makes it live', () async {
      // Start with an empty catalog; the activator flips a live session in.
      var isLive = false;
      catalog = SessionCatalog()
        ..addSource(() => isLive ? [makeEntry()] : const []);
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadSink: _noopSink,
        activatePollInterval: const Duration(milliseconds: 5),
        activator: (req) async {
          isLive = true;
          return const PairingActivationResult(catalogId: 'ws:p1');
        },
      );

      handler.handle(
        PairingCodec.decode(_json({
          'id': 4,
          'method': 'session.activate',
          'params': {'workspaceId': 'wsA', 'paneId': 'p1'},
        })),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final frame = decodeLast() as JsonFrame;
      final res = frame.data['result'] as Map;
      expect(res['catalogId'], 'ws:p1');
      expect(res['cols'], 100);
      expect(res['fallback'], false);
    });

    test('errors when the session never becomes live', () async {
      catalog = SessionCatalog()..addSource(() => const []);
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadSink: _noopSink,
        activateTimeout: const Duration(milliseconds: 20),
        activatePollInterval: const Duration(milliseconds: 5),
        activator: (req) async =>
            const PairingActivationResult(catalogId: 'ws:p1'),
      );

      handler.handle(
        PairingCodec.decode(_json({
          'id': 5,
          'method': 'session.activate',
          'params': {'workspaceId': 'wsA', 'paneId': 'p1'},
        })),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final frame = decodeLast() as JsonFrame;
      expect(frame.data['error'], contains('did not become live'));
    });
  });
}
