import 'dart:convert';

import '../../repositories/pairing_key_store.dart';
import 'pairing_crypto.dart';

/// Public view of a paired device — no secrets. Surfaced in the host page's
/// device list and used for revoke.
class PairedDeviceInfo {
  const PairedDeviceInfo({
    required this.deviceId,
    required this.name,
    required this.pairedAtMs,
  });

  final String deviceId;
  final String name;
  final int pairedAtMs;
}

/// Freshly registered credential handed back to the client exactly once. The
/// host keeps only [PairedDeviceInfo] + the hashed token.
class RegisteredDevice {
  const RegisteredDevice({required this.deviceId, required this.token});
  final String deviceId;
  final String token;
}

class _DeviceRecord {
  _DeviceRecord({
    required this.deviceId,
    required this.tokenHash,
    required this.name,
    required this.pairedAtMs,
  });

  final String deviceId;
  final String tokenHash;
  final String name;
  final int pairedAtMs;

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'tokenHash': tokenHash,
    'name': name,
    'pairedAtMs': pairedAtMs,
  };

  static _DeviceRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['deviceId'];
    final hash = raw['tokenHash'];
    if (id is! String || hash is! String) return null;
    return _DeviceRecord(
      deviceId: id,
      tokenHash: hash,
      name: raw['name'] is String ? raw['name'] as String : id,
      pairedAtMs: raw['pairedAtMs'] is int ? raw['pairedAtMs'] as int : 0,
    );
  }
}

/// The host's book of paired mobile devices. Device tokens are stored **hashed**
/// (sha256) and compared in constant time. Backed by [PairingKeyStore] as an
/// opaque JSON blob; call [load] once before use.
class DeviceRegistry {
  DeviceRegistry(this._store, {int Function()? clock})
    : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final PairingKeyStore _store;
  final int Function() _clock;
  final _devices = <String, _DeviceRecord>{};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final json = await _store.loadDevicesJson();
    if (json != null && json.isNotEmpty) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is List) {
          for (final entry in decoded) {
            final record = _DeviceRecord.fromJson(entry);
            if (record != null) _devices[record.deviceId] = record;
          }
        }
      } on FormatException {
        // Corrupt blob — start clean rather than crash the host.
      }
    }
    _loaded = true;
  }

  Future<RegisteredDevice> register({required String name}) async {
    await load();
    final deviceId = PairingCrypto.randomToken(8);
    final token = PairingCrypto.randomToken(24);
    _devices[deviceId] = _DeviceRecord(
      deviceId: deviceId,
      tokenHash: PairingCrypto.sha256Hex(token),
      name: name.trim().isEmpty ? deviceId : name.trim(),
      pairedAtMs: _clock(),
    );
    await _persist();
    return RegisteredDevice(deviceId: deviceId, token: token);
  }

  /// True when [token] matches the stored hash for [deviceId]. Constant-time.
  Future<bool> validate({
    required String deviceId,
    required String token,
  }) async {
    await load();
    final record = _devices[deviceId];
    if (record == null) return false;
    return PairingCrypto.constantTimeEquals(
      record.tokenHash,
      PairingCrypto.sha256Hex(token),
    );
  }

  Future<void> revoke(String deviceId) async {
    await load();
    if (_devices.remove(deviceId) != null) {
      await _persist();
    }
  }

  Future<List<PairedDeviceInfo>> list() async {
    await load();
    return _devices.values
        .map(
          (r) => PairedDeviceInfo(
            deviceId: r.deviceId,
            name: r.name,
            pairedAtMs: r.pairedAtMs,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _persist() async {
    final list = _devices.values.map((r) => r.toJson()).toList();
    await _store.saveDevicesJson(jsonEncode(list));
  }
}
