import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/workspace.dart';
import '../models/workspace_accent.dart';
import '../models/workspace_folder.dart';
import '../models/app_session.dart';
import '../models/workspace_icon_picker_result.dart';
import '../models/workspace_icon_ref.dart';
import '../models/cli_tool.dart';
import '../models/runtime_target.dart';
import '../repositories/session_repository.dart';
import '../services/workspace/workspace_icon_service.dart';
import '../services/workspace/workspace_icon_storage.dart';
import '../services/storage/app_storage.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/agent_status/agent_status_gateway.dart';
import '../services/agent_status/agent_status_seat_lookup.dart';
import 'agent_attention_cubit.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/terminal_theme_for_launch.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../utils/session/workspace_sessions.dart';
import '../../widgets/workspace_icon_picker_dialog.dart';
import 'chat/session_launch_retry.dart';
import 'chat/chat_connect_state_mixin.dart';
import 'chat/session_data_store.dart';
import 'chat/chat_session_shell_factory.dart';
import 'chat/chat_tab_store.dart';
import 'chat/session_launch_host.dart';
import 'chat/session_launch_service.dart';
import 'chat/tab_member_materializer.dart';
import 'chat/tab_session_runtime_coordinator.dart';
import 'layout_cubit.dart';
import 'chat/model/chat_state.dart';
import 'chat/model/chat_tab.dart';
import 'chat/model/session_connect_request.dart';
import 'chat/model/session_create_request.dart';
import 'chat/model/session_open_request.dart';
import 'chat/model/session_open_status.dart';

export 'chat/model/chat_state.dart';
export 'chat/model/chat_tab_info.dart';
export 'chat/model/session_create_request.dart';
export 'chat/model/session_open_request.dart';
export 'chat/model/session_open_status.dart';

