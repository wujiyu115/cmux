import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/pairing_settings_repository.dart';
import '../services/pairing/device_registry.dart';
import '../services/pairing/lan_pairing_server.dart';
import '../services/pairing/pairing_offer.dart';
import '../utils/logging/logger.dart';

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
    this.error,
  });

  final bool enabled;
  final bool running;
  final int port;
  final PairingOffer? offer;
  final List<String> lanUrls;
  final List<PairedDeviceInfo> devices;
  final String? error;

  PairingHostState copyWith({
    bool? enabled,
    bool? running,
    int? port,
    PairingOffer? offer,
    bool clearOffer = false,
    List<String>? lanUrls,
    List<PairedDeviceInfo>? devices,
    String? error,
    bool clearError = false,
  }) => PairingHostState(
    enabled: enabled ?? this.enabled,
    running: running ?? this.running,
    port: port ?? this.port,
    offer: clearOffer ? null : (offer ?? this.offer),
    lanUrls: lanUrls ?? this.lanUrls,
    devices: devices ?? this.devices,
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
    required LanPairingServer Function() serverFactory,
  }) : _settings = settings,
       _registry = registry,
       _serverFactory = serverFactory,
       super(const PairingHostState());

  final PairingSettingsRepository _settings;
  final DeviceRegistry _registry;
  final LanPairingServer Function() _serverFactory;

  LanPairingServer? _server;

  Future<void> init() async {
    final enabled = await _settings.loadPairingHostEnabled();
    emit(state.copyWith(enabled: enabled));
    if (enabled) await _start();
    await _refreshDevices();
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
      final server = _serverFactory();
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

  @override
  Future<void> close() async {
    await _server?.dispose();
    _server = null;
    return super.close();
  }
}
