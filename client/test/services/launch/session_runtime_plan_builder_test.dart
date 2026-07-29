import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/simple_launch_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/services/launch/session_runtime_plan.dart';
import 'package:teampilot/services/launch/session_runtime_plan_builder.dart';

void main() {
  late Map<String, ConfigBundle> workspaceBundles;
  late SessionRuntimePlanBuilder builder;

  setUp(() {
    workspaceBundles = {};
    builder = SessionRuntimePlanBuilder(
      loadWorkspaceBundle: (workspaceId) async {
        return workspaceBundles[workspaceId] ?? const ConfigBundle();
      },
    );
  });

  test('simple plan uses the workspace bundle', () async {
    workspaceBundles['ws-1'] = const ConfigBundle(skillIds: ['ws']);

    final plan = await builder.buildSimple(
      workspaceId: 'ws-1',
      sessionId: 'sess-1',
      memberId: 'seat-1',
      identity: const SimpleLaunchIdentity(cli: CliTool.claude),
    );

    expect(plan.mode, SessionRuntimeMode.simple);
    expect(plan.workspaceId, 'ws-1');
    expect(plan.sessionId, 'sess-1');
    expect(plan.memberId, 'seat-1');
    expect(plan.teamId, isNull);
    expect(plan.runtimeBundle.skillIds, ['ws']);
    expect(plan.member.id, 'seat-1');
  });

  test('simple plan applies identity fields to the seat member', () async {
    final plan = await builder.buildSimple(
      workspaceId: 'ws-1',
      sessionId: 'sess-1',
      memberId: 'seat-1',
      identity: const SimpleLaunchIdentity(
        cli: CliTool.codex,
        provider: 'openai-official',
        model: 'gpt-5',
        effort: 'high',
        presetId: 'preset-1',
      ),
    );

    expect(plan.member.cli, CliTool.codex);
    expect(plan.member.provider, 'openai-official');
    expect(plan.member.model, 'gpt-5');
    expect(plan.member.effort, 'high');
    expect(plan.presetId, 'preset-1');
  });

  test('team plan merges team over workspace per seat', () async {
    workspaceBundles['ws-1'] = const ConfigBundle(skillIds: ['w']);

    const team = TeamProfile(id: 'team-1', name: 'Team', skillIds: ['t']);
    const member = TeamMemberConfig(
      id: 'team-lead',
      name: 'Lead',
      responsibilities: 'You are the lead',
    );
    final slot = teamRosterSlotForMember(team, member);

    final plan = await builder.buildTeamSeat(
      workspaceId: 'ws-1',
      sessionId: 'sess-1',
      team: team,
      slot: slot,
      member: member,
    );

    expect(plan.mode, SessionRuntimeMode.team);
    expect(plan.teamId, 'team-1');
    expect(plan.runtimeBundle.skillIds, ['t', 'w']);
    expect(plan.member.id, 'team-lead');
    expect(plan.member.responsibilities, 'You are the lead');
  });

  test('synthesized slot mirrors member overrides', () {
    const team = TeamProfile(id: 'team-1', name: 'Team');
    const member = TeamMemberConfig(
      id: 'team-lead',
      name: 'Lead',
      provider: 'openai-official',
      model: 'gpt-5',
    );

    final slot = teamRosterSlotForMember(team, member);

    expect(slot.id, 'team-lead');
    expect(slot.overrides.provider, 'openai-official');
    expect(slot.overrides.model, 'gpt-5');
  });

  test('team seat without a member synthesizes one from the slot', () async {
    const team = TeamProfile(id: 'team-1', name: 'Team');
    const slot = TeamRosterSlot(
      id: 'dev',
      expertKey: '',
      overrides: TeamRosterSlotOverrides(model: 'gpt-5'),
    );

    final plan = await builder.buildTeamSeat(
      workspaceId: 'ws-1',
      sessionId: 'sess-1',
      team: team,
      slot: slot,
    );

    expect(plan.member.id, 'dev');
    expect(plan.member.model, 'gpt-5');
  });
}
