import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/team/session_working_resolver.dart';
import '../../services/terminal/terminal_session.dart';
import 'chat_tab_store.dart';
import 'model/chat_tab.dart';

/// Resolves [MemberCoordination] for a connected tab member.
final class TabMemberCoordinationFactory {
  TabMemberCoordinationFactory({
    required ChatTabStore tabStore,
    required List<CliPreset> Function() globalPresets,
    SessionWorkingResolver? sessionWorking,
  }) : _tabStore = tabStore,
       _globalPresets = globalPresets,
       _sessionWorking = sessionWorking ?? SessionWorkingResolver();

  final ChatTabStore _tabStore;
  final List<CliPreset> Function() _globalPresets;
  final SessionWorkingResolver _sessionWorking;

  SessionWorkingResolver get sessionWorking => _sessionWorking;

  MemberCoordination? forMember(
    String sessionId,
    String memberId, {
    bool directToPty = false,
  }) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null) return null;
    final shell = tab.memberShells[memberId];
    if (shell == null || !shell.isConnected) return null;

    final isPersonal = _sessionWorking.isPersonalTab(tab);
    final member = _resolveMember(tab, memberId, isPersonal);
    if (!member.isValid && !isPersonal && !directToPty) return null;

    final resolvedTeam = _fallbackTeam(tab, isPersonal);
    return MemberCoordination.resolve(
      shell: shell,
      member: member.isValid
          ? member
          : TeamMemberConfig(id: memberId, name: memberId),
      team: resolvedTeam,
      teamMode: resolvedTeam.teamMode,
      globalPresets: _globalPresets(),
      bus: null,
      session: tab.persistedSession,
      isPersonalSession: isPersonal,
    );
  }

  MemberCoordination forTabMember({
    required ChatTab tab,
    required String memberId,
    required TerminalSession shell,
    required bool isPersonal,
  }) {
    final resolvedTeam = _fallbackTeam(tab, isPersonal);
    return MemberCoordination.resolve(
      shell: shell,
      member: _resolveMember(tab, memberId, isPersonal),
      team: resolvedTeam,
      teamMode: resolvedTeam.teamMode,
      globalPresets: _globalPresets(),
      bus: null,
      session: tab.persistedSession,
      isPersonalSession: isPersonal,
    );
  }

  TeamMemberConfig resolveMember(
    ChatTab tab,
    String memberId,
    bool isPersonal,
  ) => _resolveMember(tab, memberId, isPersonal);

  TeamProfile fallbackTeam(ChatTab tab, bool isPersonal) =>
      _fallbackTeam(tab, isPersonal);

  TeamMemberConfig _resolveMember(
    ChatTab tab,
    String memberId,
    bool isPersonal,
  ) => TeamMemberConfig(id: memberId, name: memberId);

  TeamProfile _fallbackTeam(ChatTab tab, bool isPersonal) {
    final session = tab.persistedSession;
    return TeamProfile(id: '', name: '', cli: session?.cli ?? CliTool.claude);
  }
}
