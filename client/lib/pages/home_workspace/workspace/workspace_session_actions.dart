import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import 'package:uuid/uuid.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/session_preferences_cubit.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../cubits/workbench/workbench_tab.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/landing_launch_context.dart';
import '../../../models/simple_launch_identity.dart';
import '../../../models/workspace.dart';
import '../../../models/app_session.dart';
import '../../../models/session_continue_overrides.dart';
import '../../../models/cli_tool.dart';
import '../../../repositories/session_repository.dart';
import '../../../services/workbench/workbench_shell_actions.dart';
import '../../../utils/workspace/landing_draft_resolver.dart';
import '../../../utils/logging/logger.dart';
import '../../../utils/workspace/workspace_path_utils.dart';

const _uuid = Uuid();

/// Builds the [SessionOpenRequest] for opening a persisted session from the
/// sidebar / session list.
///
/// [connectImmediately] defaults to false (history review). Pass true when
/// [SessionPreferences.openExistingSessionStartsTerminal] is enabled.
SessionOpenRequest buildOpenExistingSessionRequest({
  required AppSession session,
  Workspace? workspace,
  SessionRepository? repo,
  required String emptyDisplayTitleFallback,
  bool connectImmediately = false,
}) {
  return SessionOpenRequest(
    session: session,
    workspace: workspace,
    repo: repo,
    emptyDisplayTitleFallback: emptyDisplayTitleFallback,
    connectImmediately: connectImmediately,
  );
}

Future<void> openWorkspaceSessionTab(
  BuildContext context,
  Workspace workspace,
  AppSession session, {
  String? tabScopeId,
}) async {
  appLogger.d(
    '[session-launch] openWorkspaceSessionTab start '
    'session=${session.sessionId} workspace=${workspace.workspaceId} '
    'launchState=${session.launchState.name}',
  );

  _syncWorktreeForSession(context, session);

  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final fallback = context.l10n.defaultNewChatSessionTitle;
  final connectImmediately = context
      .read<SessionPreferencesCubit>()
      .state
      .preferences
      .openExistingSessionStartsTerminal;

  final status = await chatCubit.requestOpenSession(
    buildOpenExistingSessionRequest(
      session: session,
      workspace: workspace,
      repo: repo,
      emptyDisplayTitleFallback: fallback,
      connectImmediately: connectImmediately,
    ),
  );
  if (!context.mounted) return;
  _handleSessionOpenStatus(
    context,
    status,
    blockedMixedMessage: context.l10n.mixedWorkspaceSessionLaunchBlocked,
  );
  if (status != SessionOpenStatus.opened) return;

  final scopeId = tabScopeId ?? workspace.workspaceId;
  final workbench = context.read<WorkbenchCubit>();
  final tabId = WorkbenchTabId.session(session.sessionId);
  final asPreview = !connectImmediately;
  if (connectImmediately) {
    chatCubit.setSessionWorkbenchView(
      session.sessionId,
      SessionWorkbenchView.terminal,
    );
  } else {
    final existing = chatCubit.tabStore.openTabBySessionId(session.sessionId);
    // Already live: focus + pin, keep whatever Chat/Terminal view the user set.
    if (existing != null && existing.isRunning) {
      workbench.ensureTab(workspace.workspaceId, tabId, preview: false);
      return;
    }
  }
  final replaced = workbench.ensureTab(
    workspace.workspaceId,
    tabId,
    preview: asPreview,
  );
  if (!context.mounted) return;
  await WorkbenchShellActions.closeReplacedPreview(
    context: context,
    workspaceId: workspace.workspaceId,
    tabScopeId: scopeId,
    replaced: replaced,
  );
}

void _handleSessionOpenStatus(
  BuildContext context,
  SessionOpenStatus status, {
  required String blockedMixedMessage,
}) {
  switch (status) {
    case SessionOpenStatus.opened:
      return;
    case SessionOpenStatus.blockedMixedMemberTargets:
      AppToast.show(
        context,
        message: blockedMixedMessage,
        variant: TpToastVariant.warning,
      );
    case SessionOpenStatus.missingWorkspace:
      AppToast.show(
        context,
        message: context.l10n.sessionLaunchMissingWorkspace,
        variant: TpToastVariant.warning,
      );
    case SessionOpenStatus.missingTeamMember:
      AppToast.show(
        context,
        message: context.l10n.sessionLaunchMissingTeamMember,
        variant: TpToastVariant.warning,
      );
  }
}

