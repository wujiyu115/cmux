import 'dart:async';
import 'package:shared_ui/shared_ui.dart';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/session_preferences_cubit.dart';
import '../../../cubits/workspace_landing_context_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_session.dart';
import '../../../models/landing_launch_context.dart';
import '../../../models/workspace.dart';
import '../../../models/launch_profile_kind.dart';
import '../../../pages/home_workspace/home_workspace_route.dart';
import '../../../repositories/session_repository.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../../../utils/logging/logger.dart';
import '../../../widgets/app_toast/app_toast.dart';
import 'workspace_config_workspace.dart';
import 'workspace_section.dart';
import 'workspace_split_pane.dart';
import 'workspace_config_section.dart';
import 'workspace_route_active_scope.dart';
import 'workspace_session_actions.dart';

/// Workspace work page with conversations + manage panes.
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({required this.workspaceId, super.key});

  final String workspaceId;

  String get tabKey => workspaceId;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late WorkspaceSection _section = WorkspaceSection.conversations;
  var _visitedManage = false;
  Widget? _frozenPage;
  bool _wasRouteActive = false;
  String? _lastScopeView;
  bool _activationScheduled = false;
  String? _lastSyncedRouteSession;
  bool _sessionSyncScheduled = false;

  WorkspaceRouteActiveScope? _readScope(BuildContext context) {
    return context.getInheritedWidgetOfExactType<WorkspaceRouteActiveScope>();
  }

  WorkspaceConfigSection _configSection(BuildContext context) =>
      _readScope(context)?.configSection ?? WorkspaceConfigSection.settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _readScope(context);
    final active = scope?.routeActive ?? true;
    final view = scope?.view;
    if (active && !_wasRouteActive) {
      _scheduleActivation();
    }
    if (active) {
      final nextSection = _sectionFromRoute(view);
      // Always resync on tab reactivation: inactive slots force view=null in
      // the scope, and selecting a bare workspace route must not leave a stale
      // manage section with a broken back affordance.
      final shouldSync =
          !_wasRouteActive || view != _lastScopeView || nextSection != _section;
      if (shouldSync) {
        setState(() {
          _section = nextSection;
          if (_section == WorkspaceSection.manage) _visitedManage = true;
        });
      }
      _lastScopeView = view;
    }
    _wasRouteActive = active;
    _syncProfileFromRoute();
    _syncSessionFromRoute();
  }

  void _syncProfileFromRoute() {
    final location = GoRouterState.of(context).uri.toString();
    final routeProfile = HomeWorkspaceRoute.profile(location)?.trim() ?? '';
    if (routeProfile.isEmpty) return;
    final cubit = context.read<WorkspaceLandingContextCubit>();
    final ctx = cubit.state.context;
    final current = ctx.isPersonal ? '' : (ctx.teamId ?? '');
    if (current == routeProfile) return;
    final launchProfiles = context.read<LaunchProfileCubit>();
    final profile = launchProfiles.byId(routeProfile);
    if (profile == null) return;
    final next = LandingLaunchContext(
      isPersonal: false,
      teamId: profile.id,
    );
    cubit.update(next);
  }

  void _syncSessionFromRoute() {
    final location = GoRouterState.of(context).uri.toString();
    final sessionId = HomeWorkspaceRoute.session(location);
    if (sessionId == _lastSyncedRouteSession) return;
    _lastSyncedRouteSession = sessionId;
    if (sessionId == null) return;
    if (_sessionSyncScheduled) return;
    _sessionSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sessionSyncScheduled = false;
      if (!mounted) return;
      unawaited(_applySessionFromRoute(sessionId));
    });
  }

  Future<void> _applySessionFromRoute(String sessionId) async {
    final workspace = context.read<ChatCubit>().state.workspaces
        .where((w) => w.workspaceId == widget.workspaceId)
        .firstOrNull;
    if (workspace == null) {
      _clearSessionQuery();
      return;
    }

    await context.read<ChatCubit>().ensureSessionsForWorkspace(
      widget.workspaceId,
    );
    if (!mounted) return;

    final session = await _resolveSessionForDeepLink(sessionId);
    if (!mounted) return;
    if (session == null) {
      appLogger.w(
        '[session-deep-link] session not found '
        'session=$sessionId workspace=${widget.workspaceId}',
      );
      _clearSessionQuery();
      return;
    }

    await openWorkspaceSessionTab(context, workspace, session);
    if (!mounted) return;
    _clearSessionQuery();
  }

  Future<AppSession?> _resolveSessionForDeepLink(String sessionId) async {
    final fromState = context
        .read<ChatCubit>()
        .state
        .sessions
        .where(
          (s) =>
              s.sessionId == sessionId && s.workspaceId == widget.workspaceId,
        )
        .firstOrNull;
    if (fromState != null) return fromState;

    final loaded = await context
        .read<SessionRepository>()
        .loadSessionsForWorkspace(widget.workspaceId);
    return loaded.where((s) => s.sessionId == sessionId).firstOrNull;
  }

  void _clearSessionQuery() {
    final current = GoRouterState.of(context).uri.toString();
    final next = HomeWorkspaceRoute.locationWithoutSession(current);
    if (current == next) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (GoRouterState.of(context).uri.toString() != current) return;
      context.go(next);
    });
  }

  WorkspaceSection _sectionFromRoute(String? view) {
    if (view == 'manage') {
      return WorkspaceSection.manage;
    }
    return WorkspaceSection.conversations;
  }

  void _scheduleActivation() {
    if (_activationScheduled) return;
    _activationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activationScheduled = false;
      if (!mounted) return;
      if (!(_readScope(context)?.routeActive ?? false)) return;
      _activateRoute();
    });
  }

  void _invalidateFrozenPage() => _frozenPage = null;

  void _activateRoute() {
    context.read<ChatCubit>().activateWorkspaceTab(
      workspaceTabKey: widget.tabKey,
      scopeSessionsToSelectedTeam: false,
    );
    unawaited(
      context.read<ChatCubit>().ensureSessionsForWorkspace(widget.workspaceId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<WorkspaceRouteActiveScope>();
    final routeActive = scope?.routeActive ?? true;
    final body = routeActive
        ? _buildAndCacheLivePage(context)
        : (_frozenPage ?? const SizedBox.shrink());
    return BlocListener<ChatCubit, ChatState>(
      listenWhen: (previous, next) {
        if (previous.workspaces == next.workspaces) return false;
        return _findWorkspace(previous.workspaces, widget.workspaceId) !=
            _findWorkspace(next.workspaces, widget.workspaceId);
      },
      listener: (context, state) {
        _invalidateFrozenPage();
        if (routeActive && mounted) setState(() {});
      },
      child: body,
    );
  }

  Widget _buildAndCacheLivePage(BuildContext context) {
    final built = _buildLivePage(context);
    _frozenPage = built;
    return built;
  }

  Widget _buildLivePage(BuildContext context) {
    final l10n = context.l10n;

    final workspace = context.select<ChatCubit, Workspace?>(
      (c) => _findWorkspace(c.state.workspaces, widget.workspaceId),
    );

    if (workspace == null) {
      return WorkspacePageCardShell(
        chrome: WorkspacePageChrome.workspace,
        child: _MissingWorkspace(label: l10n.homeWorkspaceEmptyWorkspaces),
      );
    }

    // Heavy body mounts at the tab-slot [WorkspaceTabDeferredMount]; this
    // page paints immediately once that defer reveals.
    // App-global status bar lives on HomeShell (GlobalResourceManagerHost).
    return WorkspacePageCardShell(
      chrome: WorkspacePageChrome.workspace,
      child: _buildCardBody(workspace: workspace),
    );
  }

  Widget _buildCardBody({required Workspace workspace}) {
    final showManage = _section == WorkspaceSection.manage;
    return Stack(
      fit: StackFit.expand,
      children: [
        TpKeepAliveLayer(
          active: !showManage,
          child: TickerMode(
            enabled: !showManage,
            child: IgnorePointer(
              ignoring: showManage,
              child: WorkspaceSplitPane(
                key: ValueKey('conversations-${widget.tabKey}'),
                workspace: workspace,
                tabScopeId: widget.tabKey,
              ),
            ),
          ),
        ),
        if (_visitedManage)
          TpKeepAliveLayer(
            active: showManage,
            child: TickerMode(
              enabled: showManage,
              child: IgnorePointer(
                ignoring: !showManage,
                child: WorkspaceConfigPanel(
                  workspace: workspace,
                  section: _configSection(context),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static Workspace? _findWorkspace(List<Workspace> workspaces, String id) {
    for (final p in workspaces) {
      if (p.workspaceId == id) return p;
    }
    return null;
  }
}

class _MissingWorkspace extends StatelessWidget {
  const _MissingWorkspace({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(label, style: TpTextStyles.of(context).mutedMd),
    );
  }
}
