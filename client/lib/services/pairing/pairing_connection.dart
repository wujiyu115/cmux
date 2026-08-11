import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../utils/logging/logger.dart';
import 'device_registry.dart';
import 'e2ee_channel.dart';
import 'pairing_crypto.dart';
import 'pairing_frames.dart';
import 'pairing_offer.dart';
import 'pairing_rpc_handler.dart';
import 'pairing_upload_receiver.dart';
import 'pairing_workspace_index.dart';
import 'session_catalog.dart';
import 'ws_transport.dart';

enum _ConnPhase { awaitingHello, awaitingAuth, active, closed }

/// One mobile client's lifetime on the host: plaintext X25519 handshake →
/// encrypted auth (one-time pairing code *or* a stored device token) → JSON-RPC
/// over the E2EE channel via [PairingRpcHandler]. Closing tears down the handler
/// (and thus every mirror subscription) and the catalog listener.
class PairingConnection {
  PairingConnection({
    required WsTransport transport,
    required PairingKeyPair hostStaticKey,
    required PairingOfferWindow offerWindow,
    required DeviceRegistry registry,
    required SessionCatalog catalog,
    required String hostName,
    required PairingUploadSink uploadSink,
    PairingWorkspaceIndexProvider? workspaceIndex,
    PairingSessionActivator? activator,
    PairingDirBrowser? dirBrowser,
    PairingWorkspaceCreator? workspaceCreator,
    PairingGroupCreator? groupCreator,
    PairingGroupIndexProvider? groupIndex,
    void Function()? onClosed,
  }) : _transport = transport,
       _hostStaticKey = hostStaticKey,
       _offerWindow = offerWindow,
       _registry = registry,
       _catalog = catalog,
       _hostName = hostName,
       _uploadSink = uploadSink,
       _workspaceIndex = workspaceIndex,
       _activator = activator,
       _dirBrowser = dirBrowser,
       _workspaceCreator = workspaceCreator,
       _groupCreator = groupCreator,
       _groupIndex = groupIndex,
       _onClosed = onClosed;

  final WsTransport _transport;
  final PairingKeyPair _hostStaticKey;
  final PairingOfferWindow _offerWindow;
  final DeviceRegistry _registry;
  final SessionCatalog _catalog;
  final String _hostName;
  final PairingUploadSink _uploadSink;
  final PairingWorkspaceIndexProvider? _workspaceIndex;
  final PairingSessionActivator? _activator;
  final PairingDirBrowser? _dirBrowser;
  final PairingWorkspaceCreator? _workspaceCreator;
  final PairingGroupCreator? _groupCreator;
  final PairingGroupIndexProvider? _groupIndex;
  final void Function()? _onClosed;

  _ConnPhase _phase = _ConnPhase.awaitingHello;
  E2eeChannel? _channel;
  PairingRpcHandler? _handler;
  StreamSubscription<Uint8List>? _inbound;
  StreamSubscription<void>? _catalogChanges;

  void start() {
    _inbound = _transport.inbound.listen(
      _onBytes,
      onError: (Object e) => _close('inbound error: $e'),
      onDone: () => _close('socket closed'),
    );
  }

  void _onBytes(Uint8List bytes) {
    try {
      switch (_phase) {
        case _ConnPhase.awaitingHello:
          _handleHello(bytes);
        case _ConnPhase.awaitingAuth:
          _handleAuth(_decodeEncrypted(bytes));
        case _ConnPhase.active:
          _handler?.handle(_decodeEncrypted(bytes));
        case _ConnPhase.closed:
          break;
      }
    } on Object catch (e) {
      appLogger.d('pairing connection frame error: $e');
      _close('frame error');
    }
  }

