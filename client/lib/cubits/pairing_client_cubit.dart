import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/pairing_settings_repository.dart';
import '../services/pairing/pairing_client.dart';
import '../services/pairing/pairing_offer.dart';

/// Client-side pairing flow, mirroring orca's screens:
/// idle → confirmAwaiting → confirmConnecting → connected → mirroring, with a
/// dedicated error phase (hard ~25s timeout on connect gives an actionable
/// failure instead of an infinite spinner).
enum PairingClientPhase {
  idle,
  confirmAwaiting,
  confirmConnecting,
  connected,
  mirroring,
  error,
}

/// A one-shot, localizable toast the UI should surface then clear. Kept as an
/// enum so the cubit stays free of display strings (mapped to l10n at render).
enum PairingNotice { activateFailed, fallbackOpenedTerminal }

class PairingClientState extends Equatable {
  const PairingClientState({
    this.phase = PairingClientPhase.idle,
    this.pairedDesktops = const [],
    this.sessions = const [],
    this.workspaces = const [],
    this.logs = const [],
    this.pendingOffer,
    this.activeHostName,
    this.activeCatalogId,
    this.activatingKey,
    this.notice,
    this.error,
  });

  final PairingClientPhase phase;
  final List<PairedDesktop> pairedDesktops;
  final List<PairingSessionSummary> sessions;

  /// Full workspace tree (all workspaces, persisted sessions + live panes).
  final List<PairingWorkspaceNode> workspaces;
  final List<String> logs;
  final PairingOffer? pendingOffer;
  final String? activeHostName;
  final String? activeCatalogId;

  /// [PairingSessionNode.nodeKey] currently being activated (row-level spinner).
  final String? activatingKey;

  /// One-shot toast to surface then clear via [PairingClientCubit.clearNotice].
  final PairingNotice? notice;
  final String? error;

  PairingClientState copyWith({
    PairingClientPhase? phase,
    List<PairedDesktop>? pairedDesktops,
    List<PairingSessionSummary>? sessions,
    List<PairingWorkspaceNode>? workspaces,
    List<String>? logs,
    PairingOffer? pendingOffer,
    bool clearPendingOffer = false,
    String? activeHostName,
    String? activeCatalogId,
    bool clearActiveCatalogId = false,
    String? activatingKey,
    bool clearActivatingKey = false,
    PairingNotice? notice,
    bool clearNotice = false,
    String? error,
    bool clearError = false,
  }) => PairingClientState(
    phase: phase ?? this.phase,
    pairedDesktops: pairedDesktops ?? this.pairedDesktops,
    sessions: sessions ?? this.sessions,
    workspaces: workspaces ?? this.workspaces,
    logs: logs ?? this.logs,
    pendingOffer: clearPendingOffer ? null : (pendingOffer ?? this.pendingOffer),
    activeHostName: activeHostName ?? this.activeHostName,
    activeCatalogId: clearActiveCatalogId
        ? null
        : (activeCatalogId ?? this.activeCatalogId),
    activatingKey: clearActivatingKey
        ? null
        : (activatingKey ?? this.activatingKey),
    notice: clearNotice ? null : (notice ?? this.notice),
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    phase,
    pairedDesktops,
    sessions,
    workspaces,
    logs,
    pendingOffer,
    activeHostName,
    activeCatalogId,
    activatingKey,
    notice,
    error,
  ];
}

/// Drives [PairingClient] and persists paired desktops. UI reads [state] and,
/// for the live mirror, [activeSubscription] + [client] input helpers.
class PairingClientCubit extends Cubit<PairingClientState> {
  PairingClientCubit({
    required PairingSettingsRepository settings,
    PairingClient Function()? clientFactory,
  }) : _settings = settings,
       _clientFactory = clientFactory ?? PairingClient.new,
       super(const PairingClientState());

  final PairingSettingsRepository _settings;
  final PairingClient Function() _clientFactory;

