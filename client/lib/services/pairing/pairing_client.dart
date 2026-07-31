import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../utils/logging/logger.dart';
import 'e2ee_channel.dart';
import 'pairing_crypto.dart';
import 'pairing_frames.dart';
import 'ws_transport.dart';

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

/// One mirrorable session as advertised by the host's `session.list`.
class PairingSessionSummary {
  const PairingSessionSummary({
    required this.catalogId,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.cols,
    required this.rows,
  });

  final String catalogId;
  final String kind;
  final String title;
  final String subtitle;
  final int cols;
  final int rows;
}

/// One node under a workspace in the `workspace.list` tree: either a persisted
/// chat session (`kind == 'chat'`, keyed by [sessionId]) or a live workspace
/// terminal pane (`kind == 'workspace'`, keyed by [paneId]). [live] is true when
/// the host currently has it running; [catalogId] is only present when live and
/// is what [subscribe] takes.
class PairingSessionNode {
  const PairingSessionNode({
    required this.workspaceId,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.live,
    this.sessionId,
    this.paneId,
    this.memberId,
    this.cli,
    this.started = false,
    this.catalogId,
    this.cols = 0,
    this.rows = 0,
  });

  final String workspaceId;
  final String kind; // 'chat' | 'workspace'
  final String title;
  final String subtitle;
  final bool live;
  final String? sessionId;
  final String? paneId;
  final String? memberId;
  final String? cli;
  final bool started;
  final String? catalogId;
  final int cols;
  final int rows;

  /// Stable per-row identity: live catalogId if any, else kind-scoped local id.
  String get nodeKey =>
      catalogId ?? '$kind:${sessionId ?? paneId ?? ''}';
}

/// One workspace and its child nodes, as advertised by `workspace.list`. Covers
/// dormant workspaces (no live terminals) too.
class PairingWorkspaceNode {
  const PairingWorkspaceNode({
    required this.workspaceId,
    required this.title,
    this.sessions = const [],
    this.panes = const [],
  });

  final String workspaceId;
  final String title;
  final List<PairingSessionNode> sessions;
  final List<PairingSessionNode> panes;
}

/// Outcome of [PairingClient.activateSession]: the catalogId to subscribe to,
/// its live geometry, and whether the host fell back to opening a plain
/// workspace terminal instead of resuming the requested chat session.
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
  PairingClient({Future<WsTransport> Function(Uri)? connector})
    : _connector = connector ?? WsTransport.connect;

  final Future<WsTransport> Function(Uri) _connector;

  final _log = StreamController<String>.broadcast();
  Stream<String> get log => _log.stream;

  WsTransport? _transport;
  E2eeChannel? _channel;
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
    throw Exception('All pairing URLs failed: $lastError');
  }

  Future<PairingAuthResult> _connectOne({
    required String url,
    required String token,
    required String hostPublicKeyB64,
    required String? deviceId,
    required String deviceName,
  }) async {
    final transport = await _connector(Uri.parse(url));
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
    return result;
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

  Future<List<PairingSessionSummary>> listSessions() async {
    final result = await _rpc('session.list');
    final raw = result['sessions'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          PairingSessionSummary(
            catalogId: item['catalogId'] as String? ?? '',
            kind: item['kind'] as String? ?? 'chat',
            title: item['title'] as String? ?? '',
            subtitle: item['subtitle'] as String? ?? '',
            cols: item['cols'] is int ? item['cols'] as int : 80,
            rows: item['rows'] is int ? item['rows'] as int : 24,
          ),
    ];
  }

  /// Fetches the full workspace tree (every workspace, its persisted chat
  /// sessions and its live panes). Defensive parse: unknown/missing fields fall
  /// back to sane defaults so a protocol skew never throws in the UI.
  Future<List<PairingWorkspaceNode>> listWorkspaces() async {
    final result = await _rpc('workspace.list');
    final raw = result['workspaces'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) _parseWorkspace(item.cast<String, Object?>()),
    ];
  }

  PairingWorkspaceNode _parseWorkspace(Map<String, Object?> ws) {
    final workspaceId = ws['workspaceId'] as String? ?? '';
    final rawSessions = ws['sessions'];
    final rawPanes = ws['panes'];
    return PairingWorkspaceNode(
      workspaceId: workspaceId,
      title: ws['title'] as String? ?? '',
      sessions: [
        if (rawSessions is List)
          for (final s in rawSessions)
            if (s is Map)
              _parseNode(workspaceId, s.cast<String, Object?>(), 'chat'),
      ],
      panes: [
        if (rawPanes is List)
          for (final p in rawPanes)
            if (p is Map)
              _parseNode(workspaceId, p.cast<String, Object?>(), 'workspace'),
      ],
    );
  }

  PairingSessionNode _parseNode(
    String workspaceId,
    Map<String, Object?> n,
    String fallbackKind,
  ) {
    return PairingSessionNode(
      workspaceId: workspaceId,
      kind: n['kind'] as String? ?? fallbackKind,
      title: n['title'] as String? ?? '',
      subtitle: n['subtitle'] as String? ?? '',
      live: n['live'] == true,
      sessionId: n['sessionId'] as String?,
      paneId: n['paneId'] as String?,
      memberId: n['memberId'] as String?,
      cli: n['cli'] as String?,
      started: n['started'] == true,
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
    required String kind,
    String? sessionId,
    String? memberId,
    String? paneId,
  }) async {
    final result = await _rpc('session.activate', {
      'workspaceId': workspaceId,
      'kind': kind,
      if (sessionId != null) 'sessionId': sessionId,
      if (memberId != null) 'memberId': memberId,
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
    await _sessionsChanged.close();
  }
}
