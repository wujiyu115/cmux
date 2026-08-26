import 'dart:io';

import '../../utils/logging/logger.dart';
import 'agent_notice_message.dart';
import 'device_registry.dart';
import 'pairing_connection.dart';
import 'pairing_crypto.dart';
import 'pairing_git_view.dart';
import 'pairing_offer.dart';
import 'pairing_ports.dart';
import 'pairing_upload_target.dart';
import 'pairing_workspace_index.dart';
import 'session_catalog.dart';
import 'ws_transport.dart';

/// Desktop-only LAN listener for phone pairing. Mirrors [AgentStatusGateway]'s
/// lifecycle (idempotent [ensureStarted], force-close [dispose]) but binds
/// `anyIPv4` so devices on the same network can reach it, and upgrades
/// `GET /pair/ws` to a WebSocket handed to a [PairingConnection].
///
/// Only ever constructed on a host platform behind a `isPairingHost && enabled`
/// gate — the mobile client never binds.
class LanPairingServer {
  LanPairingServer({
    required PairingKeyPair hostStaticKey,
    required DeviceRegistry registry,
    required SessionCatalog catalog,
    required String hostName,
    required PairingUploadOpener uploadOpener,
    PairingWorkspaceIndexProvider? workspaceIndex,
    PairingSessionActivator? activator,
    PairingDirBrowser? dirBrowser,
    PairingWorkspaceCreator? workspaceCreator,
    PairingGroupCreator? groupCreator,
    PairingGroupIndexProvider? groupIndex,
    PairingTargetIndexProvider? targetIndex,
    PairingGitChangesProvider? gitChanges,
    PairingGitDiffProvider? gitDiff,
    Stream<PairingAgentNotice>? agentNotices,
    PairingOfferWindow? offerWindow,
    List<int> ports = kPairingPortLadder,
  }) : _ports = ports,
       _agentNotices = agentNotices,
       _hostStaticKey = hostStaticKey,
       _registry = registry,
       _catalog = catalog,
       _hostName = hostName,
       _uploadOpener = uploadOpener,
       _workspaceIndex = workspaceIndex,
       _activator = activator,
       _dirBrowser = dirBrowser,
       _workspaceCreator = workspaceCreator,
       _groupCreator = groupCreator,
       _groupIndex = groupIndex,
       _targetIndex = targetIndex,
       _gitChanges = gitChanges,
       _gitDiff = gitDiff,
       offerWindow = offerWindow ?? PairingOfferWindow();

  /// Ports [ensureStarted] tries in order. `[0]` means "any", which tests use to
  /// avoid contending with a real desktop on the same machine.
  final List<int> _ports;

  final PairingKeyPair _hostStaticKey;
  final DeviceRegistry _registry;
  final SessionCatalog _catalog;
  final String _hostName;
  final PairingUploadOpener _uploadOpener;
  final PairingWorkspaceIndexProvider? _workspaceIndex;
  final PairingSessionActivator? _activator;
  final PairingDirBrowser? _dirBrowser;
  final PairingWorkspaceCreator? _workspaceCreator;
  final PairingGroupCreator? _groupCreator;
  final PairingGroupIndexProvider? _groupIndex;
  final PairingTargetIndexProvider? _targetIndex;
  final PairingGitChangesProvider? _gitChanges;
  final PairingGitDiffProvider? _gitDiff;

  /// Broadcast feed of agent-attention edges, handed to every connection so each
  /// authenticated phone can pop its own local notification.
  final Stream<PairingAgentNotice>? _agentNotices;

  /// One-time pairing-code window; [createOffer] opens it, auth consumes it.
  final PairingOfferWindow offerWindow;

  HttpServer? _http;
  final _connections = <PairingConnection>{};

  bool get isRunning => _http != null;

  /// Whether any phone is authenticated right now. Sockets still handshaking do
  /// not count — see [PairingConnection.isAuthenticated].
  bool get hasAuthenticatedClient =>
      _connections.any((connection) => connection.isAuthenticated);

