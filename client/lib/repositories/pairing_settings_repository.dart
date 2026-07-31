import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A desktop the mobile client has paired with, pinned locally so future
/// connects skip the QR step: the host static public key (MITM pin), the LAN
/// URLs last seen, and the device credential to re-auth with.
class PairedDesktop {
  const PairedDesktop({
    required this.id,
    required this.name,
    required this.wsUrls,
    required this.hostPublicKeyB64,
    required this.deviceToken,
    this.resumeSecret,
    this.lastConnectedAt,
  });

  final String id;
  final String name;
  final List<String> wsUrls;
  final String hostPublicKeyB64;
  final String deviceToken;
  final String? resumeSecret;

  /// Last successful connect, stamped locally (the host reports nothing here).
  /// Null for desktops paired before this field existed.
  final DateTime? lastConnectedAt;

  PairedDesktop copyWith({
    String? name,
    List<String>? wsUrls,
    String? resumeSecret,
    DateTime? lastConnectedAt,
  }) => PairedDesktop(
    id: id,
    name: name ?? this.name,
    wsUrls: wsUrls ?? this.wsUrls,
    hostPublicKeyB64: hostPublicKeyB64,
    deviceToken: deviceToken,
    resumeSecret: resumeSecret ?? this.resumeSecret,
    lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'wsUrls': wsUrls,
    'pk': hostPublicKeyB64,
    'deviceToken': deviceToken,
    if (resumeSecret != null) 'resume': resumeSecret,
    if (lastConnectedAt != null)
      'lastConnectedAt': lastConnectedAt!.millisecondsSinceEpoch,
  };

  static PairedDesktop? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final pk = raw['pk'];
    final token = raw['deviceToken'];
    if (id is! String || pk is! String || token is! String) return null;
    return PairedDesktop(
      id: id,
      name: raw['name'] is String ? raw['name'] as String : id,
      wsUrls: (raw['wsUrls'] as List?)?.whereType<String>().toList() ?? const [],
      hostPublicKeyB64: pk,
      deviceToken: token,
      resumeSecret: raw['resume'] is String ? raw['resume'] as String : null,
      lastConnectedAt: _readTimestamp(raw['lastConnectedAt']),
    );
  }

  /// Tolerant read: epoch millis (what we write), an ISO string (hand-edited
  /// blobs), missing key (pre-field pairings), or junk → null.
  static DateTime? _readTimestamp(Object? raw) {
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}

/// Control-plane settings for pairing: the host on/off switch (desktop) and the
/// paired-desktop list (mobile). JSON blob under one versioned key, matching
/// [AppSettingsRepository]'s shape.
abstract class PairingSettingsRepository {
  Future<bool> loadPairingHostEnabled();
  Future<void> savePairingHostEnabled(bool value);

  Future<List<PairedDesktop>> loadPairedDesktops();
  Future<void> savePairedDesktops(List<PairedDesktop> desktops);
}

class SharedPrefsPairingSettingsRepository
    implements PairingSettingsRepository {
  const SharedPrefsPairingSettingsRepository(this._preferences);

  static const storageKey = 'teampilot.pairing_settings.v1';
  static const _hostEnabledKey = 'hostEnabled';
  static const _pairedDesktopsKey = 'pairedDesktops';

  final SharedPreferences _preferences;

  @override
  Future<bool> loadPairingHostEnabled() async =>
      _readMap()[_hostEnabledKey] == true;

  @override
  Future<void> savePairingHostEnabled(bool value) async {
    final current = _readMap();
    current[_hostEnabledKey] = value;
    await _writeMap(current);
  }

  @override
  Future<List<PairedDesktop>> loadPairedDesktops() async {
    final raw = _readMap()[_pairedDesktopsKey];
    if (raw is! List) return const [];
    return raw
        .map(PairedDesktop.fromJson)
        .whereType<PairedDesktop>()
        .toList(growable: false);
  }

  @override
  Future<void> savePairedDesktops(List<PairedDesktop> desktops) async {
    final current = _readMap();
    current[_pairedDesktopsKey] = desktops.map((d) => d.toJson()).toList();
    await _writeMap(current);
  }

  Future<void> _writeMap(Map<String, Object?> current) async {
    if (current.isEmpty) {
      await _preferences.remove(storageKey);
    } else {
      await _preferences.setString(storageKey, jsonEncode(current));
    }
  }

  Map<String, Object?> _readMap() {
    final stored = _preferences.getString(storageKey);
    if (stored == null || stored.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return <String, Object?>{};
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      return <String, Object?>{};
    }
  }
}

class InMemoryPairingSettingsRepository implements PairingSettingsRepository {
  InMemoryPairingSettingsRepository({
    bool hostEnabled = false,
    List<PairedDesktop>? pairedDesktops,
  }) : _hostEnabled = hostEnabled,
       _pairedDesktops = pairedDesktops ?? [];

  bool _hostEnabled;
  List<PairedDesktop> _pairedDesktops;

  @override
  Future<bool> loadPairingHostEnabled() async => _hostEnabled;

  @override
  Future<void> savePairingHostEnabled(bool value) async {
    _hostEnabled = value;
  }

  @override
  Future<List<PairedDesktop>> loadPairedDesktops() async =>
      List.unmodifiable(_pairedDesktops);

  @override
  Future<void> savePairedDesktops(List<PairedDesktop> desktops) async {
    _pairedDesktops = List.of(desktops);
  }
}
