import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../cli/preset_resolver.dart';
import '../cli/registry/capabilities/presence_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../terminal/terminal_session.dart';
import 'member_coordination_scope.dart';

export 'member_coordination_scope.dart' show MemberCoordinationScope;

enum MemberCoordinationKind {
  personal,
  nativeClaudeRoster,
  nativeShellActivity,
}

/// Turn latch, idle-watch, and availability policy for one connected member.
sealed class MemberCoordination {
  const MemberCoordination(this.scope);

  final MemberCoordinationScope scope;

  TerminalSession get shell => scope.shell;
  TeamMemberConfig get member => scope.member;

  bool inTurn({required bool pendingDelivery});
  void latchTurnStarted();
  void endTurn();
  MemberAvailability availability();
  bool countsAsSessionWorkingWhileBooting();
  bool isReadyForAutomationInput({bool directToPty = false});

  factory MemberCoordination.resolve({
    required TerminalSession shell,
    required TeamMemberConfig member,
    required TeamProfile team,
    required TeamMode teamMode,
    required List<CliPreset> globalPresets,
    AppSession? session,
    bool? isPersonalSession,
    bool claudeRosterWorking = false,
    bool usesClaudeRoster = false,
    bool usesShellActivity = false,
    CliToolRegistry? cliToolRegistry,
  }) {
    final personal =
        isPersonalSession ??
        (MemberCoordinationScope.inferPersonalFromLegacyFlags(
          usesClaudeRoster: usesClaudeRoster,
          usesShellActivity: usesShellActivity,
        ) &&
            team.id.trim().isEmpty);
    final coordinationScope = MemberCoordinationScope(
      shell: shell,
      member: member,
      team: team,
      teamMode: teamMode,
      globalPresets: globalPresets,
      session: session,
      claudeRosterWorking: claudeRosterWorking,
    );
    final registry = cliToolRegistry ?? CliToolRegistry.builtIn();
    final presenceCap = registry.capability<PresenceCapability>(team.cli);
    final kind = _kindFor(
      isPersonalSession: personal,
      usesClaudeRoster: presenceCap?.usesClaudeRoster ?? usesClaudeRoster,
      usesShellActivity: presenceCap?.usesShellActivity ?? usesShellActivity,
    );
    return switch (kind) {
      MemberCoordinationKind.personal =>
        PersonalMemberCoordination(coordinationScope),
      MemberCoordinationKind.nativeClaudeRoster =>
        NativeClaudeRosterCoordination(coordinationScope),
      MemberCoordinationKind.nativeShellActivity =>
        NativeShellActivityCoordination(coordinationScope),
    };
  }

  static MemberCoordinationKind _kindFor({
    required bool isPersonalSession,
    required bool usesClaudeRoster,
    required bool usesShellActivity,
  }) {
    if (isPersonalSession) return MemberCoordinationKind.personal;
    if (usesClaudeRoster) return MemberCoordinationKind.nativeClaudeRoster;
    if (usesShellActivity) return MemberCoordinationKind.nativeShellActivity;
    return MemberCoordinationKind.personal;
  }

  MemberAvailability _bootingOr(MemberAvailability whenReady) {
    if (!shell.activityTracker.isBootFrameReady) {
      return MemberAvailability.booting;
    }
    return whenReady;
  }
}

/// Shell [userTurnActive] latch shared by personal and native single-CLI modes.
abstract base class ShellLatchCoordination extends MemberCoordination {
  const ShellLatchCoordination(super.scope);

  @override
  bool inTurn({required bool pendingDelivery}) =>
      shell.userTurnActive || pendingDelivery;

  @override
  void latchTurnStarted() => shell.markUserTurnStarted();

  @override
  void endTurn() => shell.markUserTurnIdle();

  @override
  bool isReadyForAutomationInput({bool directToPty = false}) =>
      shell.activityTracker.isBootFrameReady;
}

final class PersonalMemberCoordination extends ShellLatchCoordination {
  const PersonalMemberCoordination(super.scope);

  @override
  MemberAvailability availability() => _bootingOr(
    shell.userTurnActive
        ? MemberAvailability.working
        : MemberAvailability.idle,
  );

  @override
  bool countsAsSessionWorkingWhileBooting() {
    if (availability() != MemberAvailability.booting) return false;
    // Only a latched user turn counts while the boot frame is still settling.
    // Startup PTY churn must not light session-working (that false edge fires
    // the "ready to chat" idle notification when opening a stopped session).
    return shell.userTurnActive;
  }
}

final class NativeClaudeRosterCoordination extends ShellLatchCoordination {
  const NativeClaudeRosterCoordination(super.scope);

  @override
  MemberAvailability availability() => _bootingOr(
    scope.claudeRosterWorking
        ? MemberAvailability.working
        : MemberAvailability.idle,
  );

  @override
  bool countsAsSessionWorkingWhileBooting() => false;
}

final class NativeShellActivityCoordination extends ShellLatchCoordination {
  const NativeShellActivityCoordination(super.scope);

  @override
  MemberAvailability availability() => _bootingOr(
    shell.activityTracker.isWorking
        ? MemberAvailability.working
        : MemberAvailability.idle,
  );

  @override
  bool countsAsSessionWorkingWhileBooting() => false;
}