class ChatCubit extends Cubit<ChatState>
    with ChatConnectStateMixin
    implements SessionLaunchHost {
  ChatCubit({
    required String Function() executableResolver,
    CliExecutableResolver? cliExecutableResolver,
    TerminalSessionFactory terminalSessionFactory =
        defaultTerminalSessionFactory,
    PostFrameScheduler? postFrameScheduler,
    SessionLifecycleService? lifecycleService,
    SessionRepository? sessionRepository,
    TerminalTransportFactory? transportFactory,
    SshActiveProfileResolver? sshProfileResolver,
    SshProfileByIdResolver? sshProfileById,
    String Function()? sshDefaultWorkingDirectoryResolver,
    bool Function()? sshUseLoginShellResolver,
    RuntimeTarget Function()? defaultTargetResolver,
    int Function()? terminalScrollbackLinesResolver,
    AgentStatusGateway? agentStatusGateway,
    AgentStatusSeatLookup? agentStatusSeatLookup,
    AgentAttentionCubit? agentAttentionCubit,
    LayoutCubit? layoutCubit,
  }) : _teammateBusMcpGateway =
           agentStatusGateway ?? AgentStatusGateway(),
       _agentStatusSeatLookup = agentStatusSeatLookup,
       _agentAttentionCubit = agentAttentionCubit,
       _layoutCubit = layoutCubit,
       _shellFactory = ChatSessionShellFactory(
         executableResolver: executableResolver,
         cliExecutableResolver: cliExecutableResolver,
         terminalSessionFactory: terminalSessionFactory,
         transportFactory: transportFactory,
         sshProfileResolver: sshProfileResolver,
         sshProfileById: sshProfileById,
         sshDefaultWorkingDirectoryResolver: sshDefaultWorkingDirectoryResolver,
         sshUseLoginShellResolver: sshUseLoginShellResolver,
         defaultTargetResolver: defaultTargetResolver,
         terminalScrollbackLinesResolver: terminalScrollbackLinesResolver,
       ),
       _postFrameScheduler = postFrameScheduler ?? _defaultPostFrameScheduler,
       _lifecycle = lifecycleService ?? SessionLifecycleService(),
       _sessionRepository = sessionRepository,
       super(const ChatState()) {
    final attention = _agentAttentionCubit;
    if (attention != null) {
      _agentAttentionSub = attention.stream.listen((_) {
        if (!isClosed) _recomputeWorkingSessions();
      });
    }
  }

  /// Fired when History should drop cache / reload (disconnect or switch back).
  void Function(String sessionId)? onSessionHistoryStale;

  /// Fired when a session tab is torn down so History can dispose its seats.
  void Function(String sessionId)? onHistorySeatsDispose;


  final AgentStatusGateway _teammateBusMcpGateway;
  final AgentStatusSeatLookup? _agentStatusSeatLookup;
  final AgentAttentionCubit? _agentAttentionCubit;
  StreamSubscription<AgentAttentionState>? _agentAttentionSub;
  final LayoutCubit? _layoutCubit;
  final ChatTabStore _tabStore = ChatTabStore();
  final SessionDataStore _dataStore = SessionDataStore();
  final Map<String, Future<void>> _sessionHydrationByWorkspace = {};
  late final SessionLaunchService _launchService = SessionLaunchService(this);
  late final TabSessionRuntimeCoordinator _sessionRuntime =
      TabSessionRuntimeCoordinator(
        tabStore: _tabStore,
        isClosed: () => isClosed,
        onAfterTurnLatched: _onOperatorTurnLatched,
      );
  late final TabMemberMaterializer _memberMaterializer = TabMemberMaterializer(
    runtime: _sessionRuntime,
    tabStore: _tabStore,
    isClosed: () => isClosed,
  );

  final ChatSessionShellFactory _shellFactory;
  final PostFrameScheduler _postFrameScheduler;
  final SessionLifecycleService _lifecycle;
  final SessionRepository? _sessionRepository;

  @override
  ChatTabStore get tabStore => _tabStore;

  // ===== SessionLaunchHost =====

  @override
  void applyState(ChatState next) {
    emit(next);
  }

  @override
  void emitSnapshot(ChatDataSnapshot snapshot) => _emitSnapshot(snapshot);

  @override
  void appendSessionSnapshot(AppSession session) {
    _emitSnapshot(
      _dataStore.appendSession(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        session,
      ),
    );
  }

  @override
  void replaceSessionSnapshot(AppSession session) {
    _emitSnapshot(
      _dataStore.replaceSession(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        session,
      ),
    );
  }

  @override
  void removeSessionSnapshot(String sessionId) {
    _emitSnapshot(
      _dataStore.removeSession(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        sessionId,
      ),
    );
  }

  @override
  void closeSessionTab(String sessionId) {
    final idx = _tabStore.activeIndexOfSession(sessionId);
    if (idx != -1) closeTab(idx);
  }

  @override
  ChatTab? get activeTab => _activeTab;

  @override
  ChatSessionShellFactory get shellFactory => _shellFactory;

  @override
  TabSessionRuntimeCoordinator get sessionRuntime => _sessionRuntime;

  @override
  TabMemberMaterializer get memberMaterializer => _memberMaterializer;

  @override
  AgentStatusGateway get agentStatusGateway => _teammateBusMcpGateway;

  @override
  AgentStatusSeatLookup? get agentStatusSeatLookup => _agentStatusSeatLookup;

  @override
  AgentAttentionCubit? get agentAttentionCubit => _agentAttentionCubit;

  @override
  SessionLifecycleService get lifecycle => _lifecycle;

  @override
  SessionDataStore get dataStore => _dataStore;

  /// True once [ensureSessionsForWorkspace] has loaded this workspace's
  /// sessions from disk. The UI uses this to tell "still loading" apart from
  /// "genuinely empty" so a cold tab switch shows a skeleton, not a flash of
  /// the empty-conversations placeholder.
  bool sessionsLoadedForWorkspace(String workspaceId) =>
      _dataStore.sessionsLoadedForWorkspace(workspaceId);

  @override
  SessionRepository? get sessionRepository => _sessionRepository;

  @override
  PostFrameScheduler get postFrameScheduler => _postFrameScheduler;

  @override
  Future<bool> isWorkspaceRootSandboxEnvOptIn(String workspaceId) async {
    final id = workspaceId.trim();
    if (id.isEmpty) return false;
    for (final w in state.workspaces) {
      if (w.workspaceId == id) return w.rootSandboxEnvOptIn;
    }
    return false;
  }

  @override
  TerminalTheme? resolveTerminalThemeForLaunch() {
    final layout = _layoutCubit;
    if (layout == null) return null;
    return resolveTerminalThemeFromLayout(
      preferences: layout.state.preferences,
      platformBrightness:
          SchedulerBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  /// Session spinners follow shell activity, not agent presence.
  void _updateWorkingSessions(Set<String> ids) {
    if (isClosed || setEquals(ids, state.workingSessionIds)) return;
    emit(state.copyWith(workingSessionIds: ids));
  }

  /// Plain shells report no agent activity, so nothing is ever "working".
  void _recomputeWorkingSessions() => _updateWorkingSessions(const {});

  /// History / Terminal operator submit latched a seat turn — refresh session
  /// working and clear sticky permission waiting so the sidebar spinner can show.
  void _onOperatorTurnLatched(String sessionId, String memberId) {
    final attention = _agentAttentionCubit;
    if (attention != null && memberId.trim().isNotEmpty) {
      // Why: [userTurnActive] already lights the spinner. Stamping
      // attention.working here pins [sessionIsAgentActive] for CLIs without
      // Stop/done (Cursor simple), so the sidebar stays busy after PTY quiet.
      // Clear any prior waiting/working seat so a fresh submit is not locked.
      attention.clearSeat(sessionId: sessionId, memberId: memberId);
    }
    _recomputeWorkingSessions();
  }

  @visibleForTesting
  void updateWorkingSessionsForTest(Set<String> ids) =>
      _updateWorkingSessions(ids);

  @visibleForTesting
  void debugRecomputeWorkingSessions() => _recomputeWorkingSessions();

  /// Seat-level working for the compose stop button.
  ///
  /// A plain shell is "working" while the operator's submitted line has not
  /// been echoed back as an idle prompt.
  bool isMemberWorking(String sessionId, String memberId) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    final shell = tab?.memberShells[memberId];
    return shell?.userTurnActive ?? false;
  }

  /// Cancels in-flight PTY inject and sends CLI turn-interrupt bytes to the seat.
  Future<void> interruptSelectedMemberTurn({
    String? sessionId,
    String? memberId,
  }) async {
    final sid = sessionId ?? state.activeSessionId;
    if (sid == null) return;
    final tab = _tabStore.openTabBySessionId(sid);
    if (tab == null) return;
    final mid = (memberId ?? tab.selectedMemberId).trim();
    if (mid.isEmpty) return;

    final shell = tab.memberShells[mid];
    if (shell == null || !shell.isConnected) return;
    _sessionRuntime.abortMemberInject(sid, mid);
    // Plain shells interrupt the foreground job with Ctrl-C.
    shell.input.writeToPty('');
  }

  /// Exercises History/Terminal submit → [onAfterTurnLatched] without PTY I/O.
  @visibleForTesting
  void debugNotifyOperatorTurnLatched(String sessionId, String memberId) =>
      _onOperatorTurnLatched(sessionId, memberId);

  /// Switches the active workspace bucket and republishes its tabs into state.
  /// Called by the workspace page whenever the active workspace changes.
  void setActiveWorkspace(String workspaceId) {
    final restoredIndex = _tabStore.setActiveWorkspace(
      workspaceId,
      currentActiveIndex: state.activeTabIndex,
    );
    _publishActiveWorkspaceTabs(restoredIndex);
  }

  /// Switches the chat tab bucket for a workspace tab activation.
  void activateWorkspaceTab({required String workspaceTabKey}) {
    final restoredIndex = _tabStore.setActiveWorkspace(
      workspaceTabKey,
      currentActiveIndex: state.activeTabIndex,
    );
    _publishActiveWorkspaceTabs(restoredIndex);
  }

  /// Re-emits the active bucket's tab infos without changing the workspace, after
  /// callers mutate the active bucket directly via [tabStore].
  @override
  void refreshActiveWorkspaceTabs() =>
      _publishActiveWorkspaceTabs(state.activeTabIndex);

  void _publishActiveWorkspaceTabs(
    int desiredIndex, {
    ChatDataSnapshot? snapshot,
  }) {
    if (_tabStore.activeTabsIsEmpty) {
      final empty = snapshot;
      emit(
        state.copyWith(
          tabs: const [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
          clearSessionConnectingId: true,
          selectedMemberId: '',
          workspaces: empty?.workspaces,
          sessions: empty?.sessions,
          visibleWorkspaces: empty?.visibleWorkspaces,
          visibleSessions: empty?.visibleSessions,
        ),
      );
      return;
    }
    final index = desiredIndex.clamp(0, _tabStore.activeTabCount - 1);
    final tab = _tabStore.activeTabs[index];
    emit(
      state.copyWith(
        tabs: _tabStore.activeTabInfos(),
        activeTabIndex: index,
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
        workspaces: snapshot?.workspaces,
        sessions: snapshot?.sessions,
        visibleWorkspaces: snapshot?.visibleWorkspaces,
        visibleSessions: snapshot?.visibleSessions,
      ),
    );
  }

  static void _defaultPostFrameScheduler(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
  }

  void _emitSnapshot(ChatDataSnapshot snap, {ChatState? base}) {
    final s = base ?? state;
    emit(
      s.copyWith(
        workspaces: snap.workspaces,
        sessions: snap.sessions,
        visibleWorkspaces: snap.visibleWorkspaces,
        visibleSessions: snap.visibleSessions,
      ),
    );
  }

  ChatTab? get _activeTab => _tabStore.activeTab(state.activeTabIndex);

  TerminalSession? get currentSession {
    final tab = _activeTab;
    if (tab == null) return null;
    final memberShell = tab.memberShells[tab.selectedMemberId];
    return memberShell ?? tab.resumeSession;
  }

  /// Session workspace path for the active tab (used to resolve relative file links).
  String get activeTabWorkingDirectory {
    final tab = _activeTab;
    if (tab == null) return AppStorage.cwd;
    return _tabStore
        .workingDirectoryAndAddDirsForTab(
          tab,
          state.sessions,
          workspaces: state.workspaces,
        )
        .$1;
  }

  /// Last launch failure for the active tab, or [ChatState.sessionLaunchError].
  String? get activeLaunchError {
    if (!_tabStore.activeTabsIsEmpty) {
      final index = state.activeTabIndex.clamp(0, _tabStore.activeTabCount - 1);
      final error = _tabStore.activeTabs[index].info.launchError;
      if (error != null && error.isNotEmpty) return error;
    }
    final pending = state.sessionLaunchError;
    if (pending != null && pending.isNotEmpty) return pending;
    return null;
  }

  @override
  Future<void> loadWorkspaceData(SessionRepository repo) async {
    _emitSnapshot(await _dataStore.loadWorkspaceData(repo));
  }

  /// Home index: workspace manifests only; sessions hydrate separately.
  Future<void> loadWorkspaceIndex(SessionRepository repo) async {
    _emitSnapshot(await _dataStore.loadWorkspaceIndex(repo));
  }

  Future<void> hydrateAllSessions(SessionRepository repo) async {
    final sessions = await _dataStore.loadSessions(repo);
    _dataStore.markWorkspacesSessionsHydrated(
      state.workspaces.map((workspace) => workspace.workspaceId),
    );
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
    );
  }

  /// Loads [workspaceId] sessions from disk when the UI needs them.
  Future<void> ensureSessionsForWorkspace(String workspaceId) async {
    final repo = _sessionRepository;
    final id = workspaceId.trim();
    if (repo == null || id.isEmpty) return;
    if (_dataStore.sessionsLoadedForWorkspace(id)) return;

    final inflight = _sessionHydrationByWorkspace[id];
    if (inflight != null) {
      await inflight;
      return;
    }

    final load = _hydrateWorkspaceSessions(repo, id);
    _sessionHydrationByWorkspace[id] = load;
    try {
      await load;
    } finally {
      _sessionHydrationByWorkspace.remove(id);
    }
  }

  Future<List<AppSession>> sessionsForWorkspaceReady(String workspaceId) async {
    await ensureSessionsForWorkspace(workspaceId);
    return sessionsForWorkspace(
      state.workspaces.where((w) => w.workspaceId == workspaceId).firstOrNull ??
          Workspace(workspaceId: workspaceId, folders: const [], createdAt: 0),
      state.sessions,
    );
  }

  Future<void> _hydrateWorkspaceSessions(
    SessionRepository repo,
    String workspaceId,
  ) async {
    final sessions = await _dataStore.loadSessionsForWorkspace(
      repo,
      workspaceId,
    );
    if (isClosed) return;
    _emitSnapshot(
      _dataStore.mergeWorkspaceSessions(
        current: ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        workspaceId: workspaceId,
        workspaceSessions: sessions,
      ),
    );
  }

  /// Updates persisted-index mirrors in state and recomputes team-scoped sidebar lists.
  void ingestWorkspaceSessionSnapshot({
    required List<Workspace> workspaces,
    required List<AppSession> sessions,
  }) {
    _emitSnapshot(
      _dataStore.deriveSnapshot(workspaces: workspaces, sessions: sessions),
    );
  }

  Future<AppSession> createSession(
    String workspaceId,
    SessionRepository repo, {
    CliTool? cli,
    String? workingDirectory,
    String? fixedSessionId,
  }) async {
    final session = await _dataStore.createSession(
      workspaceId,
      repo,
      cli: cli,
      workingDirectory: workingDirectory,
      fixedSessionId: fixedSessionId,
    );
    _emitSnapshot(
      _dataStore.appendSession(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        session,
      ),
    );
    return session;
  }

  Future<SessionOpenStatus> requestCreateAndOpenSession(
    SessionCreateRequest request,
  ) => _launchService.requestCreateAndOpenSession(request);

  /// Creates (or reuses) the workspace for [primaryPath], seeds a first session,
  /// reloads workspace data, and returns the workspace id so callers can navigate
  /// straight to the new workspace.
  Future<String> createWorkspaceWithFirstSession(
    List<WorkspaceFolder> folders,
    SessionRepository repo, {
    String display = '',
    bool allowDuplicate = false,
  }) async {
    final result = await _dataStore.createWorkspaceWithFirstSession(
      folders,
      repo,
      display: display,
      allowDuplicate: allowDuplicate,
    );
    _emitSnapshot(result.snapshot);
    return result.workspaceId;
  }

  Future<void> addWorkspaceDirectory(
    SessionRepository repo,
    Workspace workspace,
    WorkspaceFolder folder,
  ) async {
    final snap = await _dataStore.addWorkspaceDirectory(
      repo,
      workspace,
      folder,
    );
    if (snap != null) _emitSnapshot(snap);
  }

  Future<void> updateWorkspaceMetadata(
    SessionRepository repo,
    String workspaceId, {
    String? display,
    String? defaultProfileId,
    bool? rootSandboxEnvOptIn,
    String? groupId,
    WorkspaceAccentPreset? accent,
    bool clearAccent = false,
    String? defaultShell,
    bool clearDefaultShell = false,
  }) async {
    _emitSnapshot(
      await _dataStore.updateWorkspaceMetadata(
        repo,
        workspaceId,
        display: display,
        defaultProfileId: defaultProfileId,
        rootSandboxEnvOptIn: rootSandboxEnvOptIn,
        groupId: groupId,
        accent: accent,
        clearAccent: clearAccent,
        defaultShell: defaultShell,
        clearDefaultShell: clearDefaultShell,
      ),
    );
  }

  Future<void> applyWorkspaceIcon(
    SessionRepository repo,
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    _emitSnapshot(await _dataStore.applyWorkspaceIcon(repo, workspaceId, icon));
  }

  Future<void> importCustomWorkspaceIcon(
    SessionRepository repo,
    String workspaceId,
    String localSourcePath,
  ) async {
    _emitSnapshot(
      await _dataStore.importCustomWorkspaceIcon(
        repo,
        workspaceId,
        localSourcePath,
      ),
    );
  }

  /// Opens the icon picker and applies the user's choice.
  ///
  /// Returns an error message when custom import fails; otherwise `null`.
  Future<String?> editWorkspaceIcon(
    BuildContext context,
    SessionRepository repo,
    Workspace workspace,
  ) async {
    final result = await showWorkspaceIconPickerDialog(
      context,
      workspace: workspace,
    );
    return switch (result) {
      WorkspaceIconPickerCancelled() => null,
      WorkspaceIconPickerUploadRequested() => _pickAndImportCustomIcon(
        repo,
        workspace.workspaceId,
      ),
      WorkspaceIconPickerCommitted(:final icon) => _applyCommittedIcon(
        repo,
        workspace.workspaceId,
        icon,
      ),
    };
  }

  Future<String?> _pickAndImportCustomIcon(
    SessionRepository repo,
    String workspaceId,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: WorkspaceIconStorage.allowedExtensions
          .where((ext) => ext != 'jpeg')
          .toList(growable: false),
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;

    try {
      await importCustomWorkspaceIcon(repo, workspaceId, path);
      return null;
    } on WorkspaceIconImportException catch (error) {
      return error.message;
    }
  }

  Future<String?> _applyCommittedIcon(
    SessionRepository repo,
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    await applyWorkspaceIcon(repo, workspaceId, icon);
    return null;
  }

  Future<SessionOpenStatus> requestOpenSession(SessionOpenRequest request) =>
      _launchService.requestOpenSession(request);

  Future<void> reconnectSshProfile(String profileId) =>
      _launchService.reconnectSshProfile(profileId);

  Future<void> _tearDownTab(ChatTab tab) async {
    final sessionId = tab.info.id;
    onHistorySeatsDispose?.call(sessionId);
    for (final session in tab.sessions) {
      session.dispose();
    }
    _agentAttentionCubit?.clearSession(sessionId);
    _agentStatusSeatLookup?.clearSession(sessionId);
    _teammateBusMcpGateway.unregisterAgentStatusSession(sessionId);
    await tab.disposeBus();
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabStore.activeTabCount) return;
    final tab = _tabStore.removeAt(index);
    // Emit tabs before tearDown so working→idle sees the tab already gone
    // (idle notify must not fire for user-closed sessions).
    if (_tabStore.activeTabsIsEmpty) {
      emit(
        state.copyWith(
          tabs: [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
          workingSessionIds: const <String>{},
        ),
      );
    } else {
      final newIdx = state.activeTabIndex >= _tabStore.activeTabCount
          ? _tabStore.activeTabCount - 1
          : state.activeTabIndex;
      final nextTab = _tabStore.activeTabs[newIdx];
      emit(
        state.copyWith(
          tabs: _tabStore.activeTabInfos(),
          activeTabIndex: newIdx,
          activeSessionId: nextTab.info.id,
          selectedMemberId: nextTab.selectedMemberId,
          workingSessionIds: const <String>{},
        ),
      );
    }
    unawaited(_tearDownTab(tab));
  }

  /// Number of open session-backed tabs in [workspaceId]'s bucket (excludes
  /// `local-` scratch tabs, which have no persisted workspace session).
  int openTabCountForWorkspace(String workspaceId) =>
      _tabStore.sessionBackedCountForWorkspace(workspaceId);

  /// Closes (terminates) every open tab belonging to [workspaceId] by dropping
  /// its whole bucket and disposing each tab's sessions and team-bus.
  void closeTabsForWorkspace(String workspaceId) {
    final removed = _tabStore.removeWorkspace(workspaceId);
    if (removed.isEmpty) return;
    // Republish whenever the active bucket was affected: either it was the
    // named bucket for this workspace, or it is the legacy empty-string bucket
    // and tabs were removed from it (legacy path before setActiveWorkspace).
    final activeIsAffected =
        workspaceId == _tabStore.activeWorkspaceId ||
        _tabStore.activeWorkspaceId.isEmpty;
    if (activeIsAffected) {
      _publishActiveWorkspaceTabs(0);
    }
    _updateWorkingSessions(const <String>{});
    for (final tab in removed) {
      unawaited(_tearDownTab(tab));
    }
  }

  void closeOtherTabs(int index) {
    if (index < 0 || index >= _tabStore.activeTabCount) return;
    final removed = <ChatTab>[];
    for (var i = _tabStore.activeTabCount - 1; i >= 0; i--) {
      if (i == index) continue;
      removed.add(_tabStore.removeAt(i));
    }
    final kept = _tabStore.activeTabs.single;
    emit(
      state.copyWith(
        tabs: _tabStore.activeTabInfos(),
        activeTabIndex: 0,
        activeSessionId: kept.info.id,
        selectedMemberId: kept.selectedMemberId,
        workingSessionIds: const <String>{},
      ),
    );
    for (final tab in removed) {
      unawaited(_tearDownTab(tab));
    }
  }

  void closeRightTabs(int index) {
    if (index < 0 || index >= _tabStore.activeTabCount) return;
    final removed = <ChatTab>[];
    for (var i = _tabStore.activeTabCount - 1; i > index; i--) {
      removed.add(_tabStore.removeAt(i));
    }
    final active = _activeTab;
    emit(
      state.copyWith(
        tabs: _tabStore.activeTabInfos(),
        activeTabIndex: state.activeTabIndex.clamp(
          0,
          _tabStore.activeTabCount - 1,
        ),
        activeSessionId: active?.info.id,
        selectedMemberId: active?.selectedMemberId ?? '',
        workingSessionIds: const <String>{},
      ),
    );
    for (final tab in removed) {
      unawaited(_tearDownTab(tab));
    }
  }

  void selectTab(int index) {
    if (index < 0 || index >= _tabStore.activeTabCount) return;
    final tab = _tabStore.activeTabs[index];
    emit(
      state.copyWith(
        activeTabIndex: index,
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
      ),
    );
  }

  @override
  void selectMember(String memberId) {
    if (state.selectedMemberId == memberId) return;
    _activeTab?.selectedMemberId = memberId;
    emit(state.copyWith(selectedMemberId: memberId));
  }

  /// Whether the member's PTY is up (spawning through running).
  ///
  /// [memberId] is the shell key (`memberShells` / History `shellMemberId`),
  /// not only the active workspace tab.
  bool isMemberRunning({required String sessionId, required String memberId}) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    final shell = tab?.memberShells[memberId];
    return shell?.isRunning ?? false;
  }

  Future<void> connectWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) => _launchService.connectWorkspaceSession(request, repo: repo);

  /// Rebuilds and replays the connect request for a failed/disconnected
  /// session — used by the launch-failure banner's Retry action.
  Future<void> retrySessionLaunch(String sessionId) async {
    final id = sessionId.trim();
    if (id.isEmpty) return;
    final tab = _tabStore.openTabBySessionId(id);
    AppSession? session;
    for (final s in state.sessions) {
      if (s.sessionId == id) {
        session = s;
        break;
      }
    }
    session ??= tab?.persistedSession;
    if (session == null) return;

    await connectWorkspaceSession(
      buildRetryExistingSessionConnect(session: session),
    );
  }

  void disconnectSession() {
    final tab = activeTab;
    final sessionId = tab?.info.id;
    _launchService.disconnectSession();
    if (sessionId != null && sessionId.isNotEmpty) {
      onSessionHistoryStale?.call(sessionId);
    }
  }

  /// Disconnects [memberId] for [sessionId] (any open tab). Prefer this over
  /// [disconnectSession] when the target is not the active tab's selection
  /// (e.g. Resource Manager kill).
  void disconnectMemberShell(String sessionId, String memberId) {
    _launchService.disconnectMemberShell(sessionId, memberId);
    if (sessionId.trim().isNotEmpty) {
      onSessionHistoryStale?.call(sessionId);
    }
  }

  Future<void> restartWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) => _launchService.restartWorkspaceSession(request, repo: repo);

  @override
  Future<void> renameSession(
    SessionRepository repo,
    String sessionId,
    String newName,
  ) async {
    await repo.renameSession(sessionId, newName);
    final sessions = state.sessions.map((s) {
      if (s.sessionId == sessionId) return s.copyWith(display: newName);
      return s;
    }).toList();
    final tabs = state.tabs.map((t) {
      if (t.id == sessionId) return t.copyWith(title: newName);
      return t;
    }).toList();
    for (final tab in _tabStore.openTabs) {
      if (tab.info.id == sessionId) {
        tab.info = tab.info.copyWith(title: newName);
      }
    }
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
      base: state.copyWith(sessions: sessions, tabs: tabs),
    );
  }

  /// Compose-landing / inject path: rename untitled session from first prompt.
  Future<void> applyFirstPromptTitle(String sessionId, String firstPrompt) =>
      _launchService.applyFirstPromptTitle(sessionId, firstPrompt);

  Future<void> touchSession(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    await repo.touchSession(sessionId);
    _emitSnapshot(await _dataStore.loadWorkspaceData(repo));
  }

  /// Persists a manual session arrangement. [orderedSessionIds] is the new
  /// top-to-bottom order (used by [AppSessionSort.manual]).
  Future<void> reorderSessions(List<String> orderedSessionIds) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    // Optimistic: stamp the new sortOrder in memory and emit immediately so the
    // list stays where the user dropped it, then persist on disk in the
    // background. Awaiting the per-file writes + a full reload first made the
    // row snap back, then jump once persistence finished (~1-2s later).
    final orderById = <String, int>{
      for (var i = 0; i < orderedSessionIds.length; i++)
        orderedSessionIds[i]: i + 1,
    };
    final sessions = [
      for (final s in state.sessions)
        orderById.containsKey(s.sessionId)
            ? s.copyWith(sortOrder: orderById[s.sessionId])
            : s,
    ];
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
      base: state.copyWith(sessions: sessions),
    );
    await repo.reorderSessions(orderedSessionIds);
  }

  Future<void> toggleSessionPin(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    await repo.toggleSessionPin(sessionId);
    _emitSnapshot(await _dataStore.loadWorkspaceData(repo));
  }

  Future<void> deleteSession(SessionRepository repo, String sessionId) async {
    final wasActive = state.activeSessionId == sessionId;
    final sessions = state.sessions
        .where((s) => s.sessionId != sessionId)
        .toList();
    ChatTab? removedTab;
    final idx = _tabStore.activeIndexOfSession(sessionId);
    if (idx != -1) {
      removedTab = _tabStore.removeAt(idx);
    }
    final tabs = _tabStore.activeTabs.map((t) => t.info).toList();
    final working = const <String>{};

    if (wasActive && !_tabStore.activeTabsIsEmpty) {
      final newIdx = idx < _tabStore.activeTabCount
          ? idx
          : _tabStore.activeTabCount - 1;
      final nextTab = _tabStore.activeTabs[newIdx];
      _emitSnapshot(
        _dataStore.deriveSnapshot(
          workspaces: state.workspaces,
          sessions: sessions,
        ),
        base: state.copyWith(
          tabs: tabs,
          activeTabIndex: newIdx,
          activeSessionId: nextTab.info.id,
          selectedMemberId: nextTab.selectedMemberId,
          workingSessionIds: working,
        ),
      );
    } else if (_tabStore.activeTabsIsEmpty) {
      _emitSnapshot(
        _dataStore.deriveSnapshot(
          workspaces: state.workspaces,
          sessions: sessions,
        ),
        base: state.copyWith(
          tabs: [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
          workingSessionIds: working,
        ),
      );
    } else {
      _emitSnapshot(
        _dataStore.deriveSnapshot(
          workspaces: state.workspaces,
          sessions: sessions,
        ),
        base: state.copyWith(tabs: tabs, workingSessionIds: working),
      );
    }

    if (removedTab != null) {
      await _tearDownTab(removedTab);
    }

    _emitSnapshot(await _dataStore.deleteSessionRecord(repo, sessionId));
  }

  Future<Workspace> cloneWorkspace(
    SessionRepository repo,
    String sourceWorkspaceId, {
    String? display,
  }) async {
    final result = await _dataStore.cloneWorkspace(
      repo,
      sourceWorkspaceId,
      display: display,
    );
    _emitSnapshot(result.snapshot);
    return result.workspace;
  }

  Future<void> deleteWorkspace(
    SessionRepository repo,
    String workspaceId,
  ) async {
    Workspace? workspace;
    for (final p in state.workspaces) {
      if (p.workspaceId == workspaceId) {
        workspace = p;
        break;
      }
    }
    if (workspace == null) return;
    for (final sid in workspace.sessionIds.toList()) {
      await deleteSession(repo, sid);
    }
    _emitSnapshot(await _dataStore.deleteWorkspaceRecord(repo, workspaceId));
  }

  void addSystemMessage(String content) {
    final target = currentSession;
    target?.write('\r\n[system] $content\r\n');
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    await _agentAttentionSub?.cancel();
    _agentAttentionSub = null;
    final busDisposals = <Future<void>>[];
    for (final tab in _tabStore.openTabs) {
      busDisposals.add(_tearDownTab(tab));
    }
    await Future.wait(busDisposals);
    _tabStore.clear();
    await super.close();
  }
}
