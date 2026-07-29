import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/chat/model/session_workbench_view.dart';
import '../../cubits/file_tree_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../utils/session/workspace_tab_session_scope.dart';
import '../../cubits/worktree_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/app_provider_config.dart';
import '../../models/member_instance.dart';
import '../../models/member_presence.dart';
import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../models/workspace_topology.dart';
import '../../pages/home_workspace/workspace/member_detail_dialog.dart';
import '../../pages/home_workspace/workspace/member_config_directory_opener.dart';
import '../../services/cli/member_config/member_config_inspector.dart';
import '../../services/storage/home_target_controller.dart';
import '../../services/storage/runtime_context.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../utils/team/team_member_naming.dart';
import '../../utils/workspace/workspace_path_utils.dart';
import '../git/git_source_control_panel.dart';
import 'file_tree_panel.dart';
import 'members_panel.dart';
import 'right_tools_tool_preferences.dart';
import 'tabbed_panel.dart';
import 'tool_view.dart';

/// Pokes the shared FS watcher when a session leaves the working set.
class RightToolsWorkingTurnListener extends StatelessWidget {
  const RightToolsWorkingTurnListener({
    required this.onTurnEnd,
    required this.child,
    super.key,
  });

  final VoidCallback onTurnEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _WorkingSetDelta(onTurnEnd: onTurnEnd, child: child);
  }
}

class _WorkingSetDelta extends StatefulWidget {
  const _WorkingSetDelta({required this.onTurnEnd, required this.child});

  final VoidCallback onTurnEnd;
  final Widget child;

  @override
  State<_WorkingSetDelta> createState() => _WorkingSetDeltaState();
}

class _WorkingSetDeltaState extends State<_WorkingSetDelta> {
  Set<String> _previous = const {};

  @override
  void initState() {
    super.initState();
    _previous = context.read<ChatCubit>().state.workingSessionIds;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ChatCubit, ChatState>(
      listenWhen: (previous, next) =>
          previous.workingSessionIds != next.workingSessionIds,
      listener: (context, state) {
        final working = state.workingSessionIds;
        if (_previous.difference(working).isNotEmpty) {
          widget.onTurnEnd();
        }
        _previous = working;
      },
      child: widget.child,
    );
  }
}

/// Syncs member presence when the selected team changes.
class RightToolsPresenceTeamSync extends StatefulWidget {
  const RightToolsPresenceTeamSync({
    required this.team,
    required this.child,
    super.key,
  });

  final TeamProfile? team;
  final Widget child;

  @override
  State<RightToolsPresenceTeamSync> createState() =>
      _RightToolsPresenceTeamSyncState();
}

class _RightToolsPresenceTeamSyncState
    extends State<RightToolsPresenceTeamSync> {
  String? _syncedTeamId;

  @override
  Widget build(BuildContext context) {
    if (!TickerMode.valuesOf(context).enabled) {
      return widget.child;
    }
    final team = widget.team;
    if (team != null) {
      final teamId = team.id;
      if (teamId != _syncedTeamId) {
        _syncedTeamId = teamId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.read<MemberPresenceCubit>().syncPresenceTeam(team);
        });
      }
    }
    return widget.child;
  }
}

@immutable
class RightToolsChatSlice {
  const RightToolsChatSlice({
    required this.selectedMemberId,
    required this.hasActiveTab,
    required this.activeSessionId,
    required this.hasTeamBus,
    this.persistedSession,
  });

  factory RightToolsChatSlice.from(
    ChatState state, {
    required bool hasTeamBus,
    AppSession? persistedSession,
  }) {
    return RightToolsChatSlice(
      selectedMemberId: state.selectedMemberId,
      hasActiveTab: state.tabs.isNotEmpty,
      activeSessionId: state.activeSessionId,
      hasTeamBus: hasTeamBus,
      persistedSession: persistedSession,
    );
  }

  final String selectedMemberId;
  final bool hasActiveTab;
  final String? activeSessionId;
  final bool hasTeamBus;
  final AppSession? persistedSession;

  @override
  bool operator ==(Object other) {
    return other is RightToolsChatSlice &&
        selectedMemberId == other.selectedMemberId &&
        hasActiveTab == other.hasActiveTab &&
        activeSessionId == other.activeSessionId &&
        hasTeamBus == other.hasTeamBus &&
        identical(persistedSession, other.persistedSession);
  }