  // Phase 1 — plaintext hello/hello.ack, ephemeral↔ephemeral ECDH.
  void _handleHello(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || decoded['t'] != 'hello') {
      throw const FormatException('expected hello');
    }
    final epk = decoded['epk'];
    if (epk is! String) throw const FormatException('hello missing epk');
    final clientEphemeral = PairingCrypto.publicKeyFromB64(epk);
    final hostEphemeral = E2eeChannel.newEphemeral();
    _channel = E2eeChannel.derive(
      myEphemeralPrivate: hostEphemeral.privateKey,
      theirEphemeralPublic: clientEphemeral,
    );
    _sendPlain({
      't': 'hello.ack',
      'epk': hostEphemeral.publicKeyB64,
      'spk': _hostStaticKey.publicKeyB64,
    });
    _phase = _ConnPhase.awaitingAuth;
  }

  // Phase 2 — encrypted auth frame.
  Future<void> _handleAuth(PairingFrame frame) async {
    if (frame is! JsonFrame || frame.data['method'] != 'auth') {
      throw const FormatException('expected auth');
    }
    final params = frame.data['params'] is Map
        ? (frame.data['params'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final token = params['token'];
    if (token is! String || token.isEmpty) {
      _sendEncryptedJson({'method': 'auth.err', 'params': {'reason': 'no token'}});
      _close('auth: no token');
      return;
    }
    final deviceName = params['deviceName'] is String
        ? params['deviceName'] as String
        : 'Mobile device';
    final deviceId = params['deviceId'];

    // First pairing: the one-time code consumes the open offer window.
    if (_offerWindow.consume(token)) {
      final registered = await _registry.register(name: deviceName);
      _acceptAuth(deviceId: registered.deviceId, deviceToken: registered.token);
      return;
    }
    // Reconnect: a stored device token.
    if (deviceId is String &&
        await _registry.validate(deviceId: deviceId, token: token)) {
      _acceptAuth(deviceId: deviceId, deviceToken: null);
      return;
    }
    _sendEncryptedJson({
      'method': 'auth.err',
      'params': {'reason': 'invalid token'},
    });
    _close('auth: invalid token');
  }

  void _acceptAuth({required String deviceId, String? deviceToken}) {
    _sendEncryptedJson({
      'method': 'auth.ok',
      'params': {
        'deviceId': deviceId,
        if (deviceToken != null) 'deviceToken': deviceToken,
        'hostName': _hostName,
      },
    });
    _handler = PairingRpcHandler(
      catalog: _catalog,
      send: _sendEncrypted,
      uploadSink: _uploadSink,
      workspaceIndex: _workspaceIndex,
      activator: _activator,
      dirBrowser: _dirBrowser,
      workspaceCreator: _workspaceCreator,
      groupCreator: _groupCreator,
      groupIndex: _groupIndex,
    );
    _catalogChanges = _catalog.changes.listen(
      (_) => _sendEncryptedJson({'method': 'session.changed'}),
    );
    _phase = _ConnPhase.active;
  }

  PairingFrame _decodeEncrypted(Uint8List wire) {
    final channel = _channel;
    if (channel == null) throw const FormatException('channel not derived');
    return PairingCodec.decode(channel.decrypt(wire));
  }

  void _sendPlain(Map<String, Object?> data) {
    _transport.send(Uint8List.fromList(utf8.encode(jsonEncode(data))));
  }

  void _sendEncrypted(Uint8List frame) {
    final channel = _channel;
    if (channel == null || _phase == _ConnPhase.closed) return;
    _transport.send(channel.encrypt(frame));
  }

  void _sendEncryptedJson(Map<String, Object?> data) =>
      _sendEncrypted(PairingCodec.encodeJson(data));

  void _close(String reason) {
    if (_phase == _ConnPhase.closed) return;
    _phase = _ConnPhase.closed;
    appLogger.d('pairing connection closed: $reason');
    _handler?.dispose();
    _handler = null;
    _catalogChanges?.cancel();
    _catalogChanges = null;
    _inbound?.cancel();
    _inbound = null;
    unawaited(_transport.close());
    _onClosed?.call();
  }

  void dispose() => _close('disposed');
}
