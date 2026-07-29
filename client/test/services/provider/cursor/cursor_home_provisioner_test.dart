import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/claude_credential_link_result.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider/cursor/cursor_cli_config_policy.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_provisioner.dart';
import 'package:teampilot/services/provider/cursor/cursor_provider_credentials_service.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CursorHomeProvisioner provisioner;
  late CursorProviderCredentialsService credentials;
  late CursorHomeLayout layout;
  const base = '/data/tp';

  const loggedInCliConfig = '''
{"authInfo":{"userId":"u1","authId":"a1"}}
''';

  const loggedInAuthJson = '''
{"accessToken":"at1","refreshToken":"rt1"}
''';

  Future<void> writeLoggedInProvider(String providerId) async {
    final providerHomePath = fs.pathContext.join(
      base,
      'providers',
      'cursor',
      providerId,
      'home',
    );
    await fs.writeString(layout.cliConfig(providerHomePath), loggedInCliConfig);
    await fs.writeString(layout.authJson(providerHomePath), loggedInAuthJson);
  }

  const member = TeamMemberConfig(
    id: 'planner',
    name: 'Planner',
    responsibilities: '只做代码审查',
  );

  setUp(() {
    fs = InMemoryFilesystem();
    layout = CursorHomeLayout(pathContext: fs.pathContext);
    credentials = CursorProviderCredentialsService(fs: fs, basePath: base);
    provisioner = CursorHomeProvisioner(fs: fs, credentials: credentials);
  });


  group('CursorHomeProvisioner', () {
    test(
      'provision mirrors real home passthrough when realHomeRoot set',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';
        const realHome = '/home/user';
        await fs.ensureDir(realHome);
        await fs.ensureDir(fs.pathContext.join(realHome, '.pub-cache'));

        await provisioner.provision(
          memberHome: memberHome,
          providerId: null,
          member: member,
          forceTeamLeadDelegateMode: false,
          mixed: false,
          realHomeRoot: realHome,
        );

        expect(
          await fs.readSymlinkTarget(
            fs.pathContext.join(memberHome, '.pub-cache'),
          ),
          fs.pathContext.join(realHome, '.pub-cache'),
        );
        expect(
          (await fs.stat(layout.cursorDir(memberHome))).isDirectory,
          isTrue,
        );
      },
    );

    test('provision writes role.mdc in simple mode', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        forceTeamLeadDelegateMode: false,
        mixed: false,
      );

      final roleRule = await fs.readString(layout.roleRule(memberHome));
      expect(roleRule, startsWith('---\nalwaysApply: true\n---\n'));
      expect(roleRule, contains('只做代码审查'));
      expect((await fs.stat(layout.hooksConfig(memberHome))).isFile, isFalse);
      expect((await fs.stat(layout.mcpConfig(memberHome))).isFile, isFalse);
    });

    test(
      'provision seeds hasShownAgentCommandTip in isolated agent-cli-state',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';

        await provisioner.provision(
          memberHome: memberHome,
          providerId: null,
          member: member,
          forceTeamLeadDelegateMode: false,
          mixed: false,
        );

        final raw = await fs.readString(layout.agentCliState(memberHome));
        expect(raw, isNotNull);
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        expect(decoded['version'], 1);
        expect(decoded['hasShownAgentCommandTip'], isTrue);
      },
    );

    test(
      'provision merges hasShownAgentCommandTip into existing agent-cli-state',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';
        await fs.ensureDir(layout.cursorDir(memberHome));
        await fs.writeString(
          layout.agentCliState(memberHome),
          jsonEncode({
            'version': 1,
            'hasClearedLegacyStatsigFields': true,
          }),
        );

        await provisioner.provision(
          memberHome: memberHome,
          providerId: null,
          member: member,
          forceTeamLeadDelegateMode: false,
          mixed: false,
        );

        final raw = await fs.readString(layout.agentCliState(memberHome));
        expect(raw, isNotNull);
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        expect(decoded['hasShownAgentCommandTip'], isTrue);
        expect(decoded['hasClearedLegacyStatsigFields'], isTrue);
      },
    );


    test('provision merges cli-config Mcp allowlist in mixed mode', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: null,
        member: member,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      final allow = (cliConfig['permissions']! as Map)['allow'] as List;
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
    });

    test(
      'provision syncs auth when provider has logged-in credentials',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';
        final providerHomePath = fs.pathContext.join(
          base,
          'providers',
          'cursor',
          'work',
          'home',
        );
        await writeLoggedInProvider('work');

        await provisioner.provision(
          memberHome: memberHome,
          providerId: 'work',
          member: member,
          forceTeamLeadDelegateMode: false,
          mixed: true,
        );

        expect(
          fs.symlinks[layout.cliConfig(memberHome)],
          layout.cliConfig(providerHomePath),
        );
        expect((await fs.stat(layout.authJson(memberHome))).isFile, isTrue);
      },
    );




    test('ignores missing auth sync result without throwing', () async {
      const memberHome = '/data/tp/members/planner/cursor/home';

      await provisioner.provision(
        memberHome: memberHome,
        providerId: 'missing-provider',
        member: member,
        forceTeamLeadDelegateMode: false,
        mixed: true,
      );

      expect((await fs.stat(layout.cliConfig(memberHome))).isFile, isTrue);
      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      final allow = (cliConfig['permissions']! as Map)['allow'] as List;
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
    });

    test(
      'syncAuthToMemberHome still returns missing for empty provider store',
      () async {
        const memberHome = '/data/tp/members/planner/cursor/home';
        final result = await credentials.syncAuthToMemberHome(
          'empty',
          memberHome,
        );
        expect(result, CredentialLinkResult.missing);
      },
    );
  });
}
