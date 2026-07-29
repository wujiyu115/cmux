import '../../models/config_bundle.dart';
import '../../models/simple_launch_identity.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../../repositories/workspace_project_config_repository.dart';
import 'layered_config_bundle.dart';
import 'session_runtime_plan.dart';

/// Maps a roster [TeamMemberConfig] to a [TeamRosterSlot] for plan building.
///
/// Prefers an existing [TeamProfile.roster] entry; otherwise synthesizes a slot
/// from member override fields only.
TeamRosterSlot teamRosterSlotForMember(
  TeamProfile team,
  TeamMemberConfig member,
) {
  for (final slot in team.roster) {
    if (slot.id == member.id) return slot;
  }
  return TeamRosterSlot(
    id: member.id,
    expertKey: '',
    overrides: TeamRosterSlotOverrides(
      provider: member.provider,
      model: member.model,
      effort: member.effort,
      extraArgs: member.extraArgs,
      cli: member.cli,
      replicas: member.replicas,
      capabilities: member.capabilities,
      activePresetId: member.activePresetId,
    ),
    joinedAt: member.joinedAt,
  );
}

/// Builds a per-seat [SessionRuntimePlan] from the workspace bundle (+ team).
class SessionRuntimePlanBuilder {
  SessionRuntimePlanBuilder({
    Future<ConfigBundle> Function(String workspaceId)? loadWorkspaceBundle,
    WorkspaceProjectConfigRepository? workspaceProjectConfig,
  }) : _loadWorkspaceBundle =
           loadWorkspaceBundle ??
           ((workspaceId) async {
             final repo = workspaceProjectConfig;
             if (repo == null) {
               throw StateError(
                 'SessionRuntimePlanBuilder requires loadWorkspaceBundle '
                 'or workspaceProjectConfig',
               );
             }
             final config = await repo.load(workspaceId);
             return config.bundle;
           });

  final Future<ConfigBundle> Function(String workspaceId) _loadWorkspaceBundle;

  /// Simple (unteamed) seat.
  ///
  /// [identity] is the session-pinned launch identity and owns the CLI /
  /// provider / model — without it, staging falls back to Claude and
  /// Cursor / Codex resume breaks.
  Future<SessionRuntimePlan> buildSimple({
    required String workspaceId,
    required String sessionId,
    required String memberId,
    SimpleLaunchIdentity? identity,
  }) async {
    final workspaceBundle = await _loadWorkspaceBundle(workspaceId);
    final base = TeamMemberConfig(id: memberId, name: memberId);
    final member = identity?.applyToMember(base) ?? base;

    return SessionRuntimePlan(
      mode: SessionRuntimeMode.simple,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      presetId: identity?.presetId,
      runtimeBundle: LayeredConfigBundle.merge(workspace: workspaceBundle),
      member: member,
    );
  }

  /// One team roster seat: merge team > workspace.
  ///
  /// When [member] is provided (materialized connect seat) it becomes
  /// [SessionRuntimePlan.member] so the role prompt / CLI come from the team
  /// member.
  Future<SessionRuntimePlan> buildTeamSeat({
    required String workspaceId,
    required String sessionId,
    required TeamProfile team,
    required TeamRosterSlot slot,
    String? presetId,
    TeamMemberConfig? member,
  }) async {
    final workspaceBundle = await _loadWorkspaceBundle(workspaceId);
    final seatMember =
        member ??
        TeamMemberConfig(
          id: slot.id,
          name: slot.id,
          provider: slot.overrides.provider,
          model: slot.overrides.model,
          effort: slot.overrides.effort,
          extraArgs: slot.overrides.extraArgs,
          cli: slot.overrides.cli,
          replicas: slot.overrides.replicas,
          capabilities: slot.overrides.capabilities,
          activePresetId: slot.overrides.activePresetId,
          joinedAt: slot.joinedAt,
        );

    return SessionRuntimePlan(
      mode: SessionRuntimeMode.team,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: slot.id,
      teamId: team.id,
      presetId: presetId,
      runtimeBundle: LayeredConfigBundle.merge(
        team: team.bundle,
        workspace: workspaceBundle,
      ),
      member: seatMember,
    );
  }
}