  static const connectTimeout = Duration(seconds: 25);

  PairingClient? _client;
  StreamSubscription<String>? _logSub;
  StreamSubscription<void>? _sessionsChangedSub;
  PairingSubscription? _activeSubscription;

  PairingSubscription? get activeSubscription => _activeSubscription;
  PairingClient? get client => _client;

  Future<void> loadPairedDesktops() async {
    final desktops = await _settings.loadPairedDesktops();
    emit(state.copyWith(pairedDesktops: desktops));
  }

  /// A QR / deep link produced a valid offer — show the confirm screen.
  void beginPairing(PairingOffer offer) {
    emit(
      state.copyWith(
        phase: PairingClientPhase.confirmAwaiting,
        pendingOffer: offer,
        logs: const [],
        clearError: true,
      ),
    );
  }

  /// Confirms the pending offer and runs the full connect + auth flow.
  Future<void> confirmPairing() async {
    final offer = state.pendingOffer;
    if (offer == null) return;
    emit(state.copyWith(phase: PairingClientPhase.confirmConnecting));
    final client = _spawnClient();
    try {
      final result = await client
          .connect(
            wsUrls: offer.wsUrls,
            token: offer.token,
            hostPublicKeyB64: offer.hostPublicKeyB64,
          )
          .timeout(connectTimeout);
      final desktop = PairedDesktop(
        id: result.deviceId,
        name: result.hostName,
        wsUrls: offer.wsUrls,
        hostPublicKeyB64: offer.hostPublicKeyB64,
        deviceToken: result.deviceToken ?? '',
      );
      await _persistDesktop(desktop);
      await _enterConnected(result.hostName);
    } on Object catch (e) {
      _appendLog('Error: $e');
      emit(state.copyWith(phase: PairingClientPhase.error, error: '$e'));
      await _disposeClient();
    }
  }

  /// Reconnects to an already-paired desktop using its stored device token.
  Future<void> connectToDesktop(PairedDesktop desktop) async {
    emit(
      state.copyWith(
        phase: PairingClientPhase.confirmConnecting,
        logs: const [],
        clearError: true,
      ),
    );
    final client = _spawnClient();
    try {
      final result = await client
          .connect(
            wsUrls: desktop.wsUrls,
            token: desktop.deviceToken,
            hostPublicKeyB64: desktop.hostPublicKeyB64,
            deviceId: desktop.id,
          )
          .timeout(connectTimeout);
      await _enterConnected(result.hostName);
    } on Object catch (e) {
      _appendLog('Error: $e');
      emit(state.copyWith(phase: PairingClientPhase.error, error: '$e'));
      await _disposeClient();
    }
  }

  Future<void> _enterConnected(String hostName) async {
    final workspaces = await _client!.listWorkspaces();
    emit(
      state.copyWith(
        phase: PairingClientPhase.connected,
        activeHostName: hostName,
        workspaces: workspaces,
        clearPendingOffer: true,
      ),
    );
  }

  Future<void> refreshSessions() async {
    final client = _client;
    if (client == null) return;
    final sessions = await client.listSessions();
    emit(state.copyWith(sessions: sessions));
  }

  /// Re-fetches the full workspace tree (pull-to-refresh / `session.changed`).
  Future<void> refreshWorkspaces() async {
    final client = _client;
    if (client == null) return;
    try {
      final workspaces = await client.listWorkspaces();
      emit(state.copyWith(workspaces: workspaces));
    } on Object catch (e) {
      _appendLog('Refresh failed: $e');
    }
  }

