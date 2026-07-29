import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/member_coordination.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

void main() {
  group('MemberCoordination availability', () {
    test('booting until PTY frame is stable', () {
      final shell = _ConnectedShell();
      shell.activityTracker.reset();
      expect(_resolve(shell), MemberAvailability.booting);

      shell.activityTracker.latchBootFrameReadyForTest();
      expect(_resolve(shell), MemberAvailability.idle);
    });

    test('personal userTurnActive shows working when PTY is quiet', () {
      final shell = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest(
          DateTime.now().subtract(const Duration(milliseconds: 3000)),
        )
        ..markUserTurnStarted();

      expect(
        MemberCoordination.resolve(
          shell: shell,
          member: const TeamMemberConfig(id: 'solo', name: 'solo'),
          team: const TeamProfile(id: '', name: ''),
          teamMode: TeamMode.native,
          globalPresets: const [],
          claudeRosterWorking: false,
          usesClaudeRoster: false,
          usesShellActivity: true,
        ).availability(),
        MemberAvailability.working,
        reason: 'submit success latches turn before PTY bytes arrive',
      );
    });

    test('isReadyForAutomationInput false while booting', () {
      final shell = _ConnectedShell();
      shell.activityTracker.reset();
      expect(
        MemberCoordination.resolve(
          shell: shell,
          member: const TeamMemberConfig(id: 'worker', name: 'worker'),
          team: const TeamProfile(id: 't', name: 'T'),
          teamMode: TeamMode.native,
          globalPresets: const [],
          claudeRosterWorking: false,
          usesClaudeRoster: false,
          usesShellActivity: true,
        ).isReadyForAutomationInput(),
        isFalse,
      );
      shell.activityTracker.latchBootFrameReadyForTest();
      expect(
        MemberCoordination.resolve(
          shell: shell,
          member: const TeamMemberConfig(id: 'worker', name: 'worker'),
          team: const TeamProfile(id: 't', name: 'T'),
          teamMode: TeamMode.native,
          globalPresets: const [],
          claudeRosterWorking: false,
          usesClaudeRoster: false,
          usesShellActivity: true,
        ).isReadyForAutomationInput(),
        isTrue,
      );
    });
  });
}

MemberAvailability _resolve(TerminalSession shell) {
  return MemberCoordination.resolve(
    shell: shell,
    member: const TeamMemberConfig(id: 'worker', name: 'worker'),
    team: const TeamProfile(
      id: 't',
      name: 'T',
      members: [TeamMemberConfig(id: 'worker', name: 'worker')],
    ),
    teamMode: TeamMode.native,
    globalPresets: const [],
    claudeRosterWorking: false,
    usesClaudeRoster: false,
    usesShellActivity: false,
  ).availability();
}

class _ConnectedShell extends TerminalSession {
  _ConnectedShell() : super(executable: 'true');

  @override
  bool get isRunning => true;

  @override
  bool get isConnected => true;

  @override
  void dispose() {}
}
