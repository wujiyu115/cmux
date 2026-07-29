import '../../models/config_bundle.dart';
import '../../models/landing_launch_context.dart';
import '../../models/team_config.dart';
import '../launch/layered_config_bundle.dart';

/// Slash enable-list for Landing / review compose.
///
/// Team drafts merge the team config over the workspace bundle; personal
/// drafts use the workspace bundle alone. Does not install deps.
ConfigBundle slashBundleForLanding({
  required LandingLaunchContext draft,
  TeamProfile? team,
  required ConfigBundle workspace,
}) {
  if (!draft.isPersonal) {
    final teamBundle = team == null
        ? const ConfigBundle()
        : ConfigBundle(
            skillIds: team.skillIds,
            pluginIds: team.pluginIds,
            mcpServerIds: team.mcpServerIds,
          );
    return LayeredConfigBundle.merge(team: teamBundle, workspace: workspace);
  }

  return LayeredConfigBundle.merge(workspace: workspace);
}
