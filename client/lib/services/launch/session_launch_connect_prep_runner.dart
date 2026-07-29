import 'package:flutter/foundation.dart';

import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logging/logger.dart';
import 'session_tab_connect_prep.dart';

typedef ScheduleShellConnectFn =
    void Function({
      required int generation,
      required ChatTab tab,
      required AppSession session,
      required TerminalSession shell,
      required SessionOpenRequest request,
      required bool launched,
      required Workspace? workspace,
      VoidCallback? onFinally,
    });

typedef RollbackStagedLaunchFn =
    void Function({
      required ChatTab tab,
      required String sessionId,
      required SessionOpenRequest request,
      required String message,
    });

/// Runs async tab-connect prep for new, existing, and deferred team tabs.
class SessionLaunchConnectPrepRunner {
  SessionLaunchConnectPrepRunner({
    required SessionLaunchHost host,
    required SessionTabConnectPrepCallbacks prepCallbacks,
    required bool Function(SessionOpenRequest request) shouldAutoConnect,
    required ScheduleShellConnectFn scheduleShellConnect,
    required RollbackStagedLaunchFn rollbackStagedLaunch,
  }) : _host = host,
       _prepCallbacks = prepCallbacks,
       _shouldAutoConnect = shouldAutoConnect,
       _scheduleShellConnect = scheduleShellConnect,
       _rollbackStagedLaunch = rollbackStagedLaunch;

  final SessionLaunchHost _host;
  final SessionTabConnectPrepCallbacks _prepCallbacks;
  final bool Function(SessionOpenRequest request) _shouldAutoConnect;
  final ScheduleShellConnectFn _scheduleShellConnect;
  final RollbackStagedLaunchFn _rollbackStagedLaunch;

  Future<void> prepareNewTabConnect({
    required int generation,
    required ChatTab tab,
    required AppSession session,
    required SessionOpenRequest request,
    required Workspace? workspace,
    required bool connect,
  }) async {
    try {
      final prep = await runSessionTabConnectPrep(
        callbacks: _prepCallbacks,
        generation: generation,
        tab: tab,
        session: session,
        request: request,
        workspace: workspace,
      );
      if (prep == null) return;

      if (!connect) {
        _host.updateTabRunning(prep.launchSession.sessionId);
        return;
      }
      final launched =
          prep.launchSession.launchState == AppSessionLaunchState.started;
      _scheduleShellConnect(
        generation: generation,
        tab: tab,
        session: prep.launchSession,
        shell: prep.shell,
        request: request,
        launched: launched,
        workspace: workspace,
      );
    } on Object catch (e, st) {
      await _handlePrepFailure(
        error: e,
        stackTrace: st,
        logLabel: 'prepare new tab failed',
        tab: tab,
        session: session,
        request: request,
        generation: generation,
      );
    }
  }

  Future<void> prepareExistingTabConnect({
    required int generation,
    required ChatTab tab,
    required SessionOpenRequest request,
    required bool connect,
    required Workspace? Function(String workspaceId) workspaceById,
  }) async {
    final session = request.session;
    final workspace = request.workspace ?? workspaceById(session.workspaceId);
    if (workspace == null) return;

    try {
      final prep = await runSessionTabConnectPrep(
        callbacks: _prepCallbacks,
        generation: generation,
        tab: tab,
        session: session,
        request: request,
        workspace: workspace,
      );
      if (prep == null) return;

      final launchSession = prep.launchSession;
      final shell = prep.shell;
      final state = _host.state;

      if (shell.isRunning || shell.isConnecting) {
        _host.updateTabRunning(tab.info.id);
        if (state.sessionConnectingId == launchSession.sessionId) {
          _host.finishSessionConnect(launchSession.sessionId);
        }
        return;
      }
      if (tab.membersPendingConnect.contains(prep.resolved.memberId)) return;

      if (!connect) {
        _host.updateTabRunning(tab.info.id);
        return;
      }

      if (_shouldAutoConnect(request) &&
          state.sessionConnectingId != launchSession.sessionId) {
        _host.beginSessionConnect(launchSession.sessionId);
      }

      tab.membersPendingConnect.add(prep.resolved.memberId);
      final launched =
          launchSession.launchState == AppSessionLaunchState.started;
      _scheduleShellConnect(
        generation: generation,
        tab: tab,
        session: launchSession,
        shell: shell,
        request: request,
        launched: launched,
        workspace: workspace,
        onFinally: () =>
            tab.membersPendingConnect.remove(prep.resolved.memberId),
      );
    } on Object catch (e, st) {
      await _handlePrepFailure(
        error: e,
        stackTrace: st,
        logLabel: 'prepare existing tab failed',
        tab: tab,
        session: session,
        request: request,
        generation: generation,
      );
    }
  }

  Future<void> _handlePrepFailure({
    required Object error,
    required StackTrace stackTrace,
    required String logLabel,
    required ChatTab tab,
    required AppSession session,
    required SessionOpenRequest request,
    required int generation,
  }) async {
    appLogger.e(
      '[session-launch] $logLabel session=${session.sessionId}: $error',
      error: error,
      stackTrace: stackTrace,
    );
    if (_prepCallbacks.launchStillValid(tab, generation)) {
      if (request.persistParams != null) {
        _rollbackStagedLaunch(
          tab: tab,
          sessionId: session.sessionId,
          request: request,
          message: error.toString(),
        );
      } else {
        _host.failSessionConnect(session.sessionId, error.toString());
      }
    }
  }
}
