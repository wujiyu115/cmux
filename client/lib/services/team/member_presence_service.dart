import '../../models/app_session.dart';
import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../terminal/terminal_session.dart';

/// Session-scoped inputs for [MemberPresenceService.compute].
class PresenceSessionContext {
  const PresenceSessionContext({required this.team, this.appSession});

  final TeamProfile team;

  /// Active tab session — when set, presence polls session pods (not a fresh
  /// expand of possibly-stale [TeamMemberConfig.replicas]).
  final AppSession? appSession;
}

/// Maps terminal connection state onto [MemberPresence].
///
/// Plain shells expose no agent availability, so presence is connection-only.
class MemberPresenceService {
  MemberPresenceService();

  Future<Map<String, MemberPresence>> compute({
    required CliTool teamCli,
    required List<TeamMemberConfig> members,
    required String cliTeamName,
    required String? memberToolConfigDir,
    required Map<String, TerminalSession> memberShells,
    PresenceSessionContext? session,
  }) async {
    final out = <String, MemberPresence>{};
    for (final member in members) {
      if (!member.isValid) continue;
      out[member.id] = MemberPresence(
        connection: _connectionOf(memberShells[member.id]),
      );
    }
    return out.isEmpty ? const {} : out;
  }

  static MemberConnection _connectionOf(TerminalSession? shell) {
    if (shell == null) return MemberConnection.offline;
    if (shell.isConnecting) return MemberConnection.connecting;
    if (shell.isConnected) return MemberConnection.connected;
    return MemberConnection.offline;
  }
}