  @override
  int get hashCode => Object.hash(
    selectedMemberId,
    hasActiveTab,
    activeSessionId,
    hasTeamBus,
    persistedSession,
  );
}

/// Builds the tabbed tool views with narrow bloc subscriptions.
class RightToolsToolViews extends StatefulWidget {
  const RightToolsToolViews({
    required this.preferences,
    required this.cwd,
    required this.workspaceId,
    required this.toolsScopeId,
    required this.isPersonalContext,
    required this.team,
    required this.dismissDrawerOnAction,
    required this.fileTreeCubit,
    required this.workContext,
    required this.scope,
    super.key,
  });

  final RightToolsToolPreferences preferences;
  final String cwd;
  final String workspaceId;
  final String toolsScopeId;
  final bool isPersonalContext;
  final TeamProfile? team;
  final bool dismissDrawerOnAction;
  final FileTreeCubit fileTreeCubit;
  final RuntimeContext workContext;
  final WorkspaceToolsScopeState scope;

  @override
  State<RightToolsToolViews> createState() => _RightToolsToolViewsState();
}

@immutable
class _RightToolsViewsCacheKey {
  const _RightToolsViewsCacheKey({
    required this.preferences,
    required this.isPersonalContext,
    required this.team,
    required this.chatSlice,
    required this.scopeRoots,
    required this.cwd,
    required this.workspaceId,
    required this.toolsScopeId,
  });

  final RightToolsToolPreferences preferences;
  final bool isPersonalContext;
  final TeamProfile? team;
  final RightToolsChatSlice chatSlice;
  final List<String> scopeRoots;
  final String cwd;
  final String workspaceId;
  final String toolsScopeId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _RightToolsViewsCacheKey &&
            preferences == other.preferences &&
            isPersonalContext == other.isPersonalContext &&
            team == other.team &&
            chatSlice == other.chatSlice &&
            listEquals(scopeRoots, other.scopeRoots) &&
            cwd == other.cwd &&
            workspaceId == other.workspaceId &&
            toolsScopeId == other.toolsScopeId;
  }

  @override
  int get hashCode => Object.hash(
    preferences,
    isPersonalContext,
    team,
    chatSlice,
    Object.hashAll(scopeRoots),
    cwd,
    workspaceId,
    toolsScopeId,
  );
}

class _RightToolsToolViewsState extends State<RightToolsToolViews> {
  _RightToolsViewsCacheKey? _cacheKey;
  List<ToolView>? _cachedViews;

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    if (!widget.isPersonalContext && team == null) {
      return const SizedBox.shrink();
    }

    final chatSlice = context.select<ChatCubit, RightToolsChatSlice>(
      (c) => RightToolsChatSlice.from(
        c.state,
        hasTeamBus: false,
        persistedSession: c.activeTab?.persistedSession,
      ),
    );

    final cacheKey = _RightToolsViewsCacheKey(
      preferences: widget.preferences,
      isPersonalContext: widget.isPersonalContext,
      team: team,
      chatSlice: chatSlice,
      scopeRoots: widget.scope.roots,
      cwd: widget.cwd,
      workspaceId: widget.workspaceId,
      toolsScopeId: widget.toolsScopeId,
    );

    if (_cacheKey != cacheKey || _cachedViews == null) {
      _cacheKey = cacheKey;
      _cachedViews = _buildViews(
        context,
        team: team,
        chatSlice: chatSlice,
      );
    }

