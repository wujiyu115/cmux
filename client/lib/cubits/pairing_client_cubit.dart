import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/pairing_settings_repository.dart';
import '../services/pairing/local_lan_ip.dart';
import '../services/pairing/pairing_client.dart';
import '../services/pairing/pairing_offer.dart';
import '../services/pairing/pairing_upload_sender.dart';

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

/// Outcome of one host-side request: the value, or the host's own words for why
/// it refused.
///
/// [error] is deliberately the raw host/exception text rather than a localized
/// string. A desktop that predates a feature answers `unknown method:
/// group.create`, which is the single fact identifying a stale desktop — and it
/// used to go only to the connection log, a screen unreachable once connected,
/// leaving the phone showing nothing but "could not create group". Callers pair
/// it with a localized headline; this is the diagnostic tail.
class PairingCallResult<T> {
  const PairingCallResult.ok(T value) : _value = value, error = null;
  const PairingCallResult.failed(this.error) : _value = null;

  final T? _value;
  final String? error;

  /// Non-null exactly when [ok]; callers that checked `ok` may use `value!`.
  T? get value => _value;

  bool get ok => error == null;
}

class PairingClientState extends Equatable {
  const PairingClientState({
    this.phase = PairingClientPhase.idle,
    this.pairedDesktops = const [],
    this.sessions = const [],
    this.workspaces = const [],
    this.groups = const [],
    this.logs = const [],
    this.stageStatuses = idleStages,
    this.pendingOffer,
    this.activeHostName,
    this.activeHostUrl,
    this.activeCatalogId,
    this.activatingKey,
    this.localIp,
    this.notice,
    this.error,
  });

  /// One [PairingStageStatus.idle] per [PairingStage], in enum order.
  static const idleStages = <PairingStageStatus>[
    PairingStageStatus.idle,
    PairingStageStatus.idle,
    PairingStageStatus.idle,
    PairingStageStatus.idle,
  ];

  final PairingClientPhase phase;
  final List<PairedDesktop> pairedDesktops;
  final List<PairingSessionSummary> sessions;

  /// Full workspace tree (all workspaces, persisted sessions + live panes).
  final List<PairingWorkspaceNode> workspaces;

  /// The host's workspace groups, so the list can render folded by group.
  final List<PairingGroup> groups;
  final List<String> logs;

  /// Connect progress indexed by [PairingStage.index] — drives the step rail.
  final List<PairingStageStatus> stageStatuses;

  final PairingOffer? pendingOffer;
  final String? activeHostName;

  /// The LAN URL the active connection actually landed on.
  final String? activeHostUrl;

  final String? activeCatalogId;

  /// [PairingSessionNode.nodeKey] currently being activated (row-level spinner).
  final String? activatingKey;

  /// This phone's own LAN IPv4, or null while unresolved / unavailable.
  final String? localIp;

  /// One-shot toast to surface then clear via [PairingClientCubit.clearNotice].
  final PairingNotice? notice;
  final String? error;

