import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../models/app_session.dart';
import '../../models/member_remote_provision_progress.dart';
import '../../repositories/session_repository.dart';
import '../../services/session/session_lifecycle_service.dart';
import '../../services/agent_status/agent_status_seat_lookup.dart';
import '../../cubits/agent_attention_cubit.dart';
import '../../services/agent_status/agent_status_gateway.dart';
import 'chat_session_shell_factory.dart';
import 'model/chat_state.dart';
import 'model/chat_tab.dart';
import 'session_data_store.dart';
import 'tab_member_materializer.dart';
import 'tab_session_runtime_coordinator.dart';
import 'chat_tab_store.dart';

/// Connect-state transitions owned by [ChatCubit] (via [ChatConnectStateMixin]).
abstract interface class SessionConnectStatePort {
  void beginSessionConnect(String sessionId);
  void failSessionConnect(String sessionId, String rawMessage);
  void finishSessionConnect(String sessionId);
  void clearLaunchError(String sessionId);
  void setLaunchError(String sessionId, String rawMessage);
  void emitLaunchWarnings(List<String> warnings);
  void updateTabRunning(String tabId);

  /// Updates (or clears) live remote provision UI for [memberId] on [sessionId].
  void setMemberRemoteProvisionProgress(
    String sessionId,
    String memberId,
    MemberRemoteProvisionProgress? progress,
  );
}

/// Session snapshot writes routed through the cubit emit path.
abstract interface class SessionSnapshotPort {
  void appendSessionSnapshot(AppSession session);
  void replaceSessionSnapshot(AppSession session);
  void removeSessionSnapshot(String sessionId);
  void emitSnapshot(ChatDataSnapshot snapshot);
}

/// Seam [SessionLaunchService] uses to read/emit ChatState and reach the other
/// collaborators. Implemented by ChatCubit, which stays the sole emit owner
/// (the service routes every state write through [applyState] / the connect
/// state-machine methods).
abstract interface class SessionLaunchHost
    implements SessionConnectStatePort, SessionSnapshotPort {
  ChatState get state;
  bool get isClosed;

  /// Single emit entry point (wraps the cubit's protected emit).
  void applyState(ChatState next);
  void refreshActiveWorkspaceTabs();
  void closeSessionTab(String sessionId);

  // Cubit-owned facade methods the launch flow drives.
  void selectMember(String memberId);
  Future<void> renameSession(
    SessionRepository repo,
    String sessionId,
    String newName,
  );
  Future<void> loadWorkspaceData(SessionRepository repo);

  ChatTab? get activeTab;

  // Collaborators.
  ChatTabStore get tabStore;
  ChatSessionShellFactory get shellFactory;
  TabSessionRuntimeCoordinator get sessionRuntime;
  TabMemberMaterializer get memberMaterializer;
  SessionLifecycleService get lifecycle;
  SessionDataStore get dataStore;

  // Resolvers.
  SessionRepository? get sessionRepository;
  PostFrameScheduler get postFrameScheduler;

  AgentStatusGateway get agentStatusGateway;

  /// Seat CLI + skip-permissions map for `/agent-status` (null in tests).
  AgentStatusSeatLookup? get agentStatusSeatLookup;

  /// Permission-attention state; cleared on seat/tab dispose (null in tests).
  AgentAttentionCubit? get agentAttentionCubit;


  /// Workspace opt-in: inject IS_SANDBOX when launching Claude as root over SSH.
  Future<bool> isWorkspaceRootSandboxEnvOptIn(String workspaceId);

  /// Terminal theme for member PTY spawn (COLORFGBG / Claude `theme: auto`).
  /// Null skips apply — tests and early bootstrap may omit it.
  TerminalTheme? resolveTerminalThemeForLaunch();
}

/// Drop attention + seat lookup for every seat in [sessionId].
///
/// Used on team-session restart (shells disconnect without [onProcessExited]).
/// Does not unregister the gateway status session — reconnect re-registers seats.
void clearAgentStatusSessionSeats({
  AgentAttentionCubit? attention,
  AgentStatusSeatLookup? seatLookup,
  required String sessionId,
}) {
  attention?.clearSession(sessionId);
  seatLookup?.clearSession(sessionId);
}

/// Drop attention + seat lookup for one seat (PTY exit, disconnect, reconnect).
extension SessionLaunchHostAgentStatus on SessionLaunchHost {
  void clearAgentStatusSeat({
    required String sessionId,
    required String memberId,
  }) {
    agentAttentionCubit?.clearSeat(
      sessionId: sessionId,
      memberId: memberId,
    );
    agentStatusSeatLookup?.unregisterSeat(
      sessionId: sessionId,
      memberId: memberId,
    );
  }

  void clearAgentStatusSession(String sessionId) {
    clearAgentStatusSessionSeats(
      attention: agentAttentionCubit,
      seatLookup: agentStatusSeatLookup,
      sessionId: sessionId,
    );
  }
}
