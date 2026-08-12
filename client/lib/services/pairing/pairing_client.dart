import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../utils/logging/logger.dart';
import 'agent_notice_message.dart';
import 'e2ee_channel.dart';
import 'pairing_crypto.dart';
import 'pairing_frames.dart';
import 'pairing_ports.dart';
import 'pairing_upload_sender.dart';
import 'ws_transport.dart';

/// The four observable phases of a pairing connect, in order. Emitted on
/// [PairingClient.stages] so the confirm screen can render real progress instead
/// of guessing from log text. [loadWorkspaces] is driven by the cubit — the
/// workspace fetch happens above this client.
enum PairingStage { connect, secureChannel, authenticate, loadWorkspaces }

/// Per-stage state for the confirm screen's step rail.
enum PairingStageStatus { idle, active, done, fail }

/// One transition of one [PairingStage].
class PairingStageEvent {
  const PairingStageEvent(this.stage, this.status);

  final PairingStage stage;
  final PairingStageStatus status;
}

/// Result of a successful auth: the host's identity plus (first pairing only) a
/// device token to persist for future reconnects.
class PairingAuthResult {
  const PairingAuthResult({
    required this.deviceId,
    required this.hostName,
    this.deviceToken,
  });

  final String deviceId;
  final String hostName;
  final String? deviceToken;
}

/// One mirrorable terminal as advertised by the host's `session.list`.
class PairingSessionSummary {
  const PairingSessionSummary({
    required this.catalogId,
    required this.title,
    required this.subtitle,
    required this.cols,
    required this.rows,
  });

  final String catalogId;
  final String title;
  final String subtitle;
  final int cols;
  final int rows;
}

/// One live terminal pane under a workspace in the `workspace.list` tree, keyed
/// by [paneId]. [catalogId] is what [subscribe] takes.
class PairingSessionNode {
  const PairingSessionNode({
    required this.workspaceId,
    required this.title,
    required this.subtitle,
    required this.live,
    this.paneId,
    this.catalogId,
    this.cols = 0,
    this.rows = 0,
  });

  final String workspaceId;
  final String title;
  final String subtitle;
  final bool live;
  final String? paneId;
  final String? catalogId;
  final int cols;
  final int rows;

  /// Stable per-row identity: live catalogId if any, else the pane id.
  String get nodeKey => catalogId ?? 'ws:${paneId ?? ''}';
}

/// One workspace and its live terminal panes, as advertised by `workspace.list`.
/// Workspaces with nothing running are still listed.
class PairingWorkspaceNode {
  const PairingWorkspaceNode({
    required this.workspaceId,
    required this.title,
    this.groupId = '',
    this.panes = const [],
  });

  final String workspaceId;
  final String title;

  /// Id of the group this workspace is filed under; empty = ungrouped.
  final String groupId;
  final List<PairingSessionNode> panes;
}

/// One workspace group advertised by `workspace.list`, so the phone can render
/// workspaces folded by group and offer them as create targets.
class PairingGroup {
  const PairingGroup({
    required this.id,
    required this.name,
    required this.order,
  });

  final String id;
  final String name;
  final int order;
}

/// One machine the desktop can bind a workspace folder to — itself, one of its
/// WSL distros, or an SSH profile.
///
/// [label] is rendered host-side (`WSL · Ubuntu`, the user's own SSH profile
/// name) and is displayed verbatim: it is not translatable. [kind] is the host's
/// `RuntimeKind` name, useful only for an icon; [id] stays authoritative.
class PairingTarget {
  const PairingTarget({
    required this.id,
    required this.label,
    required this.kind,
  });

  final String id;
  final String label;
  final String kind;

  bool get isLocal => id == 'local';
}

/// Result of [PairingClient.listWorkspaces]: the workspace tree, the host's group
/// index, and the machines it can create workspaces on.
class PairingWorkspaceListing {
  const PairingWorkspaceListing({
    required this.workspaces,
    required this.groups,
    this.targets = const [],
  });

  final List<PairingWorkspaceNode> workspaces;
  final List<PairingGroup> groups;

