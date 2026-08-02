import 'dart:async';
import 'dart:typed_data';

import '../terminal/terminal_session.dart';
import 'pairing_frames.dart';
import 'pairing_upload_receiver.dart';
import 'pairing_workspace_index.dart';
import 'session_catalog.dart';

/// Encoded application frame, ready to be E2EE-boxed and put on the socket.
typedef PairingFrameSender = void Function(Uint8List frame);

/// One live mirror subscription owned by a connection: the resolved session plus
/// the tee listener and its ~5ms output-coalescing batch.
class _Subscription {
  _Subscription(this.sub, this.catalogId, this.session);

  final int sub;
  final String catalogId;
  final TerminalSession session;
  StreamSubscription<Uint8List>? listener;
  final _batch = BytesBuilder(copy: false);
  Timer? flushTimer;
}

/// Per-connection JSON-RPC + terminal I/O dispatcher (runs *inside* the E2EE
/// channel, after auth). Owns this connection's subscription book; [dispose]
/// tears every listener down so a dropped socket leaks nothing.
///
/// Requests: `session.list`, `terminal.subscribe|unsubscribe|resize`,
/// `upload.begin`, `upload.commit`, `ping`. Binary [InputFrame]s carry
/// `terminal.input`; binary [UploadFrame]s carry image chunks (`_onUploadChunk`
/// acks each accepted one). Output is pushed as batched binary frames with a
/// monotonic `seq`, preceded on subscribe by one snapshot.
class PairingRpcHandler {
  PairingRpcHandler({
    required SessionCatalog catalog,
    required PairingFrameSender send,
    required PairingUploadSink uploadSink,
    Duration batchWindow = const Duration(milliseconds: 5),
    PairingWorkspaceIndexProvider? workspaceIndex,
    PairingSessionActivator? activator,
    Duration activateTimeout = const Duration(seconds: 8),
    Duration activatePollInterval = const Duration(milliseconds: 40),
    int uploadMaxBytes = 25 * 1024 * 1024,
    int uploadChunkSize = 64 * 1024,
    // Injection point for tests: production always builds the receiver from the
    // sink below. A fake here lets a test assert the handler's calls into it.
    PairingUploadReceiver? uploadReceiver,
  }) : _catalog = catalog,
       _send = send,
       _batchWindow = batchWindow,
       _workspaceIndex = workspaceIndex,
       _activator = activator,
       _activateTimeout = activateTimeout,
       _activatePollInterval = activatePollInterval,
       _uploads =
           uploadReceiver ??
           PairingUploadReceiver(
             sink: uploadSink,
             maxBytes: uploadMaxBytes,
             chunkSize: uploadChunkSize,
           );

  final SessionCatalog _catalog;
  final PairingFrameSender _send;
  final Duration _batchWindow;
  final PairingWorkspaceIndexProvider? _workspaceIndex;
  final PairingSessionActivator? _activator;
  final Duration _activateTimeout;
  final Duration _activatePollInterval;
  final PairingUploadReceiver _uploads;

  final _subs = <int, _Subscription>{};
  var _nextSub = 1;
  var _disposed = false;

  void handle(PairingFrame frame) {
    if (_disposed) return;
    switch (frame) {
      case JsonFrame(:final data):
        _handleJson(data);
      case InputFrame(:final sub, :final bytes):
        _subs[sub]?.session.writeRemoteInput(bytes);
      case OutputFrame():
      case SnapshotFrame():
        // Host never receives output/snapshot frames — ignore defensively.
        break;
      case UploadFrame(:final transferId, :final chunkIndex, :final bytes):
        _onUploadChunk(transferId, chunkIndex, bytes);
    }
  }

