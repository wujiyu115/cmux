import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/layout_cubit.dart';
import '../../../cubits/run_cubit.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_folder.dart';
import '../../../services/commands/quick_open_command_registrar.dart';
import '../../../services/commands/run_command_registrar.dart';
import '../../../services/commands/workspace_search_command_registrar.dart';
import '../../../services/git/git_command_runner.dart';
import '../../../services/storage/app_storage.dart';
import '../../../services/workspace/workspace_run_registry.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../services/workspace/workspace_tools_scope_registry.dart';
import '../../../services/workspace/workspace_worktree_registry.dart';
import '../../../services/workbench/workbench_shell_launcher.dart';
import '../../../utils/ui/app_keys.dart';
import '../../../widgets/right_tools/right_tools_panel.dart';
import '../../../widgets/workspace_terminal_panel.dart';
import '../../chat_page.dart';
import '../../quick_open/quick_open_overlay.dart';
import '../../workspace_ide/workspace_ide_shell.dart';
import 'workspace_route_active_scope.dart';
import 'workspace_search_dialog.dart';
import 'workspace_session_actions.dart';
import 'workspace_tools_scope_sync.dart';

class WorkspaceSplitPane extends StatefulWidget {
  const WorkspaceSplitPane({
    required this.workspace,
    required this.tabScopeId,
    super.key,
  });

  final Workspace workspace;
  final String tabScopeId;

  @override
  State<WorkspaceSplitPane> createState() => _WorkspaceSplitPaneState();
}

class _WorkspaceSplitPaneState extends State<WorkspaceSplitPane> {
  /// Bridges an IDE-shell split drag to center shell terminals' PTY resize hold.
  /// Owned here so it shares a lifetime with the workbench shell surfaces.
  final _terminalHold = WorkspaceTerminalHoldHandle();
  RunCubit? _boundRunCubit;
  RunCommandHost? _runCommandHost;
  WorkspaceSearchHost? _workspaceSearchHost;
  QuickOpenHost? _quickOpenHost;
  late final void Function() _openWorkspaceSearch = _openSearch;
  late final void Function() _openQuickOpen = _openQuickOpenNow;