  /// Activates [node] if dormant, then opens its live mirror. Live nodes go
  /// straight to [openSession]. On failure clears the spinner and emits an error
  /// without leaving the connected screen.
  Future<void> activateAndOpen(PairingSessionNode node) async {
    final client = _client;
    if (client == null) return;
    final live = node.catalogId;
    if (node.live && live != null && live.isNotEmpty) {
      await openSession(live);
      return;
    }
    emit(state.copyWith(activatingKey: node.nodeKey, clearError: true));
    try {
      final result = await client.activateSession(
        workspaceId: node.workspaceId,
        kind: node.kind,
        sessionId: node.sessionId,
        memberId: node.memberId,
        paneId: node.paneId,
      );
      emit(
        state.copyWith(
          clearActivatingKey: true,
          notice: result.fallback
              ? PairingNotice.fallbackOpenedTerminal
              : null,
        ),
      );
      await openSession(result.catalogId);
    } on Object catch (e) {
      _appendLog('Activate failed: $e');
      emit(
        state.copyWith(
          clearActivatingKey: true,
          notice: PairingNotice.activateFailed,
        ),
      );
    }
  }

  /// Clears the one-shot [PairingClientState.notice] after the UI shows it.
  void clearNotice() {
    if (state.notice != null) emit(state.copyWith(clearNotice: true));
  }

  /// Opens a live mirror of [catalogId].
  Future<void> openSession(String catalogId) async {
    final client = _client;
    if (client == null) return;
    _activeSubscription = await client.subscribe(catalogId);
    emit(
      state.copyWith(
        phase: PairingClientPhase.mirroring,
        activeCatalogId: catalogId,
      ),
    );
  }

  void leaveMirror() {
    final sub = _activeSubscription;
    if (sub != null) _client?.unsubscribe(sub.sub);
    _activeSubscription = null;
    emit(
      state.copyWith(
        phase: PairingClientPhase.connected,
        clearActiveCatalogId: true,
      ),
    );
  }

  void sendInput(List<int> data) {
    final sub = _activeSubscription;
    if (sub != null) {
      _client?.sendInput(sub.sub, Uint8List.fromList(data));
    }
  }

  void sendResize(int cols, int rows) {
    final sub = _activeSubscription;
    if (sub != null) _client?.sendResize(sub.sub, cols, rows);
  }

  /// Cancels pairing / disconnects and returns to the host list.
  Future<void> cancel() async {
    await _disposeClient();
    _activeSubscription = null;
    emit(
      state.copyWith(
        phase: PairingClientPhase.idle,
        clearPendingOffer: true,
        clearActiveCatalogId: true,
        clearError: true,
      ),
    );
  }

  PairingClient _spawnClient() {
    _disposeClientSync();
    final client = _clientFactory();
    _client = client;
    _logSub = client.log.listen(_appendLog);
    _sessionsChangedSub = client.sessionsChanged.listen(
      (_) => unawaited(refreshWorkspaces()),
    );
    return client;
  }

  void _appendLog(String message) {
    emit(state.copyWith(logs: [...state.logs, message]));
  }

  Future<void> _persistDesktop(PairedDesktop desktop) async {
    final others = state.pairedDesktops
        .where((d) => d.id != desktop.id)
        .toList();
    final updated = [...others, desktop];
    await _settings.savePairedDesktops(updated);
    emit(state.copyWith(pairedDesktops: updated));
  }

  Future<void> removeDesktop(String id) async {
    final updated = state.pairedDesktops.where((d) => d.id != id).toList();
    await _settings.savePairedDesktops(updated);
    emit(state.copyWith(pairedDesktops: updated));
  }

  void _disposeClientSync() {
    _logSub?.cancel();
    _logSub = null;
    _sessionsChangedSub?.cancel();
    _sessionsChangedSub = null;
    final client = _client;
    _client = null;
    if (client != null) unawaited(client.close());
  }

  Future<void> _disposeClient() async {
    _logSub?.cancel();
    _logSub = null;
    _sessionsChangedSub?.cancel();
    _sessionsChangedSub = null;
    final client = _client;
    _client = null;
    if (client != null) await client.close();
  }

  @override
  Future<void> close() async {
    await _disposeClient();
    return super.close();
  }
}
