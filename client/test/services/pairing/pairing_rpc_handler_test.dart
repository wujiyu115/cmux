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

void main() {
  setUpAll(() => registerFallbackValue(Uint8List(0)));

  late _MockSession session;
  late StreamController<Uint8List> mirror;
  late SessionCatalog catalog;
  late List<Uint8List> sent;
  late PairingRpcHandler handler;

  SessionCatalogEntry makeEntry() => SessionCatalogEntry(
    const PairedSessionRef(
      catalogId: 'chat:s1:main',
      kind: PairedSessionKind.chat,
      title: 'shell',
      subtitle: 'zsh',
      sessionId: 's1',
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

    catalog = SessionCatalog()..addSource(() => [makeEntry()]);
    sent = [];
    handler = PairingRpcHandler(
      catalog: catalog,
      send: sent.add,
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
    expect(s['catalogId'], 'chat:s1:main');
    expect(s['kind'], 'chat');
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
        'params': {'catalogId': 'chat:s1:main'},
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
        'params': {'catalogId': 'chat:s1:main'},
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
        'params': {'catalogId': 'chat:s1:main'},
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
        'params': {'catalogId': 'chat:s1:main'},
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
        'params': {'catalogId': 'chat:s1:main'},
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

    test('merges liveness/catalogId/geometry onto persisted sessions', () async {
      // Live catalog: chat:s1:main (running) + a workspace pane in wsA.
      final paneEntry = SessionCatalogEntry(
        const PairedSessionRef(
          catalogId: 'ws:p1',
          kind: PairedSessionKind.workspace,
          title: 'term',
          subtitle: 'wsA',
          sessionId: 'wsA',
          paneId: 'p1',
        ),
        session,
      );
      catalog = SessionCatalog()..addSource(() => [makeEntry(), paneEntry]);
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        workspaceIndex: () async => const [
          PairingWorkspaceInfo(
            workspaceId: 'wsA',
            title: 'Workspace A',
            sessions: [
              PairingPersistedSession(
                sessionId: 's1',
                title: 'live one',
                subtitle: 'zsh',
              ),
              PairingPersistedSession(
                sessionId: 's2',
                title: 'dead one',
                subtitle: 'bash',
              ),
            ],
          ),
        ],
      );

      handler.handle(
        PairingCodec.decode(_json({'id': 9, 'method': 'workspace.list'})),
      );
      await Future<void>.delayed(Duration.zero);

      final frame = decodeLast() as JsonFrame;
      final workspaces = (frame.data['result'] as Map)['workspaces'] as List;
      expect(workspaces, hasLength(1));
      final ws = workspaces.single as Map;
      expect(ws['workspaceId'], 'wsA');

      final sessions = ws['sessions'] as List;
      final live = sessions[0] as Map;
      expect(live['sessionId'], 's1');
      expect(live['live'], true);
      expect(live['catalogId'], 'chat:s1:main');
      expect(live['cols'], 100);
      final dead = sessions[1] as Map;
      expect(dead['sessionId'], 's2');
      expect(dead['live'], false);
      expect(dead.containsKey('catalogId'), false);

      final panes = ws['panes'] as List;
      expect(panes, hasLength(1));
      expect((panes.single as Map)['catalogId'], 'ws:p1');
    });
  });

  group('session.activate', () {
    test('unsupported when no activator is injected', () async {
      handler.handle(
        PairingCodec.decode(_json({
          'id': 1,
          'method': 'session.activate',
          'params': {'workspaceId': 'wsA', 'kind': 'chat', 'sessionId': 's1'},
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
        activatePollInterval: const Duration(milliseconds: 5),
        activator: (req) async {
          isLive = true;
          return const PairingActivationResult(catalogId: 'chat:s1:main');
        },
      );

      handler.handle(
        PairingCodec.decode(_json({
          'id': 4,
          'method': 'session.activate',
          'params': {'workspaceId': 'wsA', 'kind': 'chat', 'sessionId': 's1'},
        })),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final frame = decodeLast() as JsonFrame;
      final res = frame.data['result'] as Map;
      expect(res['catalogId'], 'chat:s1:main');
      expect(res['cols'], 100);
      expect(res['fallback'], false);
    });

    test('errors when the session never becomes live', () async {
      catalog = SessionCatalog()..addSource(() => const []);
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        activateTimeout: const Duration(milliseconds: 20),
        activatePollInterval: const Duration(milliseconds: 5),
        activator: (req) async =>
            const PairingActivationResult(catalogId: 'chat:s1:main'),
      );

      handler.handle(
        PairingCodec.decode(_json({
          'id': 5,
          'method': 'session.activate',
          'params': {'workspaceId': 'wsA', 'kind': 'chat', 'sessionId': 's1'},
        })),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final frame = decodeLast() as JsonFrame;
      expect(frame.data['error'], contains('did not become live'));
    });
  });
}
