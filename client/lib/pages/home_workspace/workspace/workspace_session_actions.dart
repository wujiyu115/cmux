import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/session_preferences_cubit.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../cubits/workbench/workbench_tab.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_folder.dart';
import '../../../models/app_session.dart';
import '../../../models/workspace_terminal_session_spec.dart';
import '../../../repositories/session_repository.dart';
import '../../../services/git/git_worktree_service.dart';
import '../../../services/host/host_interactive_shell.dart';
import '../../../services/storage/app_storage.dart';
import '../../../services/storage/runtime_context.dart';
import '../../../services/storage/workspace_layout.dart';
import '../../../services/workbench/workbench_shell_actions.dart';
import '../../../services/workbench/workbench_shell_launcher.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../utils/logging/logger.dart';
import 'worktree_create_dialog.dart';

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

/// Resolves the terminal spec for [workspace]'s configured default terminal.
///
/// [Workspace.defaultShell] encodes the choice: empty / null follows the
/// work-plane default (`defaultSessionSpecFor`); a `local` / `ssh:*` / `wsl:*`
/// value selects that folder target; any other value is a local shell
/// executable path.
WorkspaceTerminalSessionSpec workspaceDefaultTerminalSpec({
  required Workspace workspace,
  required String cwd,
}) {
  final defaultShell = workspace.defaultShell?.trim() ?? '';
  if (defaultShell.isNotEmpty) {
    if (defaultShell == WorkspaceFolder.localTargetId ||
        defaultShell.startsWith('ssh:') ||
        defaultShell.startsWith('wsl:')) {
      return WorkspaceTerminalWorkspaceTargetSpec(defaultShell);
    }
    return WorkspaceTerminalLocalSpec(defaultShell);
  }
  return defaultSessionSpecFor(
    cwd: cwd,
    folders: workspace.folders,
    fallbackLocalShell: HostInteractiveShell.defaultExecutable(),
  );
}

/// Opens a new shell terminal for [workspace] using its default terminal.
///
/// This is the "新建终端" action: clicking "new" launches a PTY tab directly
/// (no compose landing). cwd resolves [worktreePath] → current worktree →
/// first workspace folder; the shell spec follows that cwd's work-plane.
Future<void> openWorkspaceDefaultTerminal(
  BuildContext context,
  Workspace workspace, {
  required String tabScopeId,
  String? worktreePath,
}) async {
  final launcher = context.read<WorkbenchShellLauncher>();
  final l10n = context.l10n;

  var cwd = worktreePath?.trim() ?? '';
  if (cwd.isEmpty) {
    try {
      cwd = context.read<WorktreeCubit>().state.pathForNewSession ?? '';
    } on ProviderNotFoundException {
      // Outside the workspace split pane — no worktree scope.
    }
  }
  if (cwd.isEmpty) cwd = workspace.firstFolderPath.trim();
  if (cwd.isEmpty) return;

  final spec = workspaceDefaultTerminalSpec(workspace: workspace, cwd: cwd);

  await launcher.openAndSelect(
    workspaceId: workspace.workspaceId,
    tabScopeId: tabScopeId,
    cwd: cwd,
    spec: spec,
    sshConnectFailedMessage: l10n.workspaceTerminalSshConnectFailed,
    onStateChanged: () {},
    mounted: () => context.mounted,
  );
}

/// Whether worktree create/refresh applies to [workContext]'s work-plane
/// (native, WSL, or SSH git). Drives the worktree entries in the shell "+" menu.
bool worktreeManagementEnabled(RuntimeContext workContext) =>
    workContext.mode == StorageBackendMode.native ||
    workContext.mode == StorageBackendMode.wsl ||
    workContext.mode == StorageBackendMode.ssh;

/// Reloads the worktree list for [workspace]'s current repo. Wired to the shell
/// "+" menu "refresh worktrees" entry (retired from the old sidebar header).
void refreshWorkspaceWorktrees(BuildContext context, Workspace workspace) {
  final cubit = context.read<WorktreeCubit>();
  final repoPath = cubit.state.repoPath.trim().isNotEmpty
      ? cubit.state.repoPath
      : workspace.firstFolderPath;
  unawaited(cubit.load(repoPath));
}

/// Opens the worktree-create dialog for [workspace], adds the worktree on its
/// work-plane, then optionally launches a terminal in the new worktree. Wired to
/// the shell "+" menu "new worktree" entry (retired from the old sidebar header).
Future<void> openWorkspaceNewWorktree(
  BuildContext context,
  Workspace workspace, {
  required String tabScopeId,
}) async {
  final cubit = context.read<WorktreeCubit>();
  final l10n = context.l10n;
  final tools = WorkspaceToolsScope.of(context).tools;
  if (tools == null) return;
  final repoPath = cubit.state.repoPath.trim().isNotEmpty
      ? cubit.state.repoPath
      : workspace.firstFolderPath;
  final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
  final result = await showWorktreeCreateDialog(
    context,
    repoName: _repoBasename(repoPath),
    repoPath: repoPath,
    layout: layout.worktreePathFor,
    branchLoader: branchListLoaderFor(tools.context),
    showStartConversationOption: true,
  );
  if (result == null) return;
  try {
    await GitWorktreeService.forContext(tools.context).add(
      repoPath,
      result.worktreePath,
      branch: result.branch,
      baseRef: result.baseRef,
      existingBranch: result.existingBranch,
    );
    await cubit.load(repoPath);
    cubit.setCurrentWorktree(result.worktreePath);
    if (result.startConversation && context.mounted) {
      await openWorkspaceDefaultTerminal(
        context,
        workspace,
        tabScopeId: tabScopeId,
        worktreePath: result.worktreePath,
      );
    }
  } on Object catch (error) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: l10n.worktreeCreateFailed(error.toString()),
      variant: TpToastVariant.error,
    );
  }
}

String _repoBasename(String path) {
  final parts = path.replaceAll(r'\', '/').split('/')
    ..removeWhere((e) => e.isEmpty);
  return parts.isEmpty ? path : parts.last;
}