  /// Empty when the desktop predates machine selection — which is also the
  /// signal for the phone to hide its machine picker and send no `targetId`, so
  /// the whole flow degrades to what it did before. Defaulted rather than
  /// required so that reading an older host stays a one-line change.
  final List<PairingTarget> targets;
}

/// One remote directory listing for `fs.browse`.
class PairingDirListing {
  const PairingDirListing({
    required this.path,
    required this.parent,
    required this.dirs,
  });

  final String path;
  final String? parent;
  final List<String> dirs;
}

/// Outcome of [PairingClient.activateSession]: the catalogId to subscribe to,
/// its live geometry, and whether the requested pane was gone so the host opened
/// a fresh terminal instead.
class PairingActivateResult {
  const PairingActivateResult({
    required this.catalogId,
    this.cols = 0,
    this.rows = 0,
    this.fallback = false,
  });

  final String catalogId;
  final int cols;
  final int rows;
  final bool fallback;
}

/// A live mirror stream. [output] carries snapshot-then-live raw PTY bytes in
/// order (no client-side dedup needed — the host snapshots after attaching its
/// tee, so live frames never overlap the snapshot).
class PairingSubscription {
  PairingSubscription(this.sub, this._controller);
  final int sub;
  final StreamController<Uint8List> _controller;
  Stream<Uint8List> get output => _controller.stream;
}

/// Mobile pairing client: dials one of the host's LAN URLs, runs the X25519
/// handshake (pinning the host static key from the QR offer), authenticates,
/// then speaks JSON-RPC + binary terminal frames over the E2EE channel.
///
/// Connection progress is surfaced on [log] so the confirm UI can diagnose LAN
/// failures (wrong IP, firewall, expired code).
class PairingClient {
  PairingClient({
    Future<WsTransport> Function(Uri)? connector,
    Future<bool> Function(String host, int port)? portProbe,
  }) : _connector = connector ?? WsTransport.connect,
       _portProbe = portProbe ?? _tcpProbe;

  final Future<WsTransport> Function(Uri) _connector;

  /// Answers whether *something* accepts TCP on host:port. Used only to pick
  /// ladder candidates worth a full dial; injected in tests.
  final Future<bool> Function(String host, int port) _portProbe;

