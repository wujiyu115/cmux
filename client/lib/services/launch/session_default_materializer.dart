import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/model/session_open_status.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import 'session_launch_workspace_index.dart';

typedef SessionOpenFn = Future<SessionOpenStatus> Function(SessionOpenRequest);

/// Creates and opens the workspace's first session when the tab store is empty.
class SessionDefaultMaterializer {
  SessionDefaultMaterializer({
    required SessionLaunchHost host,
    required SessionOpenFn openSession,
    required SessionLaunchWorkspaceIndex Function() workspaceIndex,
    required bool Function() isTabsEmpty,
  }) : _host = host,
       _openSession = openSession,
       _workspaceIndex = workspaceIndex,
       _isTabsEmpty = isTabsEmpty;

  final SessionLaunchHost _host;
  final SessionOpenFn _openSession;
  final SessionLaunchWorkspaceIndex Function() _workspaceIndex;
  final bool Function() _isTabsEmpty;

  Future<void> materializePersonalSession(
    Workspace workspace,
    SessionRepository repo, {
    required bool connectImmediately,
    CliTool? cliOverride,
  }) async {
    if (!_isTabsEmpty()) return;

    final index = _workspaceIndex();
    final existingSession = index.firstForPersonalWorkspace(
      workspace.workspaceId,
    );
    if (existingSession != null) {
      await _openSession(
        SessionOpenRequest(
          session: existingSession,
          workspace: workspace,
          repo: repo,
          connectImmediately: connectImmediately,
        ),
      );
      return;
    }

    final cli = cliOverride ?? CliTool.claude;

    final session = await repo.createSession(workspace.workspaceId, cli: cli);
    if (_host.isClosed) return;
    await _host.loadWorkspaceData(repo);
    if (_host.isClosed) return;
    await _openSession(
      SessionOpenRequest(
        session: session,
        workspace: workspace,
        repo: repo,
        connectImmediately: connectImmediately,
      ),
    );
  }
}
