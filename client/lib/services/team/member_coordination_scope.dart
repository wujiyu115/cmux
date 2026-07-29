import '../../cubits/chat/model/chat_tab.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../terminal/terminal_session.dart';

/// Immutable inputs shared by every [MemberCoordination] implementation.
final class MemberCoordinationScope {
  const MemberCoordinationScope({
    required this.shell,
    required this.member,
    required this.team,
    required this.teamMode,
    required this.globalPresets,
    this.session,
    this.claudeRosterWorking = false,
  });

  final TerminalSession shell;
  final TeamMemberConfig member;
  final TeamProfile team;
  final TeamMode teamMode;
  final List<CliPreset> globalPresets;
  final AppSession? session;
  final bool claudeRosterWorking;

  /// Personal sessions have no persisted team roster (`sessionTeam` empty).
  static bool isPersonalSession({ChatTab? tab, AppSession? session}) {
    final persisted = session ?? tab?.persistedSession;
    if (persisted != null) return persisted.sessionTeam.trim().isEmpty;
    return true;
  }

  /// Legacy callers inferred personal mode from presence-cap flags.
  static bool inferPersonalFromLegacyFlags({
    required bool usesClaudeRoster,
    required bool usesShellActivity,
  }) {
    if (usesClaudeRoster) return false;
    return usesShellActivity;
  }
}