    final panel = TabbedPanel(
      views: _cachedViews!,
      scopeId: widget.toolsScopeId,
    );
    final branchLabel = _optionalWorktreeBranch(context);
    if (branchLabel == null) return panel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WorktreeBreadcrumb(branch: branchLabel),
        Expanded(child: panel),
      ],
    );
  }

  String? _optionalWorktreeBranch(BuildContext context) {
    try {
      final state = context.read<WorktreeCubit>().state;
      if (!state.hasMultipleWorktrees) return null;
      for (final w in state.worktrees) {
        if (workspacePathsEqual(w.path, state.currentWorktreePath)) {
          return w.shortBranch;
        }
      }
    } on Object {
      // [WorktreeCubit] lives under the split pane, not above the right tools host.
    }
    return null;
  }

  List<ToolView> _buildViews(
    BuildContext context, {
    required TeamProfile? team,
    required RightToolsChatSlice chatSlice,
  }) {
    final l10n = context.l10n;
    final views = <ToolView>[];
    void maybeDismissDrawer() {
      if (widget.dismissDrawerOnAction) {
        Navigator.of(context).maybePop();
      }
    }

    if (!widget.isPersonalContext &&
        widget.preferences.membersVisible &&
        team != null) {
      final session = chatSlice.persistedSession;
      final runtimeMembers = session != null && session.members.isNotEmpty
          ? sessionRosterMembers(session, team)
          : runtimeRosterMembers(team);
      final members = [...runtimeMembers]
        ..sort((a, b) {
          if (TeamMemberNaming.isTeamLead(a)) return -1;
          if (TeamMemberNaming.isTeamLead(b)) return 1;
          return a.name.compareTo(b.name);
        });
      // Spec: session targets when present; else remembered workspace pins.
      // Empty session map falls back to remembered (hydrate edge case).
      final MemberTargetAssignments memberTargets;
      if (session != null && session.memberTargets.isNotEmpty) {
        memberTargets = session.memberTargets;
      } else {
        final workspace = context
            .read<ChatCubit>()
            .state
            .workspaces
            .where((w) => w.workspaceId == widget.workspaceId)
            .firstOrNull;
        memberTargets = rememberedMemberTargets(
          workspace?.memberTargetsByTeam ?? const {},
          team.id,
        );
      }
      views.add(
        ToolView(
          icon: Icons.groups_outlined,
          label: l10n.members,
          child: _ScopedMembersPanel(
            team: team,
            members: members,
            runtimeMembers: runtimeMembers,
            memberTargets: memberTargets,
            selectedMemberId: chatSlice.selectedMemberId,
            canViewDetail: chatSlice.hasActiveTab,
            workspaceId: widget.workspaceId,
            cwd: widget.cwd,
            scope: widget.scope,
            maybeDismissDrawer: maybeDismissDrawer,
          ),
        ),
      );
    }

    if (widget.preferences.fileTreeVisible) {
      views.add(
        ToolView(
          icon: Icons.folder_outlined,
          label: l10n.fileTree,
          child: FileTreePanel(
            key: const ValueKey('workspace-file-tree'),
            cubit: widget.fileTreeCubit,
            workContext: widget.workContext,
            workspaceId: widget.workspaceId,
          ),
        ),
      );
    }

    if (widget.preferences.gitVisible) {
      views.add(
        ToolView(
          icon: Icons.account_tree_outlined,
          label: l10n.sourceControl,
          child: GitSourceControlPanel(
            roots: widget.scope.roots,
            workContext: widget.workContext,
            workspaceId: widget.workspaceId,
          ),
        ),
      );
    }

    return views;
  }
}

class _ScopedMembersPanel extends StatefulWidget {
  const _ScopedMembersPanel({
    required this.team,
    required this.members,
    required this.runtimeMembers,
    required this.memberTargets,
    required this.selectedMemberId,
    required this.canViewDetail,
    required this.workspaceId,
    required this.cwd,
    required this.scope,
    required this.maybeDismissDrawer,
  });

  final TeamProfile team;
  final List<TeamMemberConfig> members;
  final List<TeamMemberConfig> runtimeMembers;
  final MemberTargetAssignments memberTargets;
  final String selectedMemberId;
  final bool canViewDetail;
  final String workspaceId;
  final String cwd;
  final WorkspaceToolsScopeState scope;
  final VoidCallback maybeDismissDrawer;

  @override
  State<_ScopedMembersPanel> createState() => _ScopedMembersPanelState();
}