  PairingClientState copyWith({
    PairingClientPhase? phase,
    List<PairedDesktop>? pairedDesktops,
    List<PairingSessionSummary>? sessions,
    List<PairingWorkspaceNode>? workspaces,
    List<PairingGroup>? groups,
    List<String>? logs,
    List<PairingStageStatus>? stageStatuses,
    PairingOffer? pendingOffer,
    bool clearPendingOffer = false,
    String? activeHostName,
    String? activeHostUrl,
    String? activeCatalogId,
    bool clearActiveCatalogId = false,
    String? activatingKey,
    bool clearActivatingKey = false,
    String? localIp,
    PairingNotice? notice,
    bool clearNotice = false,
    String? error,
    bool clearError = false,
  }) => PairingClientState(
    phase: phase ?? this.phase,
    pairedDesktops: pairedDesktops ?? this.pairedDesktops,
    sessions: sessions ?? this.sessions,
    workspaces: workspaces ?? this.workspaces,
    groups: groups ?? this.groups,
    logs: logs ?? this.logs,
    stageStatuses: stageStatuses ?? this.stageStatuses,
    pendingOffer: clearPendingOffer ? null : (pendingOffer ?? this.pendingOffer),
    activeHostName: activeHostName ?? this.activeHostName,
    activeHostUrl: activeHostUrl ?? this.activeHostUrl,
    activeCatalogId: clearActiveCatalogId
        ? null
        : (activeCatalogId ?? this.activeCatalogId),
    activatingKey: clearActivatingKey
        ? null
        : (activatingKey ?? this.activatingKey),
    localIp: localIp ?? this.localIp,
    notice: clearNotice ? null : (notice ?? this.notice),
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    phase,
    pairedDesktops,
    sessions,
    workspaces,
    groups,
    logs,
    stageStatuses,
    pendingOffer,
    activeHostName,
    activeHostUrl,
    activeCatalogId,
    activatingKey,
    localIp,
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
  StreamSubscription<PairingStageEvent>? _stageSub;
  StreamSubscription<void>? _sessionsChangedSub;
  PairingSubscription? _activeSubscription;

  /// Stage the client last reported as in-flight; a thrown connect fails *this*
  /// one, which is what makes the rail's failure attribution correct.
  int? _activeStageIndex;

  PairingSubscription? get activeSubscription => _activeSubscription;
  PairingClient? get client => _client;

  Future<void> loadPairedDesktops() async {
    final desktops = await _settings.loadPairedDesktops();
    emit(state.copyWith(pairedDesktops: desktops));
  }

  /// Resolves this phone's LAN IPv4 for the hosts screen's network strip.
  Future<void> loadNetworkInfo() async {
    final ip = await readPrimaryLanIpv4();
    if (ip == null || isClosed) return;
    emit(state.copyWith(localIp: ip));
  }

  /// A QR / deep link produced a valid offer — show the confirm screen.
  void beginPairing(PairingOffer offer) {
    _activeStageIndex = null;
    emit(
      state.copyWith(
        phase: PairingClientPhase.confirmAwaiting,
        pendingOffer: offer,
        logs: const [],
        stageStatuses: PairingClientState.idleStages,
        clearError: true,
      ),
    );
  }

  /// Confirms the pending offer and runs the full connect + auth flow.
  Future<void> confirmPairing() async {
    final offer = state.pendingOffer;
    if (offer == null) return;
    _activeStageIndex = null;
    emit(
      state.copyWith(
        phase: PairingClientPhase.confirmConnecting,
        stageStatuses: PairingClientState.idleStages,
        clearError: true,
      ),
    );
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
        lastConnectedAt: DateTime.now(),
        lastConnectedUrl: client.connectedUrl,
      );
      await _persistDesktop(desktop);
      await _enterConnected(result.hostName);
    } on Object catch (e) {
      _appendLog('Error: $e');
      _failActiveStage();
      emit(state.copyWith(phase: PairingClientPhase.error, error: '$e'));
      await _disposeClient();
    }
  }

  /// Reconnects to an already-paired desktop using its stored device token.
  Future<void> connectToDesktop(PairedDesktop desktop) async {
    _activeStageIndex = null;
    emit(
      state.copyWith(
        phase: PairingClientPhase.confirmConnecting,
        logs: const [],
        stageStatuses: PairingClientState.idleStages,
        // Reconnects carry no offer, so the confirm card would otherwise have
        // no host to name.
        activeHostName: desktop.name,
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
      await _persistDesktop(
        desktop.copyWith(
          lastConnectedAt: DateTime.now(),
          lastConnectedUrl: client.connectedUrl,
        ),
      );
    } on Object catch (e) {
      _appendLog('Error: $e');
      _failActiveStage();
      emit(state.copyWith(phase: PairingClientPhase.error, error: '$e'));
      await _disposeClient();
    }
  }

  Future<void> _enterConnected(String hostName) async {
    // The workspace fetch is the rail's last step, and it lives here rather than
    // in the client — so this stage is emitted by the cubit.
    _setStage(PairingStage.loadWorkspaces, PairingStageStatus.active);
    final listing = await _client!.listWorkspaces();
    _setStage(PairingStage.loadWorkspaces, PairingStageStatus.done);
    emit(
      state.copyWith(
        phase: PairingClientPhase.connected,
        activeHostName: hostName,
        activeHostUrl: _client?.connectedUrl,
        workspaces: listing.workspaces,
        groups: listing.groups,
        clearPendingOffer: true,
      ),
    );
  }

  void _onStageEvent(PairingStageEvent event) =>
      _setStage(event.stage, event.status);

  void _setStage(PairingStage stage, PairingStageStatus status) {
    if (isClosed) return;
    if (status == PairingStageStatus.active) _activeStageIndex = stage.index;
    final next = [...state.stageStatuses];
    next[stage.index] = status;
    emit(state.copyWith(stageStatuses: next));
  }

  void _failActiveStage() {
    final index = _activeStageIndex;
    if (index == null || isClosed) return;
    final next = [...state.stageStatuses];
    next[index] = PairingStageStatus.fail;
    emit(state.copyWith(stageStatuses: next));
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
      final listing = await client.listWorkspaces();
      emit(
        state.copyWith(
          workspaces: listing.workspaces,
          groups: listing.groups,
        ),
      );
    } on Object catch (e) {
      _appendLog('Refresh failed: $e');
    }
  }

  /// Lists directories on the desktop for the create-workspace folder picker.
  /// Carries the host's refusal reason rather than a bare null so the picker can
  /// say *why* instead of showing an empty folder.
  Future<PairingCallResult<PairingDirListing>> browseDir([String? path]) async {
    final client = _client;
    if (client == null) {
      return const PairingCallResult<PairingDirListing>.failed('not connected');
    }
    try {
      return PairingCallResult.ok(await client.browseDir(path));
    } on Object catch (e) {
      _appendLog('Browse failed: $e');
      return PairingCallResult.failed('$e');
    }
  }

  /// Asks the desktop to create a workspace over [folderPath], then refreshes
  /// the tree so the new workspace appears. Carries the new id, or the host's
  /// reason for refusing.
  Future<PairingCallResult<String>> createWorkspace({
    required String folderPath,
    String? title,
    String? groupId,
  }) async {
    final client = _client;
    if (client == null) {
      return const PairingCallResult<String>.failed('not connected');
    }
    try {
      final id = await client.createWorkspace(
        folderPath: folderPath,
        title: title,
        groupId: groupId,
      );
      await refreshWorkspaces();
      return PairingCallResult.ok(id);
    } on Object catch (e) {
      _appendLog('Create workspace failed: $e');
      return PairingCallResult.failed('$e');
    }
  }

  /// Asks the desktop to create a workspace group, then refreshes so it appears
  /// in the group index. Carries the new id, or the host's reason for refusing.
  Future<PairingCallResult<String>> createGroup(String name) async {
    final client = _client;
    if (client == null) {
      return const PairingCallResult<String>.failed('not connected');
    }
    try {
      final id = await client.createGroup(name);
      await refreshWorkspaces();
      return PairingCallResult.ok(id);
    } on Object catch (e) {
      _appendLog('Create group failed: $e');
      return PairingCallResult.failed('$e');
    }
  }

  /// Opens [node]'s live mirror, asking the host to open a terminal first when
  /// the pane is no longer alive. On failure clears the spinner and emits an
  /// error without leaving the connected screen.
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

  /// Ships [bytes] to the host, which writes them into the mirrored pane's
  /// working directory and returns the absolute path it used.
  Future<String> uploadImage({
    required String filename,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) {
    final sub = _activeSubscription;
    final client = _client;
    if (sub == null || client == null) {
      throw const PairingUploadException('no_target');
    }
    return client.uploadFile(
      sub: sub.sub,
      filename: filename,
      bytes: bytes,
      onProgress: onProgress,
    );
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
    _stageSub = client.stages.listen(_onStageEvent);
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

  /// Puts back a desktop the user just removed (undo toast on the hosts screen).
  Future<void> restoreDesktop(PairedDesktop desktop) async {
    if (state.pairedDesktops.any((d) => d.id == desktop.id)) return;
    final updated = [...state.pairedDesktops, desktop];
    await _settings.savePairedDesktops(updated);
    emit(state.copyWith(pairedDesktops: updated));
  }

  void _disposeClientSync() {
    _logSub?.cancel();
    _logSub = null;
    _stageSub?.cancel();
    _stageSub = null;
    _sessionsChangedSub?.cancel();
    _sessionsChangedSub = null;
    final client = _client;
    _client = null;
    if (client != null) unawaited(client.close());
  }

  Future<void> _disposeClient() async {
    _logSub?.cancel();
    _logSub = null;
    _stageSub?.cancel();
    _stageSub = null;
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