  /// A plain TCP connect: far cheaper than a WebSocket dial, and enough to tell
  /// a live listener from a dead port. A false positive (some other process on
  /// that port) just costs one failed dial afterwards.
  static Future<bool> _tcpProbe(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: probeTimeout);
      socket.destroy();
      return true;
    } on Object {
      return false;
    }
  }

  /// Per-candidate dial budget.
  ///
  /// An address that is merely unreachable — a stale VPN route, a subnet the
  /// phone is not on — blackholes the SYN rather than refusing it, so the dial
  /// would otherwise hang until the cubit's 25s budget for the whole [connect]
  /// expired, and the remaining candidates would never be tried at all. LAN
  /// round trips are milliseconds, so 4s is generous and still leaves room for
  /// every candidate the host is likely to advertise.
  static const dialTimeout = Duration(seconds: 4);

  /// Budget for one ladder probe. Deliberately far below [dialTimeout]: the
  /// ladder is walked only after every saved URL already failed, so a full dial
  /// per candidate would multiply an already-slow failure. A LAN handshake is
  /// milliseconds; anything slower is not the desktop we are looking for.
  static const probeTimeout = Duration(milliseconds: 500);

  /// Budget for a request the host answers from its own memory.
  static const _defaultRpcTimeout = Duration(seconds: 10);

  final _log = StreamController<String>.broadcast();
  Stream<String> get log => _log.stream;

  final _stages = StreamController<PairingStageEvent>.broadcast();

  /// Real connect progress, one event per [PairingStage] transition.
  Stream<PairingStageEvent> get stages => _stages.stream;

  WsTransport? _transport;
  E2eeChannel? _channel;

  /// The URL that actually connected — [connect] tries several, so the caller
  /// can't assume it was the first one.
  String? connectedUrl;
  StreamSubscription<Uint8List>? _inbound;

  var _nextId = 1;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final _subs = <int, StreamController<Uint8List>>{};

  Completer<void>? _handshake; // completes when hello.ack processed
  Completer<PairingAuthResult>? _auth;

  void _emit(String message, {bool error = false}) {
    appLogger.d('pairing client: $message');
    if (!_log.isClosed) _log.add(message);
  }

  void _stage(PairingStage stage, PairingStageStatus status) {
    if (!_stages.isClosed) _stages.add(PairingStageEvent(stage, status));
  }

  /// Tries each URL in turn until one connects and authenticates. [token] is the
  /// one-time pairing code (first pairing) or a stored device token (reconnect,
  /// with [deviceId] set). Throws if every URL fails or auth is rejected.
  Future<PairingAuthResult> connect({
    required List<String> wsUrls,
    required String token,
    required String hostPublicKeyB64,
    String? deviceId,
    String deviceName = 'Mobile device',
  }) async {
    Object? lastError;
    for (final url in wsUrls) {
      try {
        // Re-armed per URL: a failed candidate is retried on the next one, so
        // the rail shows "still dialing" rather than a premature failure.
        _stage(PairingStage.connect, PairingStageStatus.active);
        _emit('Connecting to $url…');
        return await _connectOne(
          url: url,
          token: token,
          hostPublicKeyB64: hostPublicKeyB64,
          deviceId: deviceId,
          deviceName: deviceName,
        );
      } on Object catch (e) {
        lastError = e;
        _emit('Failed on $url: $e', error: true);
        await _teardown();
      }
    }

    // Every saved URL is dead. Before declaring failure, re-probe the agreed
    // ladder on the same hosts: the desktop may have had to move ports (a second
    // instance held one, or it sits in a Windows excluded range), and a stored
    // URL pins the port it happened to bind at pairing time.
    for (final url in await _ladderCandidates(wsUrls)) {
      try {
        _stage(PairingStage.connect, PairingStageStatus.active);
        _emit('Retrying moved port: $url…');
        return await _connectOne(
          url: url,
          token: token,
          hostPublicKeyB64: hostPublicKeyB64,
          deviceId: deviceId,
          deviceName: deviceName,
        );
      } on Object catch (e) {
        lastError = e;
        _emit('Failed on $url: $e', error: true);
        await _teardown();
      }
    }
    throw Exception('All pairing URLs failed: $lastError');
  }

  /// Ladder ports on the hosts from [wsUrls] that answer a TCP probe, minus the
  /// host:port pairs already tried. Probes run concurrently per host so the whole
  /// sweep costs about one [probeTimeout], not one per candidate.
  Future<List<String>> _ladderCandidates(List<String> wsUrls) async {
    final tried = <String>{};
    final hosts = <String>[];
    for (final raw in wsUrls) {
      final url = Uri.tryParse(raw);
      final host = url?.host;
      if (url == null || host == null || host.isEmpty) continue;
      tried.add('$host:${url.port}');
      if (!hosts.contains(host)) hosts.add(host);
    }

    final candidates = <String>[];
    for (final host in hosts) {
      final ports = [
        for (final port in kPairingPortLadder)
          if (!tried.contains('$host:$port')) port,
      ];
      final live = await Future.wait(
        ports.map((port) => _portProbe(host, port)),
      );
      for (var i = 0; i < ports.length; i++) {
        if (live[i]) candidates.add('ws://$host:${ports[i]}/pair/ws');
      }
    }
    return candidates;
  }

  Future<PairingAuthResult> _connectOne({
    required String url,
    required String token,
    required String hostPublicKeyB64,
    required String? deviceId,
    required String deviceName,
  }) async {
    final transport = await _dial(Uri.parse(url));
    connectedUrl = url;
    _stage(PairingStage.connect, PairingStageStatus.done);
    _stage(PairingStage.secureChannel, PairingStageStatus.active);
    _transport = transport;
    _inbound = transport.inbound.listen(
      _onBytes,
      onError: (Object e) {
        _emit('socket error: $e', error: true);
        _signalDisconnected();
      },
      onDone: () {
        _emit('socket closed');
        _signalDisconnected();
      },
    );

    // Phase 1 — plaintext hello / hello.ack.
    final clientEphemeral = E2eeChannel.newEphemeral();
    _handshake = Completer<void>();
    _sendPlain({
      't': 'hello',
      'v': 1,
      'epk': clientEphemeral.publicKeyB64,
      if (deviceId != null) 'deviceId': deviceId,
    });
    final ack = await _awaitHelloAck();
    final hostEphemeral = PairingCrypto.publicKeyFromB64(ack['epk'] as String);
    final spk = ack['spk'] as String;
    if (spk != hostPublicKeyB64) {
      throw Exception('Host key mismatch — refusing (possible MITM)');
    }
    _channel = E2eeChannel.derive(
      myEphemeralPrivate: clientEphemeral.privateKey,
      theirEphemeralPublic: hostEphemeral,
    );
    _emit('Secure channel established');
    _stage(PairingStage.secureChannel, PairingStageStatus.done);
    _stage(PairingStage.authenticate, PairingStageStatus.active);

    // Phase 2 — encrypted auth.
    _auth = Completer<PairingAuthResult>();
    _sendEncryptedJson({
      'method': 'auth',
      'params': {
        'token': token,
        'deviceName': deviceName,
        if (deviceId != null) 'deviceId': deviceId,
      },
    });
    final result = await _auth!.future.timeout(const Duration(seconds: 10));
    _emit('Paired with ${result.hostName}');
    _stage(PairingStage.authenticate, PairingStageStatus.done);
    _authenticated = true;
    return result;
  }

  /// True once auth succeeded, so a candidate that merely failed mid-handshake
  /// is reported by [connect] throwing rather than as a lost connection.
  bool _authenticated = false;
  bool _closing = false;

  final _disconnected = StreamController<void>.broadcast();

  /// Fires when an established connection dies on its own — socket error, FIN,
  /// or an unanswered keepalive ping (see [kPairingPingInterval]). Deliberate
  /// [close] calls stay silent, so a listener can treat every event as
  /// "reconnect if the user still wants to be connected".
  Stream<void> get disconnected => _disconnected.stream;

  void _signalDisconnected() {
    if (!_authenticated || _closing) return;
    // Once is enough: onError is commonly followed by onDone for the same death.
    _authenticated = false;
    if (!_disconnected.isClosed) _disconnected.add(null);
  }

  /// Dials [url], giving up after [dialTimeout] so [connect] can move on.
  ///
  /// The abandoned future is still drained and its socket closed: dropping it
  /// would leak the descriptor for as long as the OS keeps retrying the
  /// handshake behind our back.
  Future<WsTransport> _dial(Uri url) {
    final pending = _connector(url);
    return pending.timeout(
      dialTimeout,
      onTimeout: () {
        unawaited(
          pending.then(
            (transport) => transport.close(),
            onError: (Object _) {},
          ),
        );
        throw TimeoutException('No response from $url', dialTimeout);
      },
    );
  }

  Future<Map<String, Object?>> _awaitHelloAck() async {
    final completer = _handshake!;
    _helloAck = null;
    await completer.future.timeout(const Duration(seconds: 10));
    return _helloAck!;
  }

  Map<String, Object?>? _helloAck;

  void _onBytes(Uint8List bytes) {
    try {
      if (_channel == null) {
        // Plaintext handshake phase.
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is Map && decoded['t'] == 'hello.ack') {
          _helloAck = decoded.cast<String, Object?>();
          _handshake?.complete();
        }
        return;
      }
      final frame = PairingCodec.decode(_channel!.decrypt(bytes));
      switch (frame) {
        case JsonFrame(:final data):
          _onJson(data);
        case OutputFrame(:final sub, :final bytes):
          _subs[sub]?.add(bytes);
        case SnapshotFrame(:final sub, :final bytes):
          _subs[sub]?.add(bytes);
        case InputFrame():
          break; // client never receives input frames
        case UploadFrame():
          break; // phone sends upload frames and never receives them
      }
    } on Object catch (e) {
      _emit('frame error: $e', error: true);
    }
  }

  void _onJson(Map<String, Object?> data) {
    // auth.ok / auth.err arrive as method events (no id).
    final method = data['method'];
    if (method == 'auth.ok') {
      final params = _params(data);
      _auth?.complete(
        PairingAuthResult(
          deviceId: params['deviceId'] as String? ?? '',
          hostName: params['hostName'] as String? ?? 'Desktop',
          deviceToken: params['deviceToken'] as String?,
        ),
      );
      return;
    }
    if (method == 'auth.err') {
      final reason = _params(data)['reason'] ?? 'rejected';
      _auth?.completeError(Exception('Auth failed: $reason'));
      return;
    }
    if (method == 'terminal.closed') {
      final sub = _params(data)['sub'];
      if (sub is int) _subs.remove(sub)?.close();
      return;
    }
    if (method == 'session.changed') {
      if (!_sessionsChanged.isClosed) _sessionsChanged.add(null);
      return;
    }
    if (method == 'agent.notice') {
      // Dropped silently when unusable (e.g. a kind this build predates), so a
      // newer desktop cannot break an older phone.
      final notice = PairingAgentNotice.tryFromJson(_params(data));
      if (notice != null && !_agentNotices.isClosed) _agentNotices.add(notice);
      return;
    }
    if (method == 'upload.ack') {
      final params = _params(data);
      final transferId = params['transferId'];
      final received = params['received'];
      if (transferId is int && received is int && !_uploadAcks.isClosed) {
        _uploadAcks.add(
          PairingUploadAck(transferId: transferId, received: received),
        );
      }
      return;
    }
    // JSON-RPC response correlated by id.
    final id = data['id'];
    if (id is int) {
      final pending = _pending.remove(id);
      if (pending == null) return;
      if (data.containsKey('error')) {
        pending.completeError(Exception(data['error'].toString()));
      } else {
        pending.complete(_result(data));
      }
    }
  }

  final _sessionsChanged = StreamController<void>.broadcast();

  /// Fires when the host reports its session set changed (refetch [listSessions]).
  Stream<void> get sessionsChanged => _sessionsChanged.stream;

  final _agentNotices = StreamController<PairingAgentNotice>.broadcast();

  /// Agent-attention edges pushed by the host, for a local phone notification.
  /// Only arrives while this client is connected: the socket dies when Android
  /// backgrounds the app, and there is no keepalive, reconnect, or backlog.
  Stream<PairingAgentNotice> get agentNotices => _agentNotices.stream;

  /// Test seam: [WsTransport] wraps a concrete `dart:io` WebSocket with no
  /// injectable interface, so the push arms are otherwise unreachable in tests.
  @visibleForTesting
  void debugHandleJson(Map<String, Object?> data) => _onJson(data);

  final _uploadAcks = StreamController<PairingUploadAck>.broadcast();

  /// Credit-window receipts for in-flight uploads. Broadcast because each
  /// upload attaches its own filtered listener.
  Stream<PairingUploadAck> get uploadAcks => _uploadAcks.stream;

  Future<List<PairingSessionSummary>> listSessions() async {
    final result = await _rpc('session.list');
    final raw = result['sessions'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          PairingSessionSummary(
            catalogId: item['catalogId'] as String? ?? '',
            title: item['title'] as String? ?? '',
            subtitle: item['subtitle'] as String? ?? '',
            cols: item['cols'] is int ? item['cols'] as int : 80,
            rows: item['rows'] is int ? item['rows'] as int : 24,
          ),
    ];
  }

  /// Fetches the workspace tree (every workspace and its live terminal panes).
  /// Defensive parse: unknown/missing fields fall back to sane defaults so a
  /// protocol skew never throws in the UI.
  Future<PairingWorkspaceListing> listWorkspaces() async {
    final result = await _rpc('workspace.list');
    final raw = result['workspaces'];
    final rawGroups = result['groups'];
    final rawTargets = result['targets'];
    return PairingWorkspaceListing(
      workspaces: [
        if (raw is List)
          for (final item in raw)
            if (item is Map) _parseWorkspace(item.cast<String, Object?>()),
      ],
      groups: [
        if (rawGroups is List)
          for (final g in rawGroups)
            if (g is Map) _parseGroup(g.cast<String, Object?>()),
      ],
      // Absent on a desktop that predates machine selection, which is exactly
      // the signal the UI keys off. An entry with no id is unusable as a
      // `targetId`, so drop it rather than offer a machine we cannot name.
      targets: [
        if (rawTargets is List)
          for (final t in rawTargets)
            if (t is Map && (t['id'] as String? ?? '').isNotEmpty)
              _parseTarget(t.cast<String, Object?>()),
      ],
    );
  }

  PairingGroup _parseGroup(Map<String, Object?> g) => PairingGroup(
    id: g['id'] as String? ?? '',
    name: g['name'] as String? ?? '',
    order: g['order'] is int ? g['order'] as int : 0,
  );

  PairingTarget _parseTarget(Map<String, Object?> t) {
    final id = t['id'] as String? ?? '';
    final label = t['label'] as String? ?? '';
    return PairingTarget(
      id: id,
      // A host that sent an id but no label still names a real machine; showing
      // the id beats showing an empty row.
      label: label.isEmpty ? id : label,
      kind: t['kind'] as String? ?? '',
    );
  }

  PairingWorkspaceNode _parseWorkspace(Map<String, Object?> ws) {
    final workspaceId = ws['workspaceId'] as String? ?? '';
    final rawPanes = ws['panes'];
    return PairingWorkspaceNode(
      workspaceId: workspaceId,
      title: ws['title'] as String? ?? '',
      groupId: ws['groupId'] as String? ?? '',
      panes: [
        if (rawPanes is List)
          for (final p in rawPanes)
            if (p is Map) _parseNode(workspaceId, p.cast<String, Object?>()),
      ],
    );
  }

  PairingSessionNode _parseNode(String workspaceId, Map<String, Object?> n) {
    return PairingSessionNode(
      workspaceId: workspaceId,
      title: n['title'] as String? ?? '',
      subtitle: n['subtitle'] as String? ?? '',
      live: n['live'] == true,
      paneId: n['paneId'] as String?,
      catalogId: n['catalogId'] as String?,
      cols: n['cols'] is int ? n['cols'] as int : 0,
      rows: n['rows'] is int ? n['rows'] as int : 0,
    );
  }

  /// Asks the host to activate a session/pane and returns the resulting
  /// [catalogId] to `terminal.subscribe`. Uses a longer timeout than the default
  /// because the host waits (bounded) for the session to come live — its own
  /// `activateTimeout` is 8s, so the default 10s left only a 2s margin despite
  /// this comment having always claimed otherwise.
  Future<PairingActivateResult> activateSession({
    required String workspaceId,
    String? paneId,
  }) async {
    final result = await _rpc(
      'session.activate',
      {'workspaceId': workspaceId, if (paneId != null) 'paneId': paneId},
      const Duration(seconds: 20),
    );
    final catalogId = result['catalogId'] as String?;
    if (catalogId == null || catalogId.isEmpty) {
      throw Exception('activate returned no catalogId');
    }
    return PairingActivateResult(
      catalogId: catalogId,
      cols: result['cols'] is int ? result['cols'] as int : 0,
      rows: result['rows'] is int ? result['rows'] as int : 0,
      fallback: result['fallback'] == true,
    );
  }

  /// Lists directories on the desktop so the phone can pick an existing folder
  /// when creating a workspace.
  ///
  /// [targetId] names the machine to list on; null means the host's default
  /// plane. [path] is interpreted in that machine's namespace, so the two must
  /// come from the same machine — null [path] asks the host for a sensible root.
  ///
  /// Named rather than positional: two bare optional `String?`s in a row are the
  /// classic pair to transpose.
  ///
  /// The budget is deliberately far above [_rpc]'s default. A cold SSH target
  /// makes the host connect, read the remote `$HOME`, and open SFTP before it can
  /// list anything — the SSH connect alone is allowed 10s. This is a single
  /// user-initiated browse, so waiting beats a spurious timeout.
  Future<PairingDirListing> browseDir({String? path, String? targetId}) async {
    final result = await _rpc(
      'fs.browse',
      {
        if (path != null) 'path': path,
        if (targetId != null && targetId.isNotEmpty) 'targetId': targetId,
      },
      const Duration(seconds: 30),
    );
    final rawDirs = result['dirs'];
    return PairingDirListing(
      path: result['path'] as String? ?? '',
      parent: result['parent'] as String?,
      dirs: [
        if (rawDirs is List)
          for (final d in rawDirs)
            if (d is String) d,
      ],
    );
  }

  /// Asks the desktop to create a workspace over [folderPath]; returns the new
  /// workspace id. [targetId] is the machine [folderPath] lives on (null = the
  /// host's default plane) and is what decides where the workspace's terminal
  /// will open.
  Future<String> createWorkspace({
    required String folderPath,
    String? title,
    String? groupId,
    String? targetId,
  }) async {
    final result = await _rpc('workspace.create', {
      'folderPath': folderPath,
      if (title != null && title.isNotEmpty) 'title': title,
      if (groupId != null && groupId.isNotEmpty) 'groupId': groupId,
      if (targetId != null && targetId.isNotEmpty) 'targetId': targetId,
    });
    final id = result['workspaceId'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('workspace.create returned no workspaceId');
    }
    return id;
  }

  /// Asks the desktop to create a workspace group; returns the new group id.
  Future<String> createGroup(String name) async {
    final result = await _rpc('group.create', {'name': name});
    final id = result['groupId'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('group.create returned no groupId');
    }
    return id;
  }

  Future<PairingSubscription> subscribe(String catalogId) async {
    final result = await _rpc('terminal.subscribe', {'catalogId': catalogId});
    final sub = result['sub'] as int;
    final controller = StreamController<Uint8List>.broadcast();
    _subs[sub] = controller;
    return PairingSubscription(sub, controller);
  }

  void unsubscribe(int sub) {
    _subs.remove(sub)?.close();
    _sendEncryptedJson({
      'method': 'terminal.unsubscribe',
      'params': {'sub': sub},
    });
  }

  void sendInput(int sub, Uint8List data) {
    _sendEncrypted(PairingCodec.encodeInput(sub, data));
  }

  void sendResize(int sub, int cols, int rows) {
    _sendEncryptedJson({
      'method': 'terminal.resize',
      'params': {'sub': sub, 'cols': cols, 'rows': rows},
    });
  }

  Future<String> uploadFile({
    required int sub,
    required String filename,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) {
    return PairingUploadSender(
      rpc: _rpc,
      send: _sendEncrypted,
      acks: uploadAcks,
    ).upload(
      sub: sub,
      filename: filename,
      bytes: bytes,
      onProgress: onProgress,
    );
  }

  /// [timeout] is positional rather than named because Dart forbids mixing
  /// optional positional and named parameters, and `params` was already
  /// positional. Callers that leave it out get [_defaultRpcTimeout], which suits
  /// every request the host answers from memory; the ones that make the host
  /// reach another machine pass their own.
  Future<Map<String, Object?>> _rpc(
    String method, [
    Map<String, Object?> params = const {},
    Duration timeout = _defaultRpcTimeout,
  ]) {
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _sendEncryptedJson({'id': id, 'method': method, 'params': params});
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('RPC $method timed out');
      },
    );
  }

  Map<String, Object?> _params(Map<String, Object?> data) =>
      data['params'] is Map
      ? (data['params'] as Map).cast<String, Object?>()
      : const {};

  Map<String, Object?> _result(Map<String, Object?> data) =>
      data['result'] is Map
      ? (data['result'] as Map).cast<String, Object?>()
      : const {};

  void _sendPlain(Map<String, Object?> data) {
    _transport?.send(Uint8List.fromList(utf8.encode(jsonEncode(data))));
  }

  void _sendEncrypted(Uint8List frame) {
    final channel = _channel;
    final transport = _transport;
    if (channel == null || transport == null) return;
    transport.send(channel.encrypt(frame));
  }

  void _sendEncryptedJson(Map<String, Object?> data) =>
      _sendEncrypted(PairingCodec.encodeJson(data));

  Future<void> _teardown() async {
    await _inbound?.cancel();
    _inbound = null;
    await _transport?.close();
    _transport = null;
    _channel = null;
  }

  Future<void> close() async {
    _closing = true;
    for (final controller in _subs.values) {
      await controller.close();
    }
    _subs.clear();
    await _teardown();
    await _log.close();
    await _stages.close();
    await _sessionsChanged.close();
    await _agentNotices.close();
    await _disconnected.close();
    await _uploadAcks.close();
  }
}
