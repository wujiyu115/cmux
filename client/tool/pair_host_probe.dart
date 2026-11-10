// Developer harness: runs a *pairing host* with scripted terminals so a phone or
// tablet client can be exercised without a second machine, without touching the
// real app data, and without clicking anything.
//
//   flutter run -d windows -t tool/pair_host_probe.dart
//
// It prints (and writes to `<system temp>/tp_probe_offer.txt`) a pairing deep
// link to paste into the client's "enter pairing code" sheet. Set
// `TP_PROBE_ADDR=<ipv4>` to pin the advertised address; otherwise every local
// IPv4 is advertised, which is right for a real LAN but wasteful on a machine
// with VPN / WSL adapters.
//
// Mirrored "terminals" are scripted: a banner, a tick every two seconds, and
// keystroke echo. Nothing here is part of the shipped app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/repositories/pairing_key_store.dart';
import 'package:teampilot/models/pane_mode.dart';
import 'package:teampilot/services/chat/chat_transcript_registry.dart';
import 'package:teampilot/services/chat/chat_transcript_session.dart';
import 'package:teampilot/services/cli/sessions/agent_cli_sessions.dart';
import 'package:teampilot/services/pairing/device_registry.dart';
import 'package:teampilot/services/pairing/lan_pairing_server.dart';
import 'package:teampilot/services/pairing/pairing_crypto.dart';
import 'package:teampilot/services/pairing/pairing_upload_target.dart';
import 'package:teampilot/services/pairing/pairing_workspace_index.dart';
import 'package:teampilot/services/pairing/session_catalog.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';

const _probeNames = ['alpha', 'beta'];
const _chatPaneId = 'probe-pane-chat';
const _chatCwd = r'D:\git\teampilot-probe';
const _probeWorkspaceId = 'probe-workspace';
const _probeCwd = r'D:\';
final _probeHome =
    '${Directory.systemTemp.path}${Platform.pathSeparator}tp_probe_home';
const _banner =
    '\x1b[1;36mTeamPilot probe host\x1b[0m\r\n'
    'mirror target: scripted shell\r\n'
    '─────────────────────────────\r\n';

class _ScriptedTransport implements TerminalTransport {
  _ScriptedTransport(this.name, {this.onLine});

  final String name;

  /// Called with each submitted line, so the chat pane's scripted CLI can write
  /// a matching turn into the session store the transcript reader polls.
  final void Function(String line)? onLine;
  final _typed = StringBuffer();
  final _out = StreamController<Uint8List>.broadcast();
  final _done = Completer<int>();
  Timer? _ticker;
  int _tick = 0;

  void start() {
    _emit(_banner);
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      _tick++;
      final stamp = DateTime.now().toIso8601String();
      _emit('\x1b[32m$name\x1b[0m tick $_tick  $stamp\r\n');
    });
  }

  void _emit(String text) {
    if (!_out.isClosed) _out.add(Uint8List.fromList(utf8.encode(text)));
  }

  @override
  Stream<Uint8List> get output => _out.stream;

  @override
  Future<int> get done => _done.future;

  @override
  int? get pid => null;

  @override
  void write(Uint8List data) {
    // Echo keystrokes so mirror input looks alive.
    _emit(utf8.decode(data, allowMalformed: true).replaceAll('\r', '\r\n'));
    for (final unit in data) {
      if (unit == 0x0d || unit == 0x0a) {
        final line = _typed.toString().trim();
        _typed.clear();
        if (line.isNotEmpty) onLine?.call(line);
      } else if (unit >= 0x20) {
        _typed.writeCharCode(unit);
      }
    }
  }

  @override
  void resize(int rows, int columns) {}

  @override
  void close() {
    _ticker?.cancel();
    if (!_done.isCompleted) _done.complete(0);
    unawaited(_out.close());
  }
}

/// A scripted stand-in for an agent CLI, written in the shape the shipped
/// reader parses.
///
/// It writes a real Claude session file (`<home>/.claude/projects/<munged>/<id>.jsonl`)
/// and answers each submitted line in it, so the probe exercises the whole path
/// the app uses — store adapter, parser, poll, registry, RPC — instead of
/// handing the phone a stubbed snapshot. The pane's "terminal" is inert: the
/// writer below is the CLI.
class _FakeAgentStore {
  _FakeAgentStore({required this.home, required this.cwd});

  final String home;
  final String cwd;
  var _turn = 0;

  String get _path => p.join(
    home,
    '.claude',
    'projects',
    mungeDirectory(cwd),
    '00000000-0000-4000-8000-000000000001.jsonl',
  );

