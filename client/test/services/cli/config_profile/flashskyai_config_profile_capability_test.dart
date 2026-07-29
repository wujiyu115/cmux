import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';

void main() {
  test(
    'contributeLaunch returns FLASHSKYAI_CONFIG_DIR for valid member',
    () async {
      final base = await Directory.systemTemp.createTemp('flashskyai_cap_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });

      final fs = LocalFilesystem();
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      );
      const capability = FlashskyaiConfigProfileCapability();
      const member = TeamMemberConfig(id: 'm1', name: 'Member', model: 'test');

      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
      );

      final contribution = await capability.contributeLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          member: member,
          members: const [member],
          workingDirectory: '/workspace/workspace',
          paths: service,
          catalog: service,
        ),
      );

      final expectedDir = p.join(
        base.path,
        'workspace',
        'workspaces',
        'workspace-1',
        'sessions',
        'session-1',
        'runtime',
        'flashskyai',
      );
      expect(
        contribution.environment[FlashskyaiConfigProfileCapability
            .configDirEnvKey],
        expectedDir,
      );
    },
  );

}