class _ScopedMembersPanelState extends State<_ScopedMembersPanel> {
  List<RuntimeTarget> _runtimeTargets = const [];
  Future<void>? _targetsLoad;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _targetsLoad ??= _loadSelectableTargets();
  }

  Future<void> _loadSelectableTargets() async {
    try {
      final targets = await context
          .read<HomeTargetController>()
          .listSelectable();
      if (!mounted) return;
      setState(() => _runtimeTargets = targets);
    } on Object {
      // HomeTargetController unavailable in widget tests.
    }
  }

  @override
  Widget build(BuildContext context) {
    final presence = context
        .select<MemberPresenceCubit, Map<String, MemberPresence>>(
          (c) => c.state.presence,
        );
    final providersByCli = context
        .select<AppProviderCubit, Map<CliTool, List<AppProviderConfig>>>(
          (c) => c.state.providersByCli,
        );
    return MembersPanel(
      team: widget.team,
      members: widget.members,
      memberPresence: presence,
      providersByCli: providersByCli,
      selectedMemberId: widget.selectedMemberId,
      memberTargets: widget.memberTargets,
      runtimeTargets: _runtimeTargets,
      groupByMachine: widget.team.teamMode == TeamMode.mixed,
      onSelected: (id) => _onMemberRowTap(context, id),
      onSwitchTo: (id) => _switchToMember(context, id),
      onOpen: (id) => _openMember(context, id),
      onLaunchAll: widget.maybeDismissDrawer,
      canViewDetail: widget.canViewDetail,
      onViewDetail: (id) => _viewDetail(context, id),
      onOpenConfigDir: (id) => _openConfigDir(context, id),
    );
  }

  SessionWorkbenchView _activeWorkbenchView(ChatCubit chat) {
    final sessionId = chat.state.activeSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return SessionWorkbenchView.chat;
    }
    final tab = chat.tabStore.openTabBySessionId(sessionId);
    return tab?.workbenchView ?? SessionWorkbenchView.chat;
  }

  void _onMemberRowTap(BuildContext context, String id) {
    final chat = context.read<ChatCubit>();
    if (_activeWorkbenchView(chat) == SessionWorkbenchView.chat) {
      _switchToMember(context, id);
      return;
    }
    _openMember(context, id);
  }

  void _switchToMember(BuildContext context, String id) {
    context.read<ChatCubit>().selectMember(id);
    widget.maybeDismissDrawer();
  }

  void _openMember(BuildContext context, String id) {
    _switchToMember(context, id);
  }

  Future<void> _viewDetail(BuildContext context, String id) async {
    final member = widget.runtimeMembers.firstWhere((m) => m.id == id);
    final chatCubit = context.read<ChatCubit>();
    final activeTab = chatCubit.activeTab;
    final activeSessionId = chatCubit.state.activeSessionId;
    final activeSession = activeSessionId == null
        ? null
        : chatCubit.state.sessions
              .where((s) => s.sessionId == activeSessionId)
              .firstOrNull;
    await showMemberDetailDialog(
      context,
      workspaceId: widget.workspaceId,
      sessionId: activeTab?.info.id ?? '',
      team: widget.team,
      member: member,
      lifecycle: chatCubit.lifecycle,
      session: activeSession,
    );
    widget.maybeDismissDrawer();
  }

  Future<void> _openConfigDir(BuildContext context, String id) async {
    final member = widget.runtimeMembers.firstWhere((m) => m.id == id);
    final chatCubit = context.read<ChatCubit>();
    final activeTab = chatCubit.activeTab;
    final activeSessionId = chatCubit.state.activeSessionId;
    final session = activeSessionId == null
        ? null
        : chatCubit.state.sessions
              .where((s) => s.sessionId == activeSessionId)
              .firstOrNull;
    if (session == null) return;

    final cached = activeTab?.memberConfigDirs[id]?.trim();
    final launchCtx = WorkspaceLaunchContext(
      session: session,
      workspace: Workspace(
        workspaceId: widget.workspaceId,
        folders: widget.scope.effectiveFolders,
        createdAt: 0,
      ),
    );
    final workContext = await chatCubit.lifecycle.launchWorkContext(
      launchCtx,
      memberId: member.id,
    );
    final path = cached?.isNotEmpty == true
        ? cached!
        : (await MemberConfigInspector().inspect(
            workspaceId: widget.workspaceId,
            sessionId: activeTab?.info.id ?? '',
            team: widget.team,
            member: member,
            workContext: workContext,
            globalPresets: context.read<CliPresetsCubit>().state.presets,
            preferExpectedRuntimeDir: true,
          )).resolvedDir;
    if (!context.mounted || path.isEmpty) return;
    await openMemberConfigDirectory(
      context,
      path: path,
      workContext: workContext,
    );
    widget.maybeDismissDrawer();
  }
}

class _WorktreeBreadcrumb extends StatelessWidget {
  const _WorktreeBreadcrumb({required this.branch});

  final String branch;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 14,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              branch,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TpTextStyles.of(
                context,
              ).smSemiboldColored(cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