  Future<void> seed() async {
    await File(_path).parent.create(recursive: true);
    // Truncate: a restarted host must not pile a second copy of the seed on the
    // first, which reads as the same prompt answered twice.
    await File(_path).writeAsString('');
    await _append([
      _record('user', {
        'message': {'role': 'user', 'content': 'Why is this pane a chat?'},
      }),
      _record('assistant', {
        'message': {
          'id': 'msg_seed',
          'content': [
            {
              'type': 'thinking',
              'thinking':
                  'Seeding one row of each kind makes every branch of the '
                  'renderer show up on the first paint.',
            },
            {
              'type': 'text',
              'text':
                  'Because this pane is registered in chat mode on the host. '
                  'The rows come from a Claude-shaped session file — the same '
                  'one the real app reads — so no agent protocol is involved.',
            },
            {
              'type': 'tool_use',
              'id': 'tool_1',
              'name': 'Read',
              'input': {'file_path': 'tool/pair_host_probe.dart'},
            },
          ],
        },
      }),
      _record('user', {
        'message': {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'tool_1',
              'content': 'void main() { }',
            },
          ],
        },
      }),
    ]);
  }

  /// Writes the turn a real CLI would have written for [line].
  Future<void> answer(String line) async {
    _turn++;
    await _append([
      _record('user', {
        'message': {'role': 'user', 'content': line},
      }),
      _record('assistant', {
        'message': {
          'id': 'msg_$_turn',
          'content': [
            {
              'type': 'text',
              'text':
                  'Turn $_turn: your line reached the host and was appended to '
                  'the session file. This bubble came back through the poll.',
            },
          ],
        },
      }),
    ]);
  }

  Future<void> _append(List<Map<String, Object?>> records) =>
      File(_path).writeAsString(
        '${records.map(jsonEncode).join('\n')}\n',
        mode: FileMode.append,
        flush: true,
      );

  Map<String, Object?> _record(String type, Map<String, Object?> fields) => {
    'type': type,
    'uuid': '$type-${DateTime.now().microsecondsSinceEpoch}',
    'sessionId': '00000000-0000-4000-8000-000000000001',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    ...fields,
  };
}

Future<PairingUploadTarget> _noUpload({
  required String workspaceId,
  required String cwd,
  required String filename,
}) => throw UnsupportedError('probe host: upload unsupported');

/// Persists the host static key and the paired-device registry beside the offer
/// file, so a restarted probe keeps a client registered instead of forcing a new
/// pairing for every run (the client pins the host key from its offer).
class _FilePairingKeyStore implements PairingKeyStore {
  _FilePairingKeyStore(this.file);

  final File file;
  Map<String, Object?>? _cache;

