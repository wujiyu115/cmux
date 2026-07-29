import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
import '../../pages/home_workspace/workspace/member_config_directory_opener.dart';
import '../../services/storage/home_target_controller.dart';
import '../../services/storage/runtime_context.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../utils/team/team_member_naming.dart';
import '../../utils/workspace/workspace_path_utils.dart';
import '../git/git_source_control_panel.dart';
import 'file_tree_panel.dart';
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