void _syncWorktreeForSession(BuildContext context, AppSession session) {
  try {
    context.read<WorktreeCubit>().syncCurrentForSessionPath(
      session.firstFolderPath,
    );
  } on ProviderNotFoundException {
    // Outside the workspace split pane — no worktree scope to sync.
  }
}

/// Opens the Chat pane (new chat) for [tabScopeId] without closing open session tabs.
Future<void> showWorkspaceComposeLanding(
  BuildContext context,
  Workspace workspace, {
  required String tabScopeId,
}) async {
  final chat = context.read<ChatCubit>();
  if (chat.tabStore.activeWorkspaceId != tabScopeId) {
    chat.setActiveWorkspace(tabScopeId);
  }
  chat.enterNewChat(tabScopeId);
}

/// Opens Chat with [worktreePath] pre-selected as the session cwd.
Future<void> showWorkspaceComposeLandingWithWorktree(
  BuildContext context,
  Workspace workspace, {
  required String tabScopeId,
  required String worktreePath,
}) async {
  final draft = await resolveLandingDraft(
    workspaceId: workspace.workspaceId,
    simpleModeDefaultFullAccess: context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .simpleModeDefaultFullAccess,
  );
  if (!context.mounted) return;

  final normalizedPath = normalizeWorkspacePath(worktreePath);
  await persistLandingDraft(
    workspace.workspaceId,
    draft.copyWith(workingDirectoryPath: normalizedPath),
  );
  if (!context.mounted) return;

  try {
    context.read<WorktreeCubit>().setCurrentWorktree(normalizedPath);
  } on ProviderNotFoundException {
    // Outside the workspace split pane — draft still carries the path.
  }

  await showWorkspaceComposeLanding(
    context,
    workspace,
    tabScopeId: tabScopeId,
  );
}

/// Creates a conversation from Chat, connects like automation dispatch, and
/// delivers [message] to the member PTY.
///
/// [launch] is the sole source of launch intent (preset, team, identity, mode).
///
/// [onSessionOpened] fires once the session tab is staged, before the (possibly
/// minutes-long) connect + deliver phase, so hosts such as the Selection →
/// Ask AI dialog can dismiss themselves without waiting for delivery.
Future<void> submitWorkspaceLandingMessage(
  BuildContext context,
  Workspace workspace, {
  required LandingLaunchContext launch,
  required String message,
  String? workingDirectory,
  void Function(String sessionId)? onSessionOpened,
}) async {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return;

  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final l10n = context.l10n;
  final liveWorkspace = chatCubit.state.workspaces.firstWhere(
    (w) => w.workspaceId == workspace.workspaceId,
    orElse: () => workspace,
  );
  final simpleIdentity = _resolveSimpleLaunchIdentity(
    context,
    presetId: launch.presetId,
  );
  final plannedSessionId = _uuid.v4();
  final status = await _requestCreateWorkspaceConversation(
    context,
    liveWorkspace,
    simpleIdentity: simpleIdentity,
    workingDirectory: workingDirectory,
    fixedSessionId: plannedSessionId,
    continueOverrides: SessionContinueOverrides(
      dangerouslySkipPermissions: launch.dangerouslySkipPermissions,
    ),
  );
  if (status == null) return;
  if (status != SessionOpenStatus.opened) {
    if (context.mounted) {
      _handleSessionOpenStatus(
        context,
        status,
        blockedMixedMessage: l10n.mixedWorkspaceCreateSessionBlocked,
      );
    }
    return;
  }

  // Landing unmounts ChatPage while a Run tab (启动配置) may still be active;
  // syncSessions does not steal focus from run/shell/file — select explicitly.
  if (context.mounted) {
    context.read<WorkbenchCubit>().ensureTab(
      liveWorkspace.workspaceId,
      WorkbenchTabId.session(plannedSessionId),
    );
  }

  onSessionOpened?.call(plannedSessionId);

  // Opening the session exits new-chat mode and unmounts [WorkspaceChatPane].
  // Delivery must keep going via cubits/repos captured above — not [context.mounted].

  final session = await _sessionById(
    chatCubit: chatCubit,
    repo: repo,
    sessionId: plannedSessionId,
    workspaceId: liveWorkspace.workspaceId,
  );
  if (session == null) {
    appLogger.w(
      'submitWorkspaceLandingMessage: session missing after open '
      'sessionId=$plannedSessionId workspace=${liveWorkspace.workspaceId}',
    );
    return;
  }

  final memberId = session.sessionId;

  final connected = await _ensureLandingSessionConnected(
    chatCubit: chatCubit,
    session: session,
    memberId: memberId,
  );
  if (!connected) {
    appLogger.w(
      'submitWorkspaceLandingMessage: member not ready '
      'session=${session.sessionId} member=$memberId',
    );
    if (context.mounted) {
      AppToast.show(
        context,
        message: l10n.homeWorkspaceNewConversation,
        variant: TpToastVariant.error,
      );
    }
    return;
  }

  try {
    await chatCubit.sessionRuntime.deliverUserCommandToMember(
      session.sessionId,
      memberId,
      trimmed,
      directToPty: true,
    );
    // Landing inject bypasses FirstUserLineCapture (keyboard path only).
    await chatCubit.applyFirstPromptTitle(session.sessionId, trimmed);
  } on Object catch (error, stackTrace) {
    appLogger.e(
      'submitWorkspaceLandingMessage',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      AppToast.show(
        context,
        message: '${l10n.homeWorkspaceNewConversation}: $error',
        variant: TpToastVariant.error,
      );
    }
  }
}

