import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/pairing_key_store.dart';
import 'package:teampilot/services/pairing/device_registry.dart';
import 'package:teampilot/services/pairing/pairing_crypto.dart';

void main() {
  group('DeviceRegistry', () {
    late InMemoryPairingKeyStore store;
    late DeviceRegistry registry;

    setUp(() {
      store = InMemoryPairingKeyStore();
      registry = DeviceRegistry(store, clock: () => 4242);
    });

    test('register then validate the issued token', () async {
      final device = await registry.register(name: 'Pixel');
      expect(device.deviceId, isNotEmpty);
      expect(device.token, isNotEmpty);
      expect(
        await registry.validate(deviceId: device.deviceId, token: device.token),
        isTrue,
      );
    });

    test('validate rejects a wrong token and an unknown device', () async {
      final device = await registry.register(name: 'Pixel');
      expect(
        await registry.validate(deviceId: device.deviceId, token: 'nope'),
        isFalse,
      );
      expect(
        await registry.validate(deviceId: 'ghost', token: device.token),
        isFalse,
      );
    });

    test('token is persisted hashed, never in the clear', () async {
      final device = await registry.register(name: 'Pixel');
      final json = await store.loadDevicesJson();
      expect(json, isNotNull);
      expect(json, isNot(contains(device.token)));
      expect(json, contains(PairingCrypto.sha256Hex(device.token)));
    });

    test('revoke removes the device so it no longer validates', () async {
      final device = await registry.register(name: 'Pixel');
      await registry.revoke(device.deviceId);
      expect(
        await registry.validate(deviceId: device.deviceId, token: device.token),
        isFalse,
      );
      expect(await registry.list(), isEmpty);
    });

    test('list reflects registered devices with metadata', () async {
      await registry.register(name: 'Pixel');
      await registry.register(name: 'iPhone');
      final list = await registry.list();
      expect(list.map((d) => d.name), containsAll(['Pixel', 'iPhone']));
      expect(list.every((d) => d.pairedAtMs == 4242), isTrue);
    });

    test('devices survive a reload from the same store', () async {
      final device = await registry.register(name: 'Pixel');
      final reloaded = DeviceRegistry(store);
      await reloaded.load();
      expect(
        await reloaded.validate(deviceId: device.deviceId, token: device.token),
        isTrue,
      );
    });

    test('blank name falls back to the device id', () async {
      final device = await registry.register(name: '   ');
      final info = (await registry.list()).single;
      expect(info.name, device.deviceId);
    });
  });
}