  void _handleJson(Map<String, Object?> data) {
    final id = data['id'];
    final method = data['method'];
    if (method is! String) return;
    final params = data['params'] is Map
        ? (data['params'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    switch (method) {
      case 'session.list':
        _replyResult(id, {'sessions': _sessionList()});
      case 'workspace.list':
        _workspaceList(id);
      case 'session.activate':
        _activate(id, params);
      case 'terminal.subscribe':
        _subscribe(id, params);
      case 'terminal.unsubscribe':
        _unsubscribe(params);
        _replyResult(id, const {'ok': true});
      case 'terminal.resize':
        _resize(params);
        _replyResult(id, const {'ok': true});
      case 'upload.begin':
        _uploadBegin(id, params);
      case 'upload.commit':
        // `_handleJson` is sync; the commit awaits the sink write.
        unawaited(_uploadCommit(id, params));
      case 'ping':
        _replyResult(id, const {'pong': true});
      default:
        _replyError(id, 'unknown method: $method');
    }
  }

  List<Map<String, Object?>> _sessionList() => [
    for (final entry in _catalog.list())
      {
        'catalogId': entry.ref.catalogId,
        'title': entry.ref.title,
        'subtitle': entry.ref.subtitle,
        'cols': entry.session.viewWidth,
        'rows': entry.session.viewHeight,
      },
  ];

  /// Full workspace tree: every workspace from disk with its live terminal panes
  /// merged in from the [SessionCatalog]. Workspaces with nothing running are
  /// still listed — the phone can open a terminal in them via `session.activate`.
  Future<void> _workspaceList(Object? id) async {
    final provider = _workspaceIndex;
    if (provider == null) {
      _replyError(id, 'workspace.list unsupported');
      return;
    }
    List<PairingWorkspaceInfo> workspaces;
    try {
      workspaces = await provider();
    } on Object catch (e) {
      _replyError(id, 'workspace.list failed: $e');
      return;
    }
    if (_disposed) return;

    // Snapshot the live catalog once so every workspace reads the same view.
    final live = _catalog.list();

    final out = <Map<String, Object?>>[];
    for (final ws in workspaces) {
      final panes = <Map<String, Object?>>[
        for (final entry in live)
          if (entry.ref.workspaceId == ws.workspaceId)
            {
              'paneId': entry.ref.paneId,
              'title': entry.ref.title,
              'subtitle': entry.ref.subtitle,
              'live': true,
              'catalogId': entry.ref.catalogId,
              'cols': entry.session.viewWidth,
              'rows': entry.session.viewHeight,
            },
      ];
      out.add({
        'workspaceId': ws.workspaceId,
        'title': ws.title,
        'panes': panes,
      });
    }
    _replyResult(id, {'workspaces': out});
  }

  /// Opens/reuses a terminal host-side, then waits (bounded) for it to appear
  /// live in the catalog before returning its catalogId so the client can
  /// immediately `terminal.subscribe`.
  Future<void> _activate(Object? id, Map<String, Object?> params) async {
    final activator = _activator;
    if (activator == null) {
      _replyError(id, 'session.activate unsupported');
      return;
    }
    final workspaceId = params['workspaceId'];
    if (workspaceId is! String) {
      _replyError(id, 'session.activate requires workspaceId');
      return;
    }
    final request = PairingActivationRequest(
      workspaceId: workspaceId,
      paneId: params['paneId'] is String ? params['paneId'] as String : null,
    );

    PairingActivationResult? result;
    try {
      result = await activator(request);
    } on Object catch (e) {
      _replyError(id, 'session.activate failed: $e');
      return;
    }
    if (_disposed) return;
    if (result == null) {
      _replyError(id, 'activation returned no session');
      return;
    }

    final entry = await _awaitCatalog(result.catalogId);
    if (_disposed) return;
    if (entry == null) {
      _replyError(id, 'session did not become live: ${result.catalogId}');
      return;
    }
    _replyResult(id, {
      'catalogId': entry.ref.catalogId,
      'cols': entry.session.viewWidth,
      'rows': entry.session.viewHeight,
      'fallback': result.fallback,
    });
  }

  /// Polls the catalog until [catalogId] resolves to a live session or the
  /// activate timeout elapses. [SessionCatalog.resolve] only ever returns
  /// running sessions, so a non-null result is a reliable liveness signal.
  Future<SessionCatalogEntry?> _awaitCatalog(String catalogId) async {
    final deadline = _activateTimeout.inMicroseconds;
    var waited = 0;
    while (!_disposed) {
      final entry = _catalog.resolve(catalogId);
      if (entry != null) return entry;
      if (waited >= deadline) return null;
      await Future<void>.delayed(_activatePollInterval);
      waited += _activatePollInterval.inMicroseconds;
    }
    return null;
  }

  void _subscribe(Object? id, Map<String, Object?> params) {
    final catalogId = params['catalogId'];
    if (catalogId is! String) {
      _replyError(id, 'terminal.subscribe requires catalogId');
      return;
    }
    final entry = _catalog.resolve(catalogId);
    if (entry == null) {
      _replyError(id, 'no such session: $catalogId');
      return;
    }
    final session = entry.session;
    final sub = _nextSub++;
    final record = _Subscription(sub, catalogId, session);
    _subs[sub] = record;
    // The desktop pane yields the grid while this phone mirrors it.
    session.attachMirror();

    // Attach the tee listener BEFORE snapshotting so no bytes slip through the
    // gap; the client dedups by seq against the snapshot high-water mark.
    record.listener = session.mirrorOutput.listen(
      (bytes) => _onOutput(record, bytes),
      onDone: () => _closeSub(sub, 'ended'),
    );
    final snap = session.recentBuffer?.snapshot();
    final seq = snap?.seq ?? 0;
    _replyResult(id, {
      'sub': sub,
      'cols': session.viewWidth,
      'rows': session.viewHeight,
      'seq': seq,
    });
    if (snap != null && snap.bytes.isNotEmpty) {
      _send(PairingCodec.encodeSnapshot(sub, snap.seq, snap.bytes));
    }
  }

  void _onOutput(_Subscription record, Uint8List bytes) {
    record._batch.add(bytes);
    record.flushTimer ??= Timer(_batchWindow, () => _flush(record));
  }

  void _flush(_Subscription record) {
    record.flushTimer = null;
    if (record._batch.isEmpty) return;
    final bytes = record._batch.takeBytes();
    final seq = record.session.recentBuffer?.seq ?? bytes.length;
    _send(PairingCodec.encodeOutput(record.sub, seq, bytes));
  }

  void _unsubscribe(Map<String, Object?> params) {
    final sub = params['sub'];
    if (sub is int) _closeSub(sub, 'client');
  }

  void _resize(Map<String, Object?> params) {
    final sub = params['sub'];
    final cols = params['cols'];
    final rows = params['rows'];
    if (sub is! int || cols is! int || rows is! int) return;
    _subs[sub]?.session.onTerminalPtyResize(cols, rows);
  }

  void _closeSub(int sub, String reason) {
    final record = _subs.remove(sub);
    if (record == null) return;
    record.flushTimer?.cancel();
    record.listener?.cancel();
    // Last phone off this terminal releases the desktop back to its own grid.
    record.session.detachMirror();
    _send(PairingCodec.encodeJson({
      'method': 'terminal.closed',
      'params': {'sub': sub, 'reason': reason},
    }));
  }

  /// Upload replies carry success in the *result* envelope rather than the
  /// JSON-RPC `error` field: [_replyError] sends a bare string that the client
  /// turns into `Exception(message)`, so a structured code could not survive
  /// the trip. Do not "fix" this back to the error channel.
  void _uploadBegin(Object? id, Map<String, Object?> params) {
    final sub = params['sub'];
    final filename = params['filename'];
    final size = params['size'];
    final record = sub is int ? _subs[sub] : null;
    if (record == null || filename is! String || size is! int) {
      _replyResult(id, const {'ok': false, 'code': 'no_target'});
      return;
    }
    final entry = _catalog.resolve(record.catalogId);
    if (entry == null) {
      _replyResult(id, const {'ok': false, 'code': 'no_target'});
      return;
    }
    final result = _uploads.begin(
      workspaceId: entry.ref.workspaceId,
      cwd: record.session.runtimeTarget.workingDirectory,
      filename: filename,
      size: size,
    );
    _replyResult(
      id,
      result.isOk
          ? {
              'ok': true,
              'transferId': result.transferId,
              'chunkSize': result.chunkSize,
            }
          : {'ok': false, 'code': result.code},
    );
  }

  void _onUploadChunk(int transferId, int chunkIndex, Uint8List bytes) {
    final result = _uploads.chunk(transferId, chunkIndex, bytes);
    // Only a good chunk reopens the credit window. Acking a rejected chunk
    // would let the phone keep streaming into a dead transfer.
    if (!result.isOk) return;
    _send(
      PairingCodec.encodeJson({
        'method': 'upload.ack',
        'params': {'transferId': transferId, 'received': result.received},
      }),
    );
  }

  Future<void> _uploadCommit(Object? id, Map<String, Object?> params) async {
    final transferId = params['transferId'];
    if (transferId is! int) {
      _replyResult(id, const {'ok': false, 'code': 'unknown_transfer'});
      return;
    }
    final result = await _uploads.commit(transferId);
    _replyResult(
      id,
      result.isOk
          ? {'ok': true, 'path': result.path}
          : {'ok': false, 'code': result.code},
    );
  }

  void _replyResult(Object? id, Map<String, Object?> result) {
    if (id == null) return;
    _send(PairingCodec.encodeJson({'id': id, 'result': result}));
  }

  void _replyError(Object? id, String message) {
    if (id == null) return;
    _send(PairingCodec.encodeJson({'id': id, 'error': message}));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Release every unfinished transfer's bytes: a connection that closes
    // mid-upload must not pin them, or a phone that reconnects repeatedly
    // feeds the desktop's memory.
    _uploads.abandonAll();
    for (final record in _subs.values) {
      record.flushTimer?.cancel();
      record.listener?.cancel();
      // Covers dropped link / crash / auth failure / server shutdown — the
      // desktop must never stay locked because a phone went away silently.
      record.session.detachMirror();
    }
    _subs.clear();
  }
}