Future<AppSession?> _sessionById({
  required ChatCubit chatCubit,
  required SessionRepository repo,
  required String sessionId,
  required String workspaceId,
}) async {
  final fromState = chatCubit.state.sessions
      .where((s) => s.sessionId == sessionId && s.workspaceId == workspaceId)
      .firstOrNull;
  if (fromState != null) return fromState;
  final loaded = await repo.loadSessionsForWorkspace(workspaceId);
  return loaded.where((s) => s.sessionId == sessionId).firstOrNull;
}

Future<bool> _ensureLandingSessionConnected({
  required ChatCubit chatCubit,
  required AppSession session,
  required String memberId,
}) async {
  // requestCreateAndOpenSession already staged the tab and scheduled async
  // persist+connect. Re-opening here races that path and can connect with the
  // provisional session (empty cliTeamName) before disk persistence finishes.
  try {
    await chatCubit.memberMaterializer
        .ensureMemberInputReady(
          session.sessionId,
          memberId,
          directToPty: true,
        )
        .timeout(const Duration(seconds: 120));
    return true;
  } on TimeoutException {
    return false;
  }
}

Future<SessionOpenStatus?> _requestCreateWorkspaceConversation(
  BuildContext context,
  Workspace workspace, {
  CliTool? cli,
  SimpleLaunchIdentity? simpleIdentity,
  String? workingDirectory,
  String? fixedSessionId,
  SessionContinueOverrides? continueOverrides,
  bool preserveWorkbenchView = false,
}) async {
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final l10n = context.l10n;
  final identity =
      simpleIdentity ?? _resolveSimpleLaunchIdentity(context, cli: cli);

  try {
    return await chatCubit.requestCreateAndOpenSession(
      SessionCreateRequest(
        workspace: workspace,
        repo: repo,
        cli: identity.cli,
        simpleIdentity: identity,
        workingDirectory: workingDirectory,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
        fixedSessionId: fixedSessionId,
        continueOverrides: continueOverrides,
        preserveWorkbenchView: preserveWorkbenchView,
      ),
    );
  } on Object catch (error, stackTrace) {
    appLogger.e(
      l10n.homeWorkspaceNewConversation,
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      AppToast.show(
        context,
        message: '${l10n.homeWorkspaceNewConversation}: $error',
        variant: TpToastVariant.error,
      );
    }
    return null;
  }
}

SimpleLaunchIdentity _resolveSimpleLaunchIdentity(
  BuildContext context, {
  String? presetId,
  CliTool? cli,
}) {
  return SimpleLaunchIdentity.resolve(cli: cli, presetId: presetId);
}