  /// Guards the empty-workspace auto-terminal so it fires once per empty
  /// episode (not on every rebuild while the shell is still connecting).
  bool _autoTerminalScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _runCommandHost = context.read<RunCommandHost>();
    _workspaceSearchHost = context.read<WorkspaceSearchHost>();
    _quickOpenHost = context.read<QuickOpenHost>();
    _syncRunCommandHost();
    _syncWorkspaceSearchHost();
    _syncQuickOpenHost();
  }

  @override
  void dispose() {
    final cubit = _boundRunCubit;
    final host = _runCommandHost;
    if (cubit != null && host != null) {
      host.unbind(cubit);
    }
    _boundRunCubit = null;
    _workspaceSearchHost?.unbind(_openWorkspaceSearch);
    _quickOpenHost?.unbind(_openQuickOpen);
    super.dispose();
  }

  void _openSearch() {
    if (!mounted) return;
    unawaited(showWorkspaceSearchDialog(context, workspace: widget.workspace));
  }

  void _openQuickOpenNow() {
    if (!mounted) return;
    final lifecycle = context.read<ChatCubit>().lifecycle;
    final scopeState = context
        .read<WorkspaceToolsScopeRegistry>()
        .cubitFor(tabScopeId: widget.tabScopeId, lifecycle: lifecycle)
        .state;
    final targetId = widget.workspace.folders.isEmpty
        ? WorkspaceFolder.localTargetId
        : widget.workspace.folders.first.targetId;
    final targetContext = scopeState.runtimeContextForTarget(targetId);
    final fs = targetContext?.filesystem ?? AppStorage.fs;
    unawaited(
      showQuickOpenDialog(
        context,
        workspace: widget.workspace,
        filesystem: fs,
        gitRunner: targetContext == null
            ? null
            : gitCommandRunnerForContext(targetContext),
      ),
    );
  }

  /// Empty workspaces auto-launch their default terminal — cmux keeps a live
  /// terminal per workspace (the chat-landing composer is gone; terminals only).
  /// Fires only for the visible (route-active) workspace, once per empty episode,
  /// and only when a [WorkbenchShellLauncher] is in scope (absent in lightweight
  /// widget tests — those skip cleanly). [ctx] is the builder context (owns
  /// worktree / launcher / chat providers).
  void _maybeAutoOpenTerminal(BuildContext ctx, String cwd) {
    if (!WorkspaceRouteActiveScope.routeActiveOf(ctx)) return;
    if (cwd.trim().isEmpty) return;
    try {
      ctx.read<WorkbenchShellLauncher>();
    } on ProviderNotFoundException {
      return; // No launcher in scope (test harness).
    }

    // Workspace already owns a live shell terminal → focus it instead of
    // spawning a second PTY. Reset the guard so a later empty episode re-arms.
    final workbench = ctx.read<WorkbenchCubit>();
    final existingShell = workbench.resolveMostRecentShell(
      widget.workspace.workspaceId,
    );
    if (existingShell != null) {
      _autoTerminalScheduled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        workbench.select(widget.workspace.workspaceId, existingShell);
      });
      return;
    }

    // No live shell → open the default terminal once per empty episode.
    if (_autoTerminalScheduled) return;
    _autoTerminalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        openWorkspaceDefaultTerminal(
          ctx,
          widget.workspace,
          tabScopeId: widget.tabScopeId,
          worktreePath: cwd,
        ),
      );
    });
  }

  void _syncWorkspaceSearchHost() {
    final host = _workspaceSearchHost;
    if (host == null) return;
    final routeActive = WorkspaceRouteActiveScope.routeActiveOf(context);
    if (routeActive) {
      host.bind(_openWorkspaceSearch);
    } else {
      host.unbind(_openWorkspaceSearch);
    }
  }

  void _syncQuickOpenHost() {
    final host = _quickOpenHost;
    if (host == null) return;
    final routeActive = WorkspaceRouteActiveScope.routeActiveOf(context);
    if (routeActive) {
      host.bind(_openQuickOpen);
    } else {
      host.unbind(_openQuickOpen);
    }
  }

  void _syncRunCommandHost() {
    final host = _runCommandHost;
    if (host == null) return;
    final routeActive = WorkspaceRouteActiveScope.routeActiveOf(context);
    final runCubit = context.read<WorkspaceRunRegistry>().cubitFor(
      tabScopeId: widget.tabScopeId,
      workspaceId: widget.workspace.workspaceId,
      folders: widget.workspace.folders,
    );
    if (routeActive) {
      host.bind(runCubit);
      _boundRunCubit = runCubit;
    } else if (identical(_boundRunCubit, runCubit)) {
      host.unbind(runCubit);
      _boundRunCubit = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatLifecycle = context.read<ChatCubit>().lifecycle;
    final scopeCubit = context.read<WorkspaceToolsScopeRegistry>().cubitFor(
      tabScopeId: widget.tabScopeId,
      lifecycle: chatLifecycle,
    );
    final worktreeCubit = context.read<WorkspaceWorktreeRegistry>().cubitFor(
      workspaceId: widget.workspace.workspaceId,
      repoPath: widget.workspace.firstFolderPath,
    );
    final runCubit = context.read<WorkspaceRunRegistry>().cubitFor(
      tabScopeId: widget.tabScopeId,
      workspaceId: widget.workspace.workspaceId,
      folders: widget.workspace.folders,
    );
    return MultiBlocProvider(
      providers: [
        BlocProvider<WorkspaceToolsScopeCubit>.value(value: scopeCubit),
        BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
        BlocProvider<RunCubit>.value(value: runCubit),
      ],
      child: BlocBuilder<WorktreeCubit, WorktreeState>(
        buildWhen: (a, b) => a.currentWorktreePath != b.currentWorktreePath,
        builder: (context, wt) {
          final cwd = wt.currentWorktreePath.isNotEmpty
              ? wt.currentWorktreePath
              : widget.workspace.firstFolderPath;
          _maybeAutoOpenTerminal(context, cwd);
          return WorkspaceToolsScopeSync(
            workspace: widget.workspace,
            cwd: cwd,
            tabScopeId: widget.tabScopeId,
            child: WorkspaceIdeShell(
              terminalHold: _terminalHold,
              // Left pane retired: the global workspace nav owns switching now,
              // and worktree/session actions moved to the shell "+" menu.
              center: ChatPage(
                cwd: cwd,
                additionalPaths: widget.workspace.extraFolderPaths,
                workspaceId: widget.workspace.workspaceId,
                tabScopeId: widget.tabScopeId,
                holdHandle: _terminalHold,
              ),
              // Side panes are off the first-open critical path: chrome +
              // landing paint first, then tools mount.
              right: TpDeferredMountShell(
                delayFrames: 2,
                child: _WorkspaceRightToolsPane(
                  cwd: cwd,
                  additionalPaths: widget.workspace.extraFolderPaths,
                  workspaceId: widget.workspace.workspaceId,
                  tabScopeId: widget.tabScopeId,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Right-tools pane for the IDE shell. Resolves its own active context so chat
/// churn only rebuilds this subtree, not the whole shell / center.
class _WorkspaceRightToolsPane extends StatelessWidget {
  const _WorkspaceRightToolsPane({
    required this.cwd,
    required this.additionalPaths,
    required this.workspaceId,
    required this.tabScopeId,
  });

  final String cwd;
  final List<String> additionalPaths;
  final String workspaceId;
  final String tabScopeId;

  @override
  Widget build(BuildContext context) {
    final layoutState = context.watch<LayoutCubit>().state;
    return RightToolsPanel(
      cwd: cwd,
      additionalPaths: additionalPaths,
      preferences: layoutState.preferences.copyWith(
        rightToolsVisible: layoutState.preferences.rightToolsVisible,
      ),
      panelKey: AppKeys.rightToolsPanel,
      dismissDrawerOnAction: false,
      workspaceId: workspaceId,
      toolsScopeId: tabScopeId,
    );
  }
}
