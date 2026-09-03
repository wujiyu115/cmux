import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/pairing_settings_repository.dart';
import '../services/pairing/agent_notice_message.dart';
import '../services/pairing/local_lan_ip.dart';
import '../services/pairing/pairing_client.dart';
import '../services/pairing/pairing_git_view.dart';
import '../services/pairing/pairing_offer.dart';
import '../services/pairing/pairing_upload_sender.dart';
import '../services/pairing/upload_source.dart';

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
enum PairingNotice {
  activateFailed,
  fallbackOpenedTerminal,
  connectionLost,
  reconnected,
}

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
    this.targets = const [],
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
    this.reconnecting = false,
    this.connectGeneration = 0,
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

  /// The machines the host can create a workspace on. Empty when the desktop
  /// predates machine selection, which is the cue to hide the picker entirely.
  final List<PairingTarget> targets;
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

  /// The connection dropped on its own and a retry is pending or in flight.
  ///
  /// Deliberately *not* a [PairingClientPhase]: a WiFi blip must not throw the
  /// user out of the mirror. [phase] stays put — the mirror keeps showing the
  /// last frame the desktop actually sent — and only this flag changes.
  final bool reconnecting;

  /// Bumped on every successful reconnect. The mirror's widget key includes it,
  /// so a reconnect remounts the page onto the *new* subscription instead of
  /// leaving it bound to the dead one (the catalogId alone is unchanged).
  final int connectGeneration;

  PairingClientState copyWith({
    PairingClientPhase? phase,
    List<PairedDesktop>? pairedDesktops,
    List<PairingSessionSummary>? sessions,
    List<PairingWorkspaceNode>? workspaces,
    List<PairingGroup>? groups,
    List<PairingTarget>? targets,
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
    bool? reconnecting,
    int? connectGeneration,
  }) => PairingClientState(
    phase: phase ?? this.phase,
    pairedDesktops: pairedDesktops ?? this.pairedDesktops,
    sessions: sessions ?? this.sessions,
    workspaces: workspaces ?? this.workspaces,
    groups: groups ?? this.groups,
    targets: targets ?? this.targets,
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
    reconnecting: reconnecting ?? this.reconnecting,
    connectGeneration: connectGeneration ?? this.connectGeneration,
  );

  @override
  List<Object?> get props => [
    phase,
    pairedDesktops,
    sessions,
    workspaces,
    groups,
    targets,
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
    reconnecting,
    connectGeneration,
  ];

  /// Title of the mirrored pane as the workspace tree knows it — the desktop's
  /// tab label (renames included), not whatever OSC title the running program
  /// last set. Null while the tree does not know the active pane yet.
  String? get mirroredPaneTitle {
    final catalogId = activeCatalogId;
    if (catalogId == null) return null;
    for (final ws in workspaces) {
      for (final pane in ws.panes) {
        if (pane.live && pane.catalogId == catalogId) {
          return pane.title.isEmpty ? ws.title : pane.title;
        }
      }
    }
    return null;
  }
}

/// Drives [PairingClient] and persists paired desktops. UI reads [state] and,
/// for the live mirror, [activeSubscription] + [client] input helpers.
class PairingClientCubit extends Cubit<PairingClientState> {
  PairingClientCubit({
    required PairingSettingsRepository settings,
    PairingClient Function()? clientFactory,
    void Function(PairingAgentNotice notice)? onAgentNotice,
  }) : _settings = settings,
       _clientFactory = clientFactory ?? PairingClient.new,
       _onAgentNotice = onAgentNotice ?? ((_) {}),
       super(const PairingClientState());

  final PairingSettingsRepository _settings;
  final PairingClient Function() _clientFactory;

  /// Sink for host-pushed agent notices. Kept as a callback so the cubit never
  /// touches display strings — same rationale as [PairingNotice].
  final void Function(PairingAgentNotice notice) _onAgentNotice;

  static const connectTimeout = Duration(seconds: 25);

  /// Retry delays after a dropped connection, then [reconnectMaxBackoff] forever.
  /// Doubling rather than a fixed interval so a desktop that is genuinely off
  /// (asleep, moved network) is not probed once a second all afternoon.
  static const reconnectFirstBackoff = Duration(seconds: 1);
  static const reconnectMaxBackoff = Duration(seconds: 30);