  int get port => _http!.port;

  /// Claims the first port of [_ports] that binds, so a phone's saved URL keeps
  /// working across desktop restarts.
  ///
  /// Binding a fixed port genuinely fails in the field: a second instance holds
  /// it, or it sits inside a Windows excluded range (Hyper-V / WSL / Docker
  /// reservations), where bind returns access-denied with nothing listening.
  /// Hence the ladder — every port in it is one a stranded phone will re-probe.
  /// Only when the whole ladder is refused does this fall back to an ephemeral
  /// port, which keeps pairing usable for a fresh scan but is the one case saved
  /// URLs cannot survive.
  Future<void> ensureStarted() async {
    if (_http != null) return;
    HttpServer? server;
    final refusals = <String>[];
    for (final port in _ports) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        break;
      } on SocketException catch (error) {
        refusals.add('$port (${error.osError?.message ?? error.message})');
      }
    }
    if (server == null) {
      appLogger.w(
        '[pairing] no agreed port could be bound; using an ephemeral one. '
        'Phones paired before now will have to scan again. Refused: '
        '${refusals.join(', ')}',
      );
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    } else if (refusals.isNotEmpty) {
      // Still reachable — a stranded phone probes the whole ladder — but worth
      // saying out loud, because it means reconnect now costs extra probes.
      appLogger.w(
        '[pairing] listening on :${server.port} after refusals: '
        '${refusals.join(', ')}',
      );
    }
    _http = server;
    server.listen(_onRequest);
    appLogger.d('LanPairingServer listening on :${server.port}');
  }

  Future<void> _onRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/pair/health') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('application', 'json')
          ..write('{"ok":true}');
        await request.response.close();
        return;
      }
      if (path == '/pair/ws' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _accept(WsTransport(socket));
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (e) {
      appLogger.d('LanPairingServer request error: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  void _accept(WsTransport transport) {
    late final PairingConnection connection;
    connection = PairingConnection(
      transport: transport,
      hostStaticKey: _hostStaticKey,
      offerWindow: offerWindow,
      registry: _registry,
      catalog: _catalog,
      hostName: _hostName,
      uploadOpener: _uploadOpener,
      workspaceIndex: _workspaceIndex,
      activator: _activator,
      dirBrowser: _dirBrowser,
      workspaceCreator: _workspaceCreator,
      groupCreator: _groupCreator,
      groupIndex: _groupIndex,
      targetIndex: _targetIndex,
      gitChanges: _gitChanges,
      gitDiff: _gitDiff,
      agentNotices: _agentNotices,
      onClosed: () => _connections.remove(connection),
    );
    _connections.add(connection);
    connection.start();
  }

  /// Opens a fresh TTL pairing window and builds the QR/deep-link offer with the
  /// current LAN URLs and the pinned host static public key.
  Future<PairingOffer> createOffer({
    Duration ttl = PairingOfferWindow.defaultTtl,
  }) async {
    final token = offerWindow.open(ttl: ttl);
    final urls = await lanWsUrls();
    return PairingOffer(
      version: PairingOffer.currentVersion,
      wsUrls: urls,
      token: token,
      hostPublicKeyB64: _hostStaticKey.publicKeyB64,
      expiresAtMs: offerWindow.expiresAtMs,
    );
  }

  /// Every non-loopback IPv4 `ws://ip:port/pair/ws` the client can try in turn.
  Future<List<String>> lanWsUrls() async {
    if (_http == null) return const [];
    final p = _http!.port;
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return [
      for (final iface in interfaces)
        for (final addr in iface.addresses) 'ws://${addr.address}:$p/pair/ws',
    ];
  }

  Future<void> dispose() async {
    for (final connection in _connections.toList()) {
      connection.dispose();
    }
    _connections.clear();
    offerWindow.close();
    await _http?.close(force: true);
    _http = null;
  }
}