  Future<Map<String, Object?>> _read() async {
    final cached = _cache;
    if (cached != null) return cached;
    var data = <String, Object?>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) data = decoded.cast<String, Object?>();
      } on FormatException {
        // Corrupt probe state — start clean rather than crash the harness.
      }
    }
    return _cache = data;
  }

  Future<void> _write(String key, String value) async {
    final data = await _read();
    data[key] = value;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data));
  }

  @override
  Future<String?> loadStaticPrivateKey() async =>
      (await _read())['privateKey'] as String?;

  @override
  Future<void> saveStaticPrivateKey(String privateKeyB64) =>
      _write('privateKey', privateKeyB64);

  @override
  Future<String?> loadDevicesJson() async =>
      (await _read())['devices'] as String?;

  @override
  Future<void> saveDevicesJson(String json) => _write('devices', json);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // TerminalSession binds a flutter_alacritty engine; without this every
  // "terminal" fails to launch and the mirror stays blank.
  await RustLib.init();

  // Fixed at boot: the chat pane's "which session file is mine" window anchors
  // to when the pane started, so toggling chat off and on again finds the same
  // transcript instead of an empty one.
  final probeStartedAt = DateTime.now();
  final catalog = SessionCatalog();
  final entries = <SessionCatalogEntry>[];

  for (var i = 0; i < _probeNames.length; i++) {
    final name = _probeNames[i];
    final transport = _ScriptedTransport(name);
    final session = TerminalSession(
      executable: 'probe-shell',
      validateLaunch: false,
      parseExecutable: false,
      transportStarter:
          (
            executable, {
            required List<String> arguments,
            required String workingDirectory,
            required int columns,
            required int rows,
            Map<String, String>? environment,
          }) async {
            // The host subscribes right after this returns; a broadcast stream
            // drops anything emitted before that.
            Future<void>.delayed(
              const Duration(milliseconds: 400),
              transport.start,
            );
            return transport;
          },
    );
    session.connect(workingDirectory: _probeCwd);
    entries.add(
      SessionCatalogEntry(
        PairedSessionRef(
          catalogId: PairedSessionRef.paneCatalogId('probe-pane-$i'),
          title: 'probe-$name',
          subtitle: _probeCwd,
          workspaceId: _probeWorkspaceId,
          paneId: 'probe-pane-$i',
        ),
        session,
      ),
    );
  }

  catalog.addSource(() => entries);

  // The chat pane: a real transcript file, read by the real reader. Nothing here
  // knows how the phone draws it — the host only answers "this pane is chat".
  final agentStore = _FakeAgentStore(home: _probeHome, cwd: _chatCwd);
  await agentStore.seed();
  final chatTransport = _ScriptedTransport(
    'chat',
    onLine: (line) => unawaited(agentStore.answer(line)),
  );
  final chatSession = TerminalSession(
    executable: 'probe-agent',
    validateLaunch: false,
    parseExecutable: false,
    transportStarter:
        (
          executable, {
          required List<String> arguments,
          required String workingDirectory,
          required int columns,
          required int rows,
          Map<String, String>? environment,
        }) async {
          Future<void>.delayed(
            const Duration(milliseconds: 400),
            chatTransport.start,
          );
          return chatTransport;
        },
  );
  chatSession.connect(workingDirectory: _chatCwd);
  entries.add(
    SessionCatalogEntry(
      PairedSessionRef(
        catalogId: PairedSessionRef.paneCatalogId(_chatPaneId),
        title: 'probe-chat',
        subtitle: _chatCwd,
        workspaceId: _probeWorkspaceId,
        paneId: _chatPaneId,
      ),
      chatSession,
    ),
  );

  final chatTranscripts = ChatTranscriptRegistry();
  // Registered once, like a real chat pane's reader: `paneMode` above is what
  // tells the phone this pane is a conversation, and it never changes.
  chatTranscripts.register(
    _chatPaneId,
    ChatTranscriptSession(
      paneId: _chatPaneId,
      resolveContext: (_) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: LocalFilesystem(),
        home: _probeHome,
        cwd: _chatCwd,
        appDataRoot: p.join(_probeHome, 'appdata'),
        paths: AppPaths(p.join(_probeHome, 'appdata')),
      ),
      target: RuntimeTarget.local,
      directory: () => _chatCwd,
      // Seeded just now, so the "written since the pane opened" window is met.
      startedAt: probeStartedAt,
    )..start(),
  );

  final store = _FilePairingKeyStore(
    File('${Directory.systemTemp.path}/tp_probe_identity.json'),
  );
  final storedKey = await store.loadStaticPrivateKey();
  final hostKey = storedKey == null
      ? PairingKeyPair.generate()
      : PairingKeyPair.fromPrivateBytes(PairingCrypto.unb64u(storedKey));
  if (storedKey == null) {
    await store.saveStaticPrivateKey(hostKey.privateKeyB64);
  }
  final registry = DeviceRegistry(store);
  await registry.load();

  final server = LanPairingServer(
    hostStaticKey: hostKey,
    registry: registry,
    catalog: catalog,
    hostName: 'Probe Desktop',
    uploadOpener: _noUpload,
    workspaceIndex: () async => const [
      PairingWorkspaceInfo(
        workspaceId: _probeWorkspaceId,
        title: _probeWorkspaceId,
      ),
    ],
    groupIndex: () async => const [],
    targetIndex: () async => const [
      PairingTargetInfo(id: 'local', label: 'Local', kind: 'local'),
    ],
    advertisedAddress: Platform.environment['TP_PROBE_ADDR']?.trim(),
    chatTranscript: (paneId) => chatTranscripts[paneId]?.transcript.value,
    // The probe's chat pane was created as a chat pane, like a real one now is:
    // the mode is a property of the pane, not something the host flips at will.
    paneMode: (paneId) =>
        paneId == _chatPaneId ? PaneMode.chat : PaneMode.terminal,
  );

  await server.ensureStarted();
  final link = (await server.createOffer()).toDeepLink();
  final offerFile = File('${Directory.systemTemp.path}/tp_probe_offer.txt');
  await offerFile.writeAsString('$link\n');
  // ignore: avoid_print
  print('OFFER_FILE=${offerFile.path}');
  // ignore: avoid_print
  print('OFFER=$link');
  catalog.notifyChanged();

  runApp(_ProbeApp(link: link, port: server.port));
}

class _ProbeApp extends StatelessWidget {
  const _ProbeApp({required this.link, required this.port});

  final String link;
  final int port;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'probe pairing host on :$port',
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 12),
            SelectableText(
              link,
              style: const TextStyle(
                color: Color(0xFFFFC98A),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
