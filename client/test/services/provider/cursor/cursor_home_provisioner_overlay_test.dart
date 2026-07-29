import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider/cursor/cursor_cli_config_policy.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_provisioner.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CursorHomeProvisioner provisioner;
  late CursorHomeLayout layout;

  const memberHome = '/data/tp/members/planner/cursor/home';

  const member = TeamMemberConfig(
    id: 'planner',
    name: 'Planner',
    responsibilities: '只做代码审查',
  );

  setUp(() {
    fs = InMemoryFilesystem();
    layout = CursorHomeLayout(pathContext: fs.pathContext);
    provisioner = CursorHomeProvisioner(fs: fs);
  });

  group('CursorHomeProvisioner.provisionOverlayOnly', () {
    test('preserves member-private paths and merges cli-config.json', () async {
      final chatsPath = fs.pathContext.join(
        layout.cursorDir(memberHome),
        'chats',
        'ws-hash',
        'chat-1',
        'state.json',
      );
      final projectsPath = fs.pathContext.join(
        layout.cursorDir(memberHome),
        'projects',
        'my-project',
        '.workspace-trusted',
      );
      await fs.writeString(chatsPath, '{"chat":"preserved"}');
      await fs.writeString(projectsPath, 'trusted');
      await fs.writeString(
        layout.cliConfig(memberHome),
        '{"authInfo":{"userId":"u1","authId":"a1"}}',
      );

      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        forceTeamLeadDelegateMode: false,
      );

      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      expect(cliConfig['authInfo'], isNotNull);

      expect(await fs.readString(chatsPath), '{"chat":"preserved"}');
      expect(await fs.readString(projectsPath), 'trusted');
    });

    test('uses cliConfigJson as merge base when provided', () async {
      const baseJson = '''
{"serverConfigCache":{"key":"cached"},"permissions":{"allow":["Mcp(existing:*)"]}}
''';

      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        forceTeamLeadDelegateMode: false,
        cliConfigJson: baseJson,
      );

      final cliConfig =
          jsonDecode((await fs.readString(layout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      expect(cliConfig['serverConfigCache'], isNotNull);
      final allow = (cliConfig['permissions']! as Map)['allow'] as List;
      expect(allow, contains('Mcp(existing:*)'));
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
    });

    test('writes role.mdc and cli-config without an mcp.json', () async {
      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        forceTeamLeadDelegateMode: false,
      );

      expect((await fs.stat(layout.roleRule(memberHome))).isFile, isTrue);
      expect((await fs.stat(layout.mcpConfig(memberHome))).isFile, isFalse);
      expect((await fs.stat(layout.cliConfig(memberHome))).isFile, isTrue);
    });

    test('does not write auth.json', () async {
      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        forceTeamLeadDelegateMode: false,
      );

      expect((await fs.stat(layout.authJson(memberHome))).isFile, isFalse);
    });
  });
}
