import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/pairing_key_store.dart';
import 'package:teampilot/services/pairing/device_registry.dart';
import 'package:teampilot/services/pairing/lan_pairing_server.dart';
import 'package:teampilot/services/pairing/pairing_crypto.dart';
import 'package:teampilot/services/pairing/session_catalog.dart';
import '../../support/pairing_upload_doubles.dart';

// NOTE: TestWidgetsFlutterBinding blocks real outbound HTTP (HttpClient returns
// 400 with no socket), so these tests exercise the server's lifecycle + offer
// wiring rather than a real request round-trip. The health/WS request path is
// covered end-to-end on device, per the plan's manual verification.

/// [ports] defaults to `[0]` rather than [kPairingPortLadder]: a real desktop may
/// hold the ladder on the machine running these tests, and the lifecycle cases do
/// not care which port they get.
LanPairingServer _server(PairingKeyPair key, {List<int> ports = const [0]}) =>
    LanPairingServer(
  hostStaticKey: key,
  registry: DeviceRegistry(InMemoryPairingKeyStore()),
  catalog: SessionCatalog(),
  hostName: 'Test Desktop',
  ports: ports,
  uploadOpener: noopUploadOpener,
);

/// A port that was free a moment ago: bind ephemerally, note it, release it.
Future<int> _recentlyFreePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

void main() {
  test('binds a real port on start', () async {
    final server = _server(PairingKeyPair.generate());
    await server.ensureStarted();
    addTearDown(server.dispose);
    expect(server.isRunning, isTrue);
    expect(server.port, greaterThan(0));
  });

  test('ensureStarted is idempotent (same port)', () async {
    final server = _server(PairingKeyPair.generate());
    await server.ensureStarted();
    addTearDown(server.dispose);
    final first = server.port;
    await server.ensureStarted();
    expect(server.port, first);
  });

  test('binds the first ladder port so saved phone URLs survive a restart', () async {
    // The regression: binding port 0 handed out a new port every launch, and
    // every paired phone's stored ws:// URL pointed at the old one.
    final ports = [await _recentlyFreePort(), await _recentlyFreePort()];
    final first = _server(PairingKeyPair.generate(), ports: ports);
    await first.ensureStarted();
    expect(first.port, ports.first);
    await first.dispose();

    // A restart lands on the same port, which is the whole point.
    final second = _server(PairingKeyPair.generate(), ports: ports);
    await second.ensureStarted();
    addTearDown(second.dispose);
    expect(second.port, ports.first);
  });

  test('walks down the ladder when an earlier port is taken', () async {
    final ports = [await _recentlyFreePort(), await _recentlyFreePort()];
    final squatter = await ServerSocket.bind(InternetAddress.anyIPv4, ports[0]);
    addTearDown(squatter.close);

    final server = _server(PairingKeyPair.generate(), ports: ports);
    await server.ensureStarted();
    addTearDown(server.dispose);
    // Still on an agreed port, so a stranded phone's ladder probe finds it.
    expect(server.port, ports[1]);
  });

  test('falls back to an ephemeral port when the whole ladder is taken', () async {
    final ports = [await _recentlyFreePort(), await _recentlyFreePort()];
    final squatters = [
      for (final port in ports)
        await ServerSocket.bind(InternetAddress.anyIPv4, port),
    ];
    addTearDown(() async {
      for (final s in squatters) {
        await s.close();
      }
    });

    final server = _server(PairingKeyPair.generate(), ports: ports);
    await server.ensureStarted();
    addTearDown(server.dispose);
    // Last resort: pairing still works for a fresh scan; only saved URLs are
    // lost, which is exactly what the warning in ensureStarted says.
    expect(server.isRunning, isTrue);
    expect(server.port, isNot(anyOf(ports)));
    expect(server.port, greaterThan(0));
  });

  test('createOffer opens a window and pins the host static key', () async {
    final key = PairingKeyPair.generate();
    final server = _server(key);
    await server.ensureStarted();
    addTearDown(server.dispose);

    final offer = await server.createOffer(ttl: const Duration(minutes: 1));
    expect(offer.hostPublicKeyB64, key.publicKeyB64);
    expect(offer.token, isNotEmpty);
    expect(server.offerWindow.isOpen, isTrue);
    // The offer's token is exactly the open window's one-time code.
    expect(server.offerWindow.consume(offer.token), isTrue);
  });

  test('dispose stops the server', () async {
    final server = _server(PairingKeyPair.generate());
    await server.ensureStarted();
    await server.dispose();
    expect(server.isRunning, isFalse);
  });
}
