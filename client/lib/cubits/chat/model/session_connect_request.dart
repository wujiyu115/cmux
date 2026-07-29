import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';

/// Target for [SessionLaunchService.connectWorkspaceSession].
sealed class SessionConnectRequest {}

/// Connect the active Simple (unteamed) workspace session.
final class PersonalSessionConnect extends SessionConnectRequest {
  PersonalSessionConnect({required this.workspaceId, this.cliOverride});

  final String workspaceId;
  final CliTool? cliOverride;
}

/// Connect an already-open review tab for a specific persisted session.
///
/// Used by session history review submit — must resume [session], not
/// materialize a new workspace default or pick another session.
final class ExistingSessionConnect extends SessionConnectRequest {
  ExistingSessionConnect({
    required this.session,
    this.workspace,
    this.preserveWorkbenchView = false,
  });

  final AppSession session;
  final Workspace? workspace;

  /// When true, connect without forcing the tab onto Terminal (Chat continue).
  final bool preserveWorkbenchView;
}
