import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../utils/logging/logger.dart';
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

/// Result of [PairingClient.listWorkspaces]: the workspace tree plus the host's
/// group index.
class PairingWorkspaceListing {
  const PairingWorkspaceListing({
    required this.workspaces,
    required this.groups,
  });

  final List<PairingWorkspaceNode> workspaces;
  final List<PairingGroup> groups;
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
      onError: (Object e) => _emit('socket error: $e', error: true),
      onDone: () => _emit('socket closed'),
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
    return result;
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
    );
  }

  PairingGroup _parseGroup(Map<String, Object?> g) => PairingGroup(
    id: g['id'] as String? ?? '',
    name: g['name'] as String? ?? '',
    order: g['order'] is int ? g['order'] as int : 0,
  );

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
  /// [catalogId] to `terminal.subscribe`. Uses a longer timeout than [_rpc]
  /// because the host waits (bounded) for the session to come live.
  Future<PairingActivateResult> activateSession({
    required String workspaceId,
    String? paneId,
  }) async {
    final result = await _rpc('session.activate', {
      'workspaceId': workspaceId,
      if (paneId != null) 'paneId': paneId,
    });
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
  /// when creating a workspace. [path] null opens the default workspace root.
  Future<PairingDirListing> browseDir([String? path]) async {
    final result = await _rpc('fs.browse', {
      if (path != null) 'path': path,
    });
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
  /// workspace id.
  Future<String> createWorkspace({
    required String folderPath,
    String? title,
    String? groupId,
  }) async {
    final result = await _rpc('workspace.create', {
      'folderPath': folderPath,
      if (title != null && title.isNotEmpty) 'title': title,
      if (groupId != null && groupId.isNotEmpty) 'groupId': groupId,
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

  Future<Map<String, Object?>> _rpc(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _sendEncryptedJson({'id': id, 'method': method, 'params': params});
    return completer.future.timeout(
      const Duration(seconds: 10),
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
    for (final controller in _subs.values) {
      await controller.close();
    }
    _subs.clear();
    await _teardown();
    await _log.close();
    await _stages.close();
    await _sessionsChanged.close();
    await _uploadAcks.close();
  }
}
