import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/chat/chat_tab_store.dart';
import '../../cubits/chat/model/chat_state.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/model/session_open_status.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../services/terminal/terminal_session.dart';
import 'launch_operation.dart';
import 'launch_outcome.dart';
import 'session_default_materializer.dart';
import 'session_launch_connect_prep_runner.dart';
import 'session_launch_pipeline.dart';
import 'session_launch_workspace_index.dart';
import 'session_tab_connect_prep.dart';
import 'session_tab_surface_coordinator.dart';

/// Dependencies required to wire tab surface, materializer, and pipeline.
class SessionLaunchBundleDeps {
  const SessionLaunchBundleDeps({
    required this.host,
    required this.tabStore,
    required this.state,
    required this.workspaceIndex,
    required this.workspaceById,
    required this.prepCallbacks,
    required this.shouldAutoConnect,
    required this.scheduleShellConnect,
    required this.rollbackStagedLaunch,
    required this.disconnectSession,
    required this.activeTab,
    required this.isTabsEmpty,
    required this.uuid,
  });

  final SessionLaunchHost host;
  final ChatTabStore tabStore;
  final ChatState Function() state;
  final SessionLaunchWorkspaceIndex Function() workspaceIndex;
  final Workspace? Function(String workspaceId) workspaceById;
  final SessionTabConnectPrepCallbacks prepCallbacks;
  final bool Function(SessionOpenRequest request) shouldAutoConnect;
  final void Function({
    required int generation,
    required ChatTab tab,
    required AppSession session,
    required TerminalSession shell,
    required SessionOpenRequest request,
    required bool launched,
    required Workspace? workspace,
    VoidCallback? onFinally,
  })
  scheduleShellConnect;
  final void Function({
    required ChatTab tab,
    required String sessionId,
    required SessionOpenRequest request,
    required String message,
  })
  rollbackStagedLaunch;
  final void Function() disconnectSession;
  final ChatTab? Function() activeTab;
  final bool Function() isTabsEmpty;
  final Uuid uuid;
}

/// Composition root for launch pipeline collaborators.
class SessionLaunchBundle {
  SessionLaunchBundle._({
    required this.prepRunner,
    required this.tabSurface,
    required this.materializer,
    required this.pipeline,
    required this.openSession,
  });

  final SessionLaunchConnectPrepRunner prepRunner;
  final SessionTabSurfaceCoordinator tabSurface;
  final SessionDefaultMaterializer materializer;
  final SessionLaunchPipeline pipeline;
  final Future<SessionOpenStatus> Function(SessionOpenRequest request)
  openSession;

  factory SessionLaunchBundle.create(SessionLaunchBundleDeps deps) {
    late final SessionLaunchPipeline pipeline;

    Future<SessionOpenStatus> openSession(SessionOpenRequest request) async {
      final outcome = await pipeline.run(OpenSessionOperation(request));
      return switch (outcome) {
        LaunchOpened(:final status) => status,
        _ => SessionOpenStatus.opened,
      };
    }

    final prepRunner = SessionLaunchConnectPrepRunner(
      host: deps.host,
      prepCallbacks: deps.prepCallbacks,
      shouldAutoConnect: deps.shouldAutoConnect,
      scheduleShellConnect: deps.scheduleShellConnect,
      rollbackStagedLaunch: deps.rollbackStagedLaunch,
    );

    final tabSurface = SessionTabSurfaceCoordinator(
      host: deps.host,
      tabStore: deps.tabStore,
      state: deps.state,
      workspaceById: deps.workspaceById,
      shouldAutoConnect: deps.shouldAutoConnect,
      prepareNewTabConnect: prepRunner.prepareNewTabConnect,
      prepareExistingTabConnect:
          ({
            required int generation,
            required ChatTab tab,
            required SessionOpenRequest request,
            required bool connect,
          }) => prepRunner.prepareExistingTabConnect(
            generation: generation,
            tab: tab,
            request: request,
            connect: connect,
            workspaceById: deps.workspaceById,
          ),
    );

    final materializer = SessionDefaultMaterializer(
      host: deps.host,
      openSession: openSession,
      workspaceIndex: deps.workspaceIndex,
      isTabsEmpty: deps.isTabsEmpty,
    );

    pipeline = SessionLaunchPipeline(
      host: deps.host,
      tabStore: deps.tabStore,
      state: deps.state,
      workspaceIndex: deps.workspaceIndex,
      tabSurface: tabSurface,
      materializer: materializer,
      disconnectSession: deps.disconnectSession,
      activeTab: deps.activeTab,
      uuid: deps.uuid,
    );

    return SessionLaunchBundle._(
      prepRunner: prepRunner,
      tabSurface: tabSurface,
      materializer: materializer,
      pipeline: pipeline,
      openSession: openSession,
    );
  }
}
