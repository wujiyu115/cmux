import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/services/pairing/pairing_frames.dart';
import 'package:teampilot/services/pairing/pairing_rpc_handler.dart';
import 'package:teampilot/services/pairing/pairing_workspace_index.dart';
import 'package:teampilot/services/pairing/recent_pty_buffer.dart';
import 'package:teampilot/services/pairing/session_catalog.dart';
import 'package:teampilot/services/pairing/terminal_mode_resync.dart';
import '../../support/pairing_upload_doubles.dart';
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
    // The subscribe path reads it to build the mirror's mode resync.
    when(() => session.cursorVisible).thenReturn(true);

    catalog = SessionCatalog()..addSource(() => [makeEntry()]);
    sent = [];
    handler = PairingRpcHandler(
      catalog: catalog,
      send: sent.add,
      uploadOpener: noopUploadOpener,
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
    // The mode resync leads, then the retained bytes. The ring holds no terminal
    // state, so without the preamble a fresh mirror engine keeps whatever modes
    // it booted with — see [terminalModeResync].
    expect(
      snap.bytes,
      Uint8List.fromList([
        ...terminalModeResync(cursorVisible: true),
        1,
        2,
        3,
      ]),
    );
  });

  test('subscribe hides the mirror cursor when the pane has it hidden', () {
    // The symptom this fixes: a full-screen program sends `CSI ?25l` once at
    // startup and draws its own caret, so a mirror that never hears the hide
    // paints a second, blinking cursor on top of the drawn one.
    when(() => session.cursorVisible).thenReturn(false);
    final buffer = RecentPtyBuffer()..append(Uint8List.fromList([1]));
    when(() => session.recentBuffer).thenReturn(buffer);
    handler.handle(
      PairingCodec.decode(_json({
        'id': 1,
        'method': 'terminal.subscribe',
        'params': {'catalogId': 'ws:p1'},
      })),
    );

    final snap = PairingCodec.decode(sent[1]) as SnapshotFrame;
    expect(
      snap.bytes,
      Uint8List.fromList([...terminalModeResync(cursorVisible: false), 1]),
    );
  });

  test('subscribe still sends the resync when the ring is empty', () {
    // A pane that has produced nothing yet still has modes worth carrying over,
    // so the snapshot frame must not be skipped just because there are no bytes.
    when(() => session.cursorVisible).thenReturn(false);
    when(() => session.recentBuffer).thenReturn(RecentPtyBuffer());
    handler.handle(
      PairingCodec.decode(_json({
        'id': 1,
        'method': 'terminal.subscribe',
        'params': {'catalogId': 'ws:p1'},
      })),
    );

    final snap = PairingCodec.decode(sent[1]) as SnapshotFrame;
    expect(snap.seq, 0);
    expect(snap.bytes, terminalModeResync(cursorVisible: false));
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
        uploadOpener: noopUploadOpener,
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
        uploadOpener: noopUploadOpener,
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
        uploadOpener: noopUploadOpener,
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

  group('workspace.list groups', () {
    test('emits groups and each workspace groupId', () async {
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        workspaceIndex: () async => const [
          PairingWorkspaceInfo(
            workspaceId: 'wsA',
            title: 'A',
            groupId: 'g1',
          ),
        ],
        groupIndex: () async => const [
          PairingGroupInfo(id: 'g1', name: 'Group One', order: 0),
        ],
      );

      handler.handle(
        PairingCodec.decode(_json({'id': 1, 'method': 'workspace.list'})),
      );
      await Future<void>.delayed(Duration.zero);

      final result = (decodeLast() as JsonFrame).data['result'] as Map;
      final wsA = (result['workspaces'] as List).single as Map;
      expect(wsA['groupId'], 'g1');
      final groups = result['groups'] as List;
      expect(groups, hasLength(1));
      final g = groups.single as Map;
      expect(g['id'], 'g1');
      expect(g['name'], 'Group One');
      expect(g['order'], 0);
    });

    test('groups is empty when no group index is injected', () async {
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        workspaceIndex: () async => const [
          PairingWorkspaceInfo(workspaceId: 'wsA', title: 'A'),
        ],
      );
      handler.handle(
        PairingCodec.decode(_json({'id': 1, 'method': 'workspace.list'})),
      );
      await Future<void>.delayed(Duration.zero);

      final result = (decodeLast() as JsonFrame).data['result'] as Map;
      expect(result['groups'], isEmpty);
      // Default groupId is the empty string, not null.
      expect(((result['workspaces'] as List).single as Map)['groupId'], '');
    });

    test('advertises the machines from the target index', () async {
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        workspaceIndex: () async => const [
          PairingWorkspaceInfo(workspaceId: 'wsA', title: 'A'),
        ],
        targetIndex: () async => const [
          PairingTargetInfo(id: 'local', label: 'This device', kind: 'local'),
          PairingTargetInfo(
            id: 'wsl:Ubuntu',
            label: 'WSL · Ubuntu',
            kind: 'wsl',
          ),
        ],
      );
      handler.handle(
        PairingCodec.decode(_json({'id': 1, 'method': 'workspace.list'})),
      );
      await Future<void>.delayed(Duration.zero);

      final result = (decodeLast() as JsonFrame).data['result'] as Map;
      final targets = result['targets'] as List;
      expect(targets, hasLength(2));
      expect((targets.last as Map)['id'], 'wsl:Ubuntu');
      expect((targets.last as Map)['label'], 'WSL · Ubuntu');
      expect((targets.last as Map)['kind'], 'wsl');
    });

    test('targets is empty when no target index is injected', () async {
      // This is the compatibility contract in one assertion: a host without
      // machine selection advertises none, which is exactly how the phone knows
      // to hide its picker and send no targetId.
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        workspaceIndex: () async => const [
          PairingWorkspaceInfo(workspaceId: 'wsA', title: 'A'),
        ],
      );
      handler.handle(
        PairingCodec.decode(_json({'id': 1, 'method': 'workspace.list'})),
      );
      await Future<void>.delayed(Duration.zero);

      expect((decodeLast() as JsonFrame).data['result'], isA<Map>());
      final result = (decodeLast() as JsonFrame).data['result'] as Map;
      expect(result['targets'], isEmpty);
    });

    test('a failing target index fails the call once, cleanly', () async {
      // Enumerating machines shells out to the host, so it can fail. The await
      // must sit inside the existing try or this surfaces as an unhandled async
      // error instead of an error frame.
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        workspaceIndex: () async => const [
          PairingWorkspaceInfo(workspaceId: 'wsA', title: 'A'),
        ],
        targetIndex: () async => throw StateError('wsl.exe went missing'),
      );
      handler.handle(
        PairingCodec.decode(_json({'id': 1, 'method': 'workspace.list'})),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        (decodeLast() as JsonFrame).data['error'],
        contains('workspace.list failed'),
      );
      expect(sent, hasLength(1));
    });
  });

  group('fs.browse', () {
    test('unsupported when no browser is injected', () async {
      handler.handle(
        PairingCodec.decode(_json({'id': 1, 'method': 'fs.browse'})),
      );
      await Future<void>.delayed(Duration.zero);
      expect((decodeLast() as JsonFrame).data['error'], contains('unsupported'));
    });

    test('passes the path through and returns the listing', () async {
      String? seen = 'unset';
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        dirBrowser: (path, {targetId}) async {
          seen = path;
          return const PairingDirListing(
            path: '/home/me',
            parent: '/home',
            dirs: ['a', 'b'],
          );
        },
      );
      handler.handle(
        PairingCodec.decode(_json({
          'id': 2,
          'method': 'fs.browse',
          'params': {'path': '/home/me'},
        })),
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen, '/home/me');
      final result = (decodeLast() as JsonFrame).data['result'] as Map;
      expect(result['path'], '/home/me');
      expect(result['parent'], '/home');
      expect(result['dirs'], ['a', 'b']);
    });

    test('null path reaches the browser (default root)', () async {
      Object? seen = 'unset';
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        dirBrowser: (path, {targetId}) async {
          seen = path;
          return const PairingDirListing(
            path: '/root',
            parent: null,
            dirs: [],
          );
        },
      );
      handler.handle(
        PairingCodec.decode(_json({'id': 3, 'method': 'fs.browse'})),
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen, isNull);
      final result = (decodeLast() as JsonFrame).data['result'] as Map;
      expect(result['parent'], isNull);
    });

    test('forwards the requested machine', () async {
      Object? seenTarget = 'unset';
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        dirBrowser: (path, {targetId}) async {
          seenTarget = targetId;
          return const PairingDirListing(
            path: '/home/me',
            parent: '/home',
            dirs: [],
          );
        },
      );
      handler.handle(
        PairingCodec.decode(_json({
          'id': 4,
          'method': 'fs.browse',
          'params': {'path': '/home/me', 'targetId': 'wsl:Ubuntu'},
        })),
      );
      await Future<void>.delayed(Duration.zero);
      expect(seenTarget, 'wsl:Ubuntu');
    });

    test('an absent machine is null, not empty', () async {
      // The compatibility contract: a phone that predates machine selection
      // sends no targetId, and the host must read that as "default plane".
      Object? seenTarget = 'unset';
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        dirBrowser: (path, {targetId}) async {
          seenTarget = targetId;
          return const PairingDirListing(path: '/x', parent: null, dirs: []);
        },
      );
      handler.handle(
        PairingCodec.decode(_json({
          'id': 5,
          'method': 'fs.browse',
          'params': {'path': '/x'},
        })),
      );
      await Future<void>.delayed(Duration.zero);
      expect(seenTarget, isNull);
    });

    test('a non-string machine is treated as absent', () async {
      Object? seenTarget = 'unset';
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        dirBrowser: (path, {targetId}) async {
          seenTarget = targetId;
          return const PairingDirListing(path: '/x', parent: null, dirs: []);
        },
      );
      handler.handle(
        PairingCodec.decode(_json({
          'id': 6,
          'method': 'fs.browse',
          'params': {'targetId': 42},
        })),
      );
      await Future<void>.delayed(Duration.zero);
      expect(seenTarget, isNull);
    });
  });

  group('workspace.create', () {
    test('unsupported when no creator is injected', () async {
      handler.handle(
        PairingCodec.decode(_json({
          'id': 1,
          'method': 'workspace.create',
          'params': {'folderPath': '/x'},
        })),
      );
      await Future<void>.delayed(Duration.zero);
      expect((decodeLast() as JsonFrame).data['error'], contains('unsupported'));
    });

    test('requires a non-empty folderPath', () async {
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        workspaceCreator:
            ({required folderPath, title, groupId, targetId}) async => 'w',
      );
      handler.handle(
        PairingCodec.decode(_json({
          'id': 1,
          'method': 'workspace.create',
          'params': {'folderPath': ''},
        })),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        (decodeLast() as JsonFrame).data['error'],
        contains('requires folderPath'),
      );
    });

    test('forwards folderPath/title/groupId/targetId and returns the id', () async {
      String? gotFolder, gotTitle, gotGroup;
      Object? gotTarget = 'unset';
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        workspaceCreator: ({required folderPath, title, groupId, targetId}) async {
          gotFolder = folderPath;
          gotTitle = title;
          gotGroup = groupId;
          gotTarget = targetId;
          return 'ws-new';
        },
      );
      handler.handle(
        PairingCodec.decode(_json({
          'id': 2,
          'method': 'workspace.create',
          'params': {
            'folderPath': '/repo/app',
            'title': 'App',
            'groupId': 'g1',
            'targetId': 'wsl:Ubuntu',
          },
        })),
      );
      await Future<void>.delayed(Duration.zero);

      expect(gotFolder, '/repo/app');
      expect(gotTitle, 'App');
      expect(gotGroup, 'g1');
      expect(gotTarget, 'wsl:Ubuntu');
      final result = (decodeLast() as JsonFrame).data['result'] as Map;
      expect(result['workspaceId'], 'ws-new');
    });

    test('an absent machine reaches the creator as null', () async {
      Object? gotTarget = 'unset';
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        workspaceCreator: ({required folderPath, title, groupId, targetId}) async {
          gotTarget = targetId;
          return 'ws-new';
        },
      );
      handler.handle(
        PairingCodec.decode(_json({
          'id': 3,
          'method': 'workspace.create',
          'params': {'folderPath': '/repo/app'},
        })),
      );
      await Future<void>.delayed(Duration.zero);
      expect(gotTarget, isNull);
    });
  });

  group('group.create', () {
    test('unsupported when no creator is injected', () async {
      handler.handle(
        PairingCodec.decode(_json({
          'id': 1,
          'method': 'group.create',
          'params': {'name': 'X'},
        })),
      );
      await Future<void>.delayed(Duration.zero);
      expect((decodeLast() as JsonFrame).data['error'], contains('unsupported'));
    });

    test('requires a non-blank name', () async {
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        groupCreator: (name) async => 'g',
      );
      handler.handle(
        PairingCodec.decode(_json({
          'id': 1,
          'method': 'group.create',
          'params': {'name': '   '},
        })),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        (decodeLast() as JsonFrame).data['error'],
        contains('requires name'),
      );
    });

    test('trims the name, forwards it, and returns the id', () async {
      String? got;
      handler = PairingRpcHandler(
        catalog: catalog,
        send: sent.add,
        uploadOpener: noopUploadOpener,
        groupCreator: (name) async {
          got = name;
          return 'g-new';
        },
      );
      handler.handle(
        PairingCodec.decode(_json({
          'id': 2,
          'method': 'group.create',
          'params': {'name': '  Frontend  '},
        })),
      );
      await Future<void>.delayed(Duration.zero);

      expect(got, 'Frontend');
      final result = (decodeLast() as JsonFrame).data['result'] as Map;
      expect(result['groupId'], 'g-new');
    });
  });
}
