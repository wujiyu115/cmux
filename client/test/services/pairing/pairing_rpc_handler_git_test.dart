import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/services/pairing/pairing_frames.dart';
import 'package:teampilot/services/pairing/pairing_git_view.dart';
import 'package:teampilot/services/pairing/pairing_rpc_handler.dart';
import 'package:teampilot/services/pairing/recent_pty_buffer.dart';
import 'package:teampilot/services/pairing/session_catalog.dart';
import '../../support/pairing_upload_doubles.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/workspace_dnd/runtime_target.dart';

class _MockSession extends Mock implements TerminalSession {}

Uint8List _json(Map<String, Object?> data) => PairingCodec.encodeJson(data);

void main() {
  late _MockSession session;
  late StreamController<Uint8List> mirror;
  late SessionCatalog catalog;
  late List<Uint8List> sent;

  /// Calls recorded by the injected providers, so each test can assert the pane
  /// the handler resolved rather than trusting the reply alone.
  late List<Map<String, Object?>> changesCalls;
  late List<Map<String, Object?>> diffCalls;

  var changesResult = const PairingGitChanges(
    isRepository: true,
    branch: 'main',
    files: [
      PairingGitFile(path: 'lib/main.dart', badge: 'M'),
      PairingGitFile(path: 'lib/new.dart', badge: '?', untracked: true),
    ],
  );
  Object? changesError;

  Future<PairingGitChanges> changes({
    required String workspaceId,
    required String cwd,
  }) async {
    changesCalls.add({'workspaceId': workspaceId, 'cwd': cwd});
    if (changesError != null) throw changesError!;
    return changesResult;
  }

  Future<String> diff({
    required String workspaceId,
    required String cwd,
    required String path,
    required bool untracked,
  }) async {
    diffCalls.add({
      'workspaceId': workspaceId,
      'cwd': cwd,
      'path': path,
      'untracked': untracked,
    });
    return '@@ -1 +1 @@\n-old\n+new\n';
  }

  PairingRpcHandler build({bool wired = true}) => PairingRpcHandler(
    catalog: catalog,
    send: sent.add,
    uploadOpener: noopUploadOpener,
    gitChanges: wired ? changes : null,
    gitDiff: wired ? diff : null,
  );

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
      const RuntimeTarget.localPosix(workingDirectory: '/home/dev/app/sub'),
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
    changesCalls = [];
    diffCalls = [];
    changesError = null;
    changesResult = const PairingGitChanges(
      isRepository: true,
      branch: 'main',
      files: [
        PairingGitFile(path: 'lib/main.dart', badge: 'M'),
        PairingGitFile(path: 'lib/new.dart', badge: '?', untracked: true),
      ],
    );
  });

  tearDown(() => mirror.close());

  int subscribe(PairingRpcHandler handler) {
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

  JsonFrame lastJson() =>
      sent.map(PairingCodec.decode).whereType<JsonFrame>().last;

  Future<Map<String, Object?>> call(
    PairingRpcHandler handler,
    String method,
    Map<String, Object?> params,
  ) async {
    handler.handle(PairingCodec.decode(_json({
      'id': 9,
      'method': method,
      'params': params,
    })));
    // The handlers are async; one microtask drain is enough because the injected
    // providers complete synchronously.
    await Future<void>.delayed(Duration.zero);
    return lastJson().data;
  }

  test('git.changes resolves the pane and returns the host listing', () async {
    final handler = build();
    addTearDown(handler.dispose);
    final sub = subscribe(handler);

    final reply = await call(handler, 'git.changes', {'sub': sub});

    // The workspace comes from the catalog entry and the cwd from the pane, so
    // the phone never names either.
    expect(changesCalls.single['workspaceId'], 'ws-1');
    expect(changesCalls.single['cwd'], '/home/dev/app/sub');
    final result = reply['result'] as Map;
    expect(result['isRepository'], true);
    expect(result['branch'], 'main');
    final files = result['files'] as List;
    expect(files, hasLength(2));
    expect((files.first as Map)['path'], 'lib/main.dart');
    expect((files.last as Map)['untracked'], true);
  });

  test('git.diff forwards a path from the last git.changes, carrying its '
      'untracked flag', () async {
    final handler = build();
    addTearDown(handler.dispose);
    final sub = subscribe(handler);
    await call(handler, 'git.changes', {'sub': sub});

    final reply = await call(handler, 'git.diff', {
      'sub': sub,
      'path': 'lib/new.dart',
    });

    expect(diffCalls.single['path'], 'lib/new.dart');
    expect(diffCalls.single['untracked'], true);
    expect((reply['result'] as Map)['diff'], contains('+new'));
  });

  test('git.diff refuses a path the host never advertised', () async {
    final handler = build();
    addTearDown(handler.dispose);
    final sub = subscribe(handler);
    await call(handler, 'git.changes', {'sub': sub});

    final reply = await call(handler, 'git.diff', {
      'sub': sub,
      'path': '../../.ssh/id_rsa',
    });

    // The authorization clause: an unlisted path never reaches the provider, so
    // a paired phone cannot use git.diff as an arbitrary-file reader.
    expect(diffCalls, isEmpty);
    expect(reply['error'], contains('path not in changes'));
  });

  test('git.diff before any git.changes has nothing to authorize against',
      () async {
    final handler = build();
    addTearDown(handler.dispose);
    final sub = subscribe(handler);

    final reply = await call(handler, 'git.diff', {
      'sub': sub,
      'path': 'lib/main.dart',
    });

    expect(diffCalls, isEmpty);
    expect(reply['error'], contains('path not in changes'));
  });

  test('leaving the mirror drops the authorized paths with the subscription',
      () async {
    final handler = build();
    addTearDown(handler.dispose);
    final sub = subscribe(handler);
    await call(handler, 'git.changes', {'sub': sub});

    handler.handle(PairingCodec.decode(_json({
      'id': 5,
      'method': 'terminal.unsubscribe',
      'params': {'sub': sub},
    })));
    final reply = await call(handler, 'git.diff', {
      'sub': sub,
      'path': 'lib/main.dart',
    });

    expect(diffCalls, isEmpty);
    expect(reply['error'], contains('no such subscription'));
  });

  test('git.changes on an unknown sub fails without calling the provider',
      () async {
    final handler = build();
    addTearDown(handler.dispose);
    subscribe(handler);

    final reply = await call(handler, 'git.changes', {'sub': 999});

    expect(changesCalls, isEmpty);
    expect(reply['error'], contains('no such subscription'));
  });

  test('a provider throw becomes one named error frame', () async {
    changesError = StateError('git executable not found on PATH');
    final handler = build();
    addTearDown(handler.dispose);
    final sub = subscribe(handler);

    final reply = await call(handler, 'git.changes', {'sub': sub});

    expect(reply['error'], contains('git.changes failed'));
    expect(reply['error'], contains('not found on PATH'));
  });

  test('a host without the providers reports the method as unsupported',
      () async {
    final handler = build(wired: false);
    addTearDown(handler.dispose);
    final sub = subscribe(handler);

    final changesReply = await call(handler, 'git.changes', {'sub': sub});
    final diffReply = await call(handler, 'git.diff', {
      'sub': sub,
      'path': 'lib/main.dart',
    });

    expect(changesReply['error'], 'git.changes unsupported');
    expect(diffReply['error'], 'git.diff unsupported');
  });
}
