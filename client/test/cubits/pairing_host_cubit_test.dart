import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/pairing_host_cubit.dart';
import 'package:teampilot/repositories/pairing_key_store.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/services/pairing/device_registry.dart';
import 'package:teampilot/services/pairing/lan_pairing_server.dart';
import 'package:teampilot/services/pairing/pairing_crypto.dart';
import 'package:teampilot/services/pairing/pairing_offer.dart';
import 'package:teampilot/services/pairing/session_catalog.dart';

/// Fake host server: no real socket, deterministic port/offer.
class _FakeServer extends LanPairingServer {
  _FakeServer()
    : super(
        hostStaticKey: PairingKeyPair.generate(),
        registry: DeviceRegistry(InMemoryPairingKeyStore()),
        catalog: SessionCatalog(),
        hostName: 'Test',
        uploadSink: ({
          required String workspaceId,
          required String cwd,
          required String filename,
          required List<int> bytes,
        }) async => '',
      );

  bool started = false;
  bool disposed = false;

  @override
  bool get isRunning => started && !disposed;

  @override
  int get port => 4321;

  @override
  Future<void> ensureStarted() async {
    started = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<PairingOffer> createOffer({
    Duration ttl = PairingOfferWindow.defaultTtl,
  }) async => const PairingOffer(
    version: 1,
    wsUrls: ['ws://192.168.0.5:4321/pair/ws'],
    token: 'code',
    hostPublicKeyB64: 'pk',
    expiresAtMs: 0,
  );
}

void main() {
  group('PairingHostCubit', () {
    late DeviceRegistry registry;
    late _FakeServer server;

    PairingHostCubit makeCubit(PairingSettingsRepository settings) {
      server = _FakeServer();
      final cubit = PairingHostCubit(
        settings: settings,
        registry: registry,
        serverFactory: () => server,
      );
      addTearDown(cubit.close);
      return cubit;
    }

    setUp(() {
      registry = DeviceRegistry(InMemoryPairingKeyStore());
    });

    test('init with host disabled leaves the server stopped', () async {
      final cubit = makeCubit(InMemoryPairingSettingsRepository());
      await cubit.init();
      expect(cubit.state.enabled, isFalse);
      expect(cubit.state.running, isFalse);
    });

    test('init with host enabled auto-starts and shows an offer', () async {
      final cubit = makeCubit(
        InMemoryPairingSettingsRepository(hostEnabled: true),
      );
      await cubit.init();
      expect(cubit.state.enabled, isTrue);
      expect(cubit.state.running, isTrue);
      expect(cubit.state.port, 4321);
      expect(cubit.state.offer, isNotNull);
      expect(cubit.state.lanUrls, isNotEmpty);
    });

    test('setEnabled(true) starts, setEnabled(false) stops + clears offer',
        () async {
      final settings = InMemoryPairingSettingsRepository();
      final cubit = makeCubit(settings);
      await cubit.init();

      await cubit.setEnabled(true);
      expect(cubit.state.running, isTrue);
      expect(cubit.state.offer, isNotNull);
      expect(server.started, isTrue);
      expect(await settings.loadPairingHostEnabled(), isTrue);

      await cubit.setEnabled(false);
      expect(cubit.state.running, isFalse);
      expect(cubit.state.offer, isNull);
      expect(cubit.state.lanUrls, isEmpty);
      expect(server.disposed, isTrue);
      expect(await settings.loadPairingHostEnabled(), isFalse);
    });

    test('revokeDevice removes it from the device list', () async {
      final device = await registry.register(name: 'Phone');
      final cubit = makeCubit(InMemoryPairingSettingsRepository());
      await cubit.init();
      expect(cubit.state.devices, hasLength(1));

      await cubit.revokeDevice(device.deviceId);
      expect(cubit.state.devices, isEmpty);
    });

    test('init surfaces already-paired devices', () async {
      await registry.register(name: 'Phone');
      await registry.register(name: 'Tablet');
      final cubit = makeCubit(InMemoryPairingSettingsRepository());
      await cubit.init();
      expect(cubit.state.devices, hasLength(2));
    });
  });
}
