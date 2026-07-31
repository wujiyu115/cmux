import 'package:shared_preferences/shared_preferences.dart';

import 'ssh_credential_store.dart' show SecureKeyValueStore;

/// Secret-plane store for pairing: the desktop host's static X25519 identity
/// key and the paired-device book (device tokens hashed at rest + resume
/// secrets). Mirrors the 3-impl shape of [SshCredentialStore]
/// (Secure / SharedPrefs / InMemory) so tests inject the in-memory variant.
abstract class PairingKeyStore {
  /// Base64url of the host static private key; null until first generated.
  Future<String?> loadStaticPrivateKey();
  Future<void> saveStaticPrivateKey(String privateKeyB64);

  /// Opaque JSON blob owned by `DeviceRegistry` (list of paired devices).
  Future<String?> loadDevicesJson();
  Future<void> saveDevicesJson(String json);
}

const _prefix = 'teampilot.pairing.v1';
const _kStaticPrivateKey = '$_prefix.static_private_key';
const _kDevices = '$_prefix.devices';

class SecurePairingKeyStore implements PairingKeyStore {
  const SecurePairingKeyStore(this._store);

  final SecureKeyValueStore _store;

  @override
  Future<String?> loadStaticPrivateKey() => _store.read(_kStaticPrivateKey);

  @override
  Future<void> saveStaticPrivateKey(String privateKeyB64) =>
      _store.write(_kStaticPrivateKey, privateKeyB64);

  @override
  Future<String?> loadDevicesJson() => _store.read(_kDevices);

  @override
  Future<void> saveDevicesJson(String json) => _store.write(_kDevices, json);
}

class SharedPrefsPairingKeyStore implements PairingKeyStore {
  const SharedPrefsPairingKeyStore(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<String?> loadStaticPrivateKey() async =>
      _preferences.getString(_kStaticPrivateKey);

  @override
  Future<void> saveStaticPrivateKey(String privateKeyB64) async {
    await _preferences.setString(_kStaticPrivateKey, privateKeyB64);
  }

  @override
  Future<String?> loadDevicesJson() async => _preferences.getString(_kDevices);

  @override
  Future<void> saveDevicesJson(String json) async {
    await _preferences.setString(_kDevices, json);
  }
}

class InMemoryPairingKeyStore implements PairingKeyStore {
  String? _staticPrivateKey;
  String? _devices;

  @override
  Future<String?> loadStaticPrivateKey() async => _staticPrivateKey;

  @override
  Future<void> saveStaticPrivateKey(String privateKeyB64) async {
    _staticPrivateKey = privateKeyB64;
  }

  @override
  Future<String?> loadDevicesJson() async => _devices;

  @override
  Future<void> saveDevicesJson(String json) async {
    _devices = json;
  }
}
