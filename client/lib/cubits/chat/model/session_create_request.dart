import '../../../models/simple_launch_identity.dart';
import '../../../models/session_continue_overrides.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../repositories/session_repository.dart';

/// User intent to create a new conversation and surface it immediately.
class SessionCreateRequest {
  const SessionCreateRequest({
    required this.workspace,
    this.repo,
    this.cli,
    this.simpleIdentity,
    this.workingDirectory,
    this.emptyDisplayTitleFallback = 'New Chat',
    this.fixedSessionId,
    this.continueOverrides,
    this.preserveWorkbenchView = false,
  });

  final Workspace workspace;

  final SessionRepository? repo;
  final CliTool? cli;

  /// Simple launch: resolved identity (cli/provider/model/effort/expert/preset).
  final SimpleLaunchIdentity? simpleIdentity;
  final String? workingDirectory;
  final String emptyDisplayTitleFallback;

  /// When set, the staged session uses this id instead of a fresh UUID.
  final String? fixedSessionId;


  /// Session-level continue overrides (e.g. landing permission chip).
  final SessionContinueOverrides? continueOverrides;

  /// When true, keep the new tab on Chat instead of forcing Terminal on connect.
  final bool preserveWorkbenchView;
}