  PairingClient? _client;
  StreamSubscription<String>? _logSub;
  StreamSubscription<PairingStageEvent>? _stageSub;
  StreamSubscription<void>? _sessionsChangedSub;
  StreamSubscription<PairingAgentNotice>? _agentNoticeSub;
  StreamSubscription<void>? _disconnectedSub;
  PairingSubscription? _activeSubscription;

  /// The desktop to dial on a retry, and the mirror to restore once back. Both
  /// survive the client being thrown away and rebuilt.
  PairedDesktop? _lastDesktop;
  String? _resumeCatalogId;

  /// The user wants to be connected. False after [cancel], which is what stops
  /// the retry loop — a dropped socket alone never ends it.
  bool _wantsConnection = false;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  int _generation = 0;

  /// A resume probe is awaiting its pong. Guards against a second resume (a
  /// quick background-foreground flip) starting a second probe — or worse,
  /// falling through to the immediate-reconnect branch on the connection the
  /// first probe is still validating.
  bool _resumeProbeInFlight = false;

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
      _lastDesktop = desktop;
      _wantsConnection = true;
      await _enterConnected(result.hostName);
    } on Object catch (e) {
      _appendLog('Error: $e');
      _failActiveStage();
      // Reaching the error screen means the user has to act, so no silent retry
      // should be left ticking behind it.
      _stopReconnecting();
      emit(
        state.copyWith(
          phase: PairingClientPhase.error,
          error: '$e',
          reconnecting: false,
        ),
      );
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
      _lastDesktop = desktop;
      _wantsConnection = true;
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
      // Reaching the error screen means the user has to act, so no silent retry
      // should be left ticking behind it.
      _stopReconnecting();
      emit(
        state.copyWith(
          phase: PairingClientPhase.error,
          error: '$e',
          reconnecting: false,
        ),
      );
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
        targets: listing.targets,
        clearPendingOffer: true,
      ),
    );
  }

  // --- Reconnect ------------------------------------------------------------

  /// An established connection died on its own. Keeps the current screen (the
  /// mirror stays on its last frame) and starts retrying.
  void _onDisconnected() {
    if (isClosed || !_wantsConnection || state.reconnecting) return;
    // The old subscription is dead; drop it so input/upload stop pretending.
    _resumeCatalogId = state.activeCatalogId;
    _activeSubscription = null;
    _appendLog('Connection lost — reconnecting…');
    emit(
      state.copyWith(
        reconnecting: true,
        notice: PairingNotice.connectionLost,
      ),
    );
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final seconds =
        reconnectFirstBackoff.inSeconds * (1 << _reconnectAttempt.clamp(0, 5));
    final delay = Duration(
      seconds: seconds.clamp(
        reconnectFirstBackoff.inSeconds,
        reconnectMaxBackoff.inSeconds,
      ),
    );
    _reconnectTimer = Timer(delay, () => unawaited(_reconnectNow()));
  }

  /// Retries immediately, resetting the backoff. Called when the app returns
  /// to the foreground: the socket often died while the OS froze the process,
  /// but not always — so when a connection is still held, one application-layer
  /// probe ([_probeOnResume]) decides between keeping it and rebuilding it.
  void onAppResumed() {
    if (isClosed || !_wantsConnection) return;
    final client = _client;
    if (!state.reconnecting && client != null) {
      final established = state.phase == PairingClientPhase.connected ||
          state.phase == PairingClientPhase.mirroring;
      // Mid-handshake (the confirm screens): leave the in-flight connect alone
      // — a probe now would be dropped by the half-open channel and read as
      // death, aborting a connect that was about to succeed.
      if (!established) return;
      if (!_resumeProbeInFlight) unawaited(_probeOnResume(client));
      return;
    }
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    if (!state.reconnecting) {
      emit(state.copyWith(reconnecting: true));
    }
    unawaited(_reconnectNow());
  }

  /// One [PairingClient.ping] settles whether the connection survived the
  /// suspend: an answer keeps it (and the mirror) exactly as it was, silence
  /// means the socket died without a FIN ever reaching the frozen event loop —
  /// so recovery starts here and now instead of on a backoff timer the user
  /// cannot see.
  Future<void> _probeOnResume(PairingClient client) async {
    _resumeProbeInFlight = true;
    // Flagged for the probe's duration: it makes _onDisconnected's guard
    // swallow a death event that flushes mid-probe, so that event cannot stack
    // a second recovery on the one this probe starts itself.
    emit(state.copyWith(reconnecting: true));
    bool alive;
    try {
      alive = await client.ping();
    } finally {
      _resumeProbeInFlight = false;
    }
    if (isClosed || !_wantsConnection) return;
    if (alive) {
      _appendLog('Connection alive after resume');
      emit(state.copyWith(reconnecting: false));
      return;
    }
    _appendLog('Connection lost after resume — reconnecting…');
    // The socket's late onDone is suppressed (see above), so the mirror state
    // must be staged here exactly as _onDisconnected would have.
    _resumeCatalogId = state.activeCatalogId;
    _activeSubscription = null;
    emit(
      state.copyWith(
        reconnecting: true,
        notice: PairingNotice.connectionLost,
      ),
    );
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    unawaited(_reconnectNow());
  }

  Future<void> _reconnectNow() async {
    final desktop = _lastDesktop;
    if (isClosed || !_wantsConnection || desktop == null) return;
    _reconnectAttempt++;
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
      if (isClosed || !_wantsConnection) return;
      final listing = await client.listWorkspaces();
      if (isClosed || !_wantsConnection) return;
      _reconnectAttempt = 0;
      _generation++;
      _appendLog('Reconnected to ${result.hostName}');
      emit(
        state.copyWith(
          activeHostName: result.hostName,
          activeHostUrl: client.connectedUrl,
          workspaces: listing.workspaces,
          groups: listing.groups,
          targets: listing.targets,
          reconnecting: false,
          notice: PairingNotice.reconnected,
          clearError: true,
        ),
      );
      await _persistDesktop(
        desktop.copyWith(
          lastConnectedAt: DateTime.now(),
          lastConnectedUrl: client.connectedUrl,
        ),
      );
      final resume = _resumeCatalogId;
      _resumeCatalogId = null;
      if (resume != null) await _resumeMirror(resume);
    } on Object catch (e) {
      _appendLog('Reconnect failed: $e');
      if (isClosed || !_wantsConnection) return;
      _scheduleReconnect();
    }
  }

  /// Re-subscribes the mirror the user was watching before the drop. Falls back
  /// to the session list when that pane did not survive.
  Future<void> _resumeMirror(String catalogId) async {
    final client = _client;
    if (client == null || isClosed) return;
    if (!_knowsLiveCatalogId(catalogId)) {
      _appendLog('Mirrored pane is gone; returning to the session list');
      emit(
        state.copyWith(
          phase: PairingClientPhase.connected,
          clearActiveCatalogId: true,
        ),
      );
      return;
    }
    try {
      _activeSubscription = await client.subscribe(catalogId);
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: PairingClientPhase.mirroring,
          activeCatalogId: catalogId,
          connectGeneration: _generation,
        ),
      );
    } on Object catch (e) {
      _appendLog('Resume mirror failed: $e');
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: PairingClientPhase.connected,
          clearActiveCatalogId: true,
        ),
      );
    }
  }

  void _stopReconnecting() {
    _wantsConnection = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _resumeCatalogId = null;
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
          targets: listing.targets,
        ),
      );
    } on Object catch (e) {
      _appendLog('Refresh failed: $e');
    }
  }

  /// Lists directories on the desktop for the create-workspace folder picker.
  /// Carries the host's refusal reason rather than a bare null so the picker can
  /// say *why* instead of showing an empty folder. [targetId] picks the machine;
  /// null means the host's default plane.
  Future<PairingCallResult<PairingDirListing>> browseDir({
    String? path,
    String? targetId,
  }) async {
    final client = _client;
    if (client == null) {
      return const PairingCallResult<PairingDirListing>.failed('not connected');
    }
    try {
      return PairingCallResult.ok(
        await client.browseDir(path: path, targetId: targetId),
      );
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
    String? targetId,
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
        targetId: targetId,
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
        connectGeneration: _generation,
      ),
    );
  }

  /// Opens the mirror named by a tapped host notification.
  ///
  /// Not routed through [openSession] alone: that one overwrites
  /// [_activeSubscription] without releasing the old mirror and lets the host's
  /// `no such session` bubble out. The list-tap path cannot reach either (the
  /// list only renders while connected and only offers live panes); a stale
  /// notification can reach both.
  Future<void> openMirrorFromNotification(String catalogId) async {
    if (_client == null) return;
    if (state.phase != PairingClientPhase.connected &&
        state.phase != PairingClientPhase.mirroring) {
      return;
    }
    if (state.activeCatalogId == catalogId) return;
    if (!_knowsLiveCatalogId(catalogId)) {
      // The pane list can lag the host by one `session.changed`.
      await refreshWorkspaces();
      if (isClosed || !_knowsLiveCatalogId(catalogId)) return;
    }
    if (state.phase == PairingClientPhase.mirroring) leaveMirror();
    try {
      await openSession(catalogId);
    } on Object catch (e) {
      _appendLog('Open from notification failed: $e');
    }
  }

  bool _knowsLiveCatalogId(String catalogId) => state.workspaces.any(
    (w) => w.panes.any((p) => p.live && p.catalogId == catalogId),
  );

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

  /// Changed files in the repository the mirrored pane sits in, or null when
  /// nothing is mirrored. Errors are logged and surface as null so the sheet can
  /// say "couldn't read" without a crash on a repo-less pane.
  Future<PairingGitChanges?> gitChanges() async {
    final sub = _activeSubscription;
    final client = _client;
    if (sub == null || client == null) return null;
    try {
      return await client.gitChanges(sub.sub);
    } on Object catch (e) {
      _appendLog('git.changes failed: $e');
      return null;
    }
  }

  /// Unified diff of [path], or null when the request failed. [path] must come
  /// from the [gitChanges] list — the host refuses anything else.
  Future<String?> gitDiff(String path) async {
    final sub = _activeSubscription;
    final client = _client;
    if (sub == null || client == null) return null;
    try {
      return await client.gitDiff(sub: sub.sub, path: path);
    } on Object catch (e) {
      _appendLog('git.diff failed: $e');
      return null;
    }
  }

  /// Fires when the mirrored pane's agent just finished a turn, which is the one
  /// moment its changed-file list is worth re-reading.
  ///
  /// A hint rather than the list itself: the changes view is only mounted some of
  /// the time, and fetching on every notice would run `git status` on the host
  /// for a sheet nobody has open.
  Stream<void> get gitRefreshHints => _gitRefreshHints.stream;
  final _gitRefreshHints = StreamController<void>.broadcast();

  /// Streams [source] to the host, which writes it into the mirrored pane's
  /// working directory and returns the absolute path it used.
  Future<String> uploadMedia({
    required String filename,
    required UploadSource source,
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
      source: source,
      onProgress: onProgress,
    );
  }

  /// Stops the in-flight upload. The upload future then completes with
  /// [PairingUploadCancelled], which the caller treats as a user action rather
  /// than a failure.
  void cancelUpload() => _client?.cancelUpload();

  /// Cancels pairing / disconnects and returns to the host list. Also ends any
  /// pending retry — this is the only thing that does.
  Future<void> cancel() async {
    _stopReconnecting();
    await _disposeClient();
    _activeSubscription = null;
    emit(
      state.copyWith(
        phase: PairingClientPhase.idle,
        clearPendingOffer: true,
        clearActiveCatalogId: true,
        clearError: true,
        reconnecting: false,
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
    _agentNoticeSub = client.agentNotices.listen(_onNotice);
    _disconnectedSub = client.disconnected.listen((_) => _onDisconnected());
    return client;
  }

  /// Hands the notice to the presenter, and — when it is the mirrored pane's own
  /// agent going idle — nudges the changes view to re-read.
  ///
  /// `waiting`/`interrupted` deliberately do not nudge: mid-turn the working tree
  /// is whatever the agent has written so far, so refreshing then shows a
  /// half-finished edit as if it were the result.
  void _onNotice(PairingAgentNotice notice) {
    _onAgentNotice(notice);
    if (notice.kind != PairingAgentNoticeKind.done) return;
    if (notice.catalogId == null) return;
    if (notice.catalogId != state.activeCatalogId) return;
    if (!_gitRefreshHints.isClosed) _gitRefreshHints.add(null);
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
    _agentNoticeSub?.cancel();
    _agentNoticeSub = null;
    _disconnectedSub?.cancel();
    _disconnectedSub = null;
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
    _agentNoticeSub?.cancel();
    _agentNoticeSub = null;
    _disconnectedSub?.cancel();
    _disconnectedSub = null;
    final client = _client;
    _client = null;
    if (client != null) await client.close();
  }

  @override
  Future<void> close() async {
    _stopReconnecting();
    await _disposeClient();
    await _gitRefreshHints.close();
    return super.close();
  }
}
