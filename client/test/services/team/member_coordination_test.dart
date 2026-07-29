import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/member_coordination.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

void main() {
  group('MemberCoordination', () {
    test('personal: userTurnActive is working, PTY churn is idle', () {
      final shell = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest(
          DateTime.now().subtract(const Duration(seconds: 5)),
        );

      final coordination = MemberCoordination.resolve(
        shell: shell,
        member: const TeamMemberConfig(id: 'solo', name: 'solo'),
        team: const TeamProfile(id: '', name: ''),
        teamMode: TeamMode.native,
        globalPresets: const [],
        isPersonalSession: true,
      );

      shell.activityTracker.markActive();
      expect(coordination.availability(), MemberAvailability.idle);

      shell.markUserTurnStarted();
      expect(coordination.availability(), MemberAvailability.working);
    });

    test('latchTurnStarted latches the shell user turn', () {
      final solo = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest();
      MemberCoordination.resolve(
        shell: solo,
        member: const TeamMemberConfig(id: 'solo', name: 'solo'),
        team: const TeamProfile(id: '', name: ''),
        teamMode: TeamMode.native,
        globalPresets: const [],
        isPersonalSession: true,
      ).latchTurnStarted();
      expect(solo.userTurnActive, isTrue);
    });
  });
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
