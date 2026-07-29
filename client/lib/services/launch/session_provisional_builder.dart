import '../../models/app_session.dart';
import '../../models/simple_launch_identity.dart';
import '../../models/workspace.dart';
import '../../models/team_config.dart';

/// In-memory session used to stage the workbench before disk persistence.
AppSession buildProvisionalSession({
  required String sessionId,
  required Workspace workspace,
  CliTool? cli,
  SimpleLaunchIdentity? simpleIdentity,
  String? workingDirectory,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final folders = Workspace.foldersForPrimaryPath(
    workspace.folders,
    workingDirectory ?? '',
  );
  final identity = simpleIdentity ?? SimpleLaunchIdentity.resolve(cli: cli);

  return AppSession(
    sessionId: sessionId,
    workspaceId: workspace.workspaceId,
    folders: folders,
    display: '',
    profileId: '',
    cliTeamName: '',
    cli: identity.cli,
    provider: identity.provider,
    model: identity.model,
    effort: identity.effort,
    presetId: identity.presetId,
    members: const [],
    memberTargets: const {},
    launchState: AppSessionLaunchState.created,
    createdAt: now,
    updatedAt: now,
  );
}
