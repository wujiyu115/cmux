import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/compose/compose_landing_bundle.dart';

void main() {
  group('slashBundleForLanding', () {
    test('personal draft uses the workspace bundle alone', () {
      final bundle = slashBundleForLanding(
        draft: const LandingLaunchContext(isPersonal: true),
        workspace: const ConfigBundle(
          skillIds: ['ws-skill'],
          pluginIds: ['ws-plugin'],
        ),
      );
      expect(bundle.skillIds, ['ws-skill']);
      expect(bundle.pluginIds, ['ws-plugin']);
    });

    test('team draft merges team config over the workspace bundle', () {
      const team = TeamProfile(
        id: 't1',
        name: 'Team',
        skillIds: ['team-skill'],
        pluginIds: ['team-plugin'],
      );
      final bundle = slashBundleForLanding(
        draft: const LandingLaunchContext(isPersonal: false, teamId: 't1'),
        team: team,
        workspace: const ConfigBundle(skillIds: ['ws-skill']),
      );
      expect(bundle.skillIds, ['team-skill', 'ws-skill']);
      expect(bundle.pluginIds, ['team-plugin']);
    });

    test('team draft without a resolved team yields workspace-only', () {
      final bundle = slashBundleForLanding(
        draft: const LandingLaunchContext(
          isPersonal: false,
          teamId: 't-missing',
        ),
        workspace: const ConfigBundle(skillIds: ['ws-skill']),
      );
      expect(bundle.skillIds, ['ws-skill']);
      expect(bundle.pluginIds, isEmpty);
    });
  });
}
