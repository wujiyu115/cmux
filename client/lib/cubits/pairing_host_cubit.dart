import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/pairing_settings_repository.dart';
import '../services/pairing/device_registry.dart';
import '../services/pairing/lan_pairing_server.dart';
import '../services/pairing/pairing_offer.dart';
import '../utils/logging/logger.dart';

/// One address the desktop can listen on, as offered in the bind picker.
class PairingInterfaceAddress extends Equatable {
  const PairingInterfaceAddress({required this.name, required this.ip});

  /// OS interface name (`Wi-Fi`, `以太网`, `vEthernet (WSL)`), which is what
  /// tells two same-subnet adapters apart in the picker.
  final String name;
  final String ip;

  @override
  List<Object?> get props => [name, ip];
}

/// Lists this machine's bindable IPv4 addresses. Injected so tests do not touch
/// the real network stack.
typedef PairingInterfaceLister =
    Future<List<PairingInterfaceAddress>> Function();

/// Desktop pairing-host state: whether the LAN server is enabled/running, the
/// current QR offer to display, the LAN URLs to fall back to, and the book of
/// already-paired devices.
class PairingHostState extends Equatable {
  const PairingHostState({
    this.enabled = false,
    this.running = false,
    this.port = 0,
    this.offer,
    this.lanUrls = const [],
    this.devices = const [],
    this.advertisedAddress,
    this.interfaces = const [],
    this.error,
  });

  final bool enabled;
  final bool running;
  final int port;
  final PairingOffer? offer;
  final List<String> lanUrls;
  final List<PairedDeviceInfo> devices;

  /// Address put in the pairing offer, or null to offer every interface.
  final String? advertisedAddress;

  /// Bindable addresses on this machine, for the picker.
  final List<PairingInterfaceAddress> interfaces;
  final String? error;

  PairingHostState copyWith({
    bool? enabled,
    bool? running,
    int? port,
    PairingOffer? offer,
    bool clearOffer = false,
    List<String>? lanUrls,
    List<PairedDeviceInfo>? devices,
    String? advertisedAddress,
    bool clearAdvertisedAddress = false,
    List<PairingInterfaceAddress>? interfaces,
    String? error,
    bool clearError = false,
  }) => PairingHostState(
    enabled: enabled ?? this.enabled,
    running: running ?? this.running,
    port: port ?? this.port,
    offer: clearOffer ? null : (offer ?? this.offer),
    lanUrls: lanUrls ?? this.lanUrls,
    devices: devices ?? this.devices,
    advertisedAddress: clearAdvertisedAddress
        ? null
        : (advertisedAddress ?? this.advertisedAddress),
    interfaces: interfaces ?? this.interfaces,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    enabled,
    running,
    port,
    offer,
    lanUrls,
    devices,
    advertisedAddress,
    interfaces,
    error,
  ];
}

/// Owns the [LanPairingServer] lifecycle behind the config toggle. The server is
/// rebuilt on each enable (a disposed listener cannot re-bind); the shared
/// [DeviceRegistry] outlives it so revoke works while stopped.
class PairingHostCubit extends Cubit<PairingHostState> {
  PairingHostCubit({
    required PairingSettingsRepository settings,
    required DeviceRegistry registry,
    required LanPairingServer Function(String? advertisedAddress) serverFactory,
    PairingInterfaceLister? interfaceLister,
  }) : _settings = settings,
       _registry = registry,
       _serverFactory = serverFactory,
       _interfaceLister = interfaceLister ?? _listLocalIpv4Interfaces,
       super(const PairingHostState());

  final PairingSettingsRepository _settings;
  final DeviceRegistry _registry;
  final LanPairingServer Function(String? advertisedAddress) _serverFactory;
  final PairingInterfaceLister _interfaceLister;

  LanPairingServer? _server;

  Future<void> init() async {
    final enabled = await _settings.loadPairingHostEnabled();
    final advertisedAddress = await _settings.loadPairingHostAddress();
    emit(
      state.copyWith(
        enabled: enabled,
        advertisedAddress: advertisedAddress,
        interfaces: await _interfaceLister(),
      ),
    );
    if (enabled) await _start();
    await _refreshDevices();
  }

  /// Re-reads the machine's addresses (Wi-Fi switch, VPN up/down). Cheap, and
  /// called when the settings page opens so the picker is never stale.
  Future<void> refreshInterfaces() async {
    final interfaces = await _interfaceLister();
    if (isClosed) return;
    emit(state.copyWith(interfaces: interfaces));
  }

  /// Chooses which address the offer advertises (null = every interface).
  ///
  /// Advertise-only on purpose: the listener keeps binding `anyIPv4`, so
  /// switching never drops a connected phone or changes the port — it just
  /// re-issues the offer/QR with a single URL.
  Future<void> setAdvertisedAddress(String? address) async {
    final next = (address == null || address.trim().isEmpty)
        ? null
        : address.trim();
    if (next == state.advertisedAddress) return;
    await _settings.savePairingHostAddress(next);
    emit(
      state.copyWith(
        advertisedAddress: next,
        clearAdvertisedAddress: next == null,
        clearError: true,
      ),
    );
    final server = _server;
    if (server == null) return;
    server.advertisedAddress = next;
    await refreshOffer();
  }

  Future<void> setEnabled(bool value) async {
    if (value == state.enabled && (state.running == value)) return;
    await _settings.savePairingHostEnabled(value);
    emit(state.copyWith(enabled: value, clearError: true));
    if (value) {
      await _start();
    } else {
      await _stop();
    }
  }

  /// Whether a phone is authenticated on the running host right now. False when
  /// the host is off. Read by the Bark dispatcher to avoid pushing an event the
  /// connected phone already got as an `agent.notice` frame.
  bool get hasConnectedPhone => _server?.hasAuthenticatedClient ?? false;

  Future<void> _start() async {
    try {
      final server = _serverFactory(state.advertisedAddress);
      await server.ensureStarted();
      _server = server;
      emit(state.copyWith(running: true, port: server.port, clearError: true));
      await refreshOffer();
    } on Object catch (e) {
      appLogger.d('pairing host start failed: $e');
      emit(state.copyWith(running: false, error: 'Failed to start: $e'));
    }
  }

  Future<void> _stop() async {
    await _server?.dispose();
    _server = null;
    emit(state.copyWith(running: false, clearOffer: true, lanUrls: const []));
  }

  /// Opens a fresh TTL pairing window + QR offer. Call again to rotate the code.
  Future<void> refreshOffer() async {
    final server = _server;
    if (server == null) return;
    try {
      final offer = await server.createOffer();
      emit(state.copyWith(offer: offer, lanUrls: offer.wsUrls));
    } on Object catch (e) {
      appLogger.d('pairing offer failed: $e');
      emit(state.copyWith(error: 'Failed to build offer: $e'));
    }
  }

  Future<void> revokeDevice(String deviceId) async {
    await _registry.revoke(deviceId);
    await _refreshDevices();
  }

  Future<void> _refreshDevices() async {
    final devices = await _registry.list();
    emit(state.copyWith(devices: devices));
  }

  static Future<List<PairingInterfaceAddress>>
  _listLocalIpv4Interfaces() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      return [
        for (final iface in interfaces)
          for (final addr in iface.addresses)
            if (!addr.isLoopback)
              PairingInterfaceAddress(name: iface.name, ip: addr.address),
      ];
    } on Object catch (e) {
      appLogger.d('pairing host cannot list interfaces: $e');
      return const [];
    }
  }

  @override
  Future<void> close() async {
    await _server?.dispose();
    _server = null;
    return super.close();
  }
}
