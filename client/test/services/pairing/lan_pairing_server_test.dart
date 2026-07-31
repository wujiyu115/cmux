import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/pairing_key_store.dart';
import 'package:teampilot/services/pairing/device_registry.dart';
import 'package:teampilot/services/pairing/lan_pairing_server.dart';
import 'package:teampilot/services/pairing/pairing_crypto.dart';
import 'package:teampilot/services/pairing/session_catalog.dart';

// NOTE: TestWidgetsFlutterBinding blocks real outbound HTTP (HttpClient returns
// 400 with no socket), so these tests exercise the server's lifecycle + offer
// wiring rather than a real request round-trip. The health/WS request path is
// covered end-to-end on device, per the plan's manual verification.

LanPairingServer _server(PairingKeyPair key) => LanPairingServer(
  hostStaticKey: key,
  registry: DeviceRegistry(InMemoryPairingKeyStore()),
  catalog: SessionCatalog(),
  hostName: 'Test Desktop',
);

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
