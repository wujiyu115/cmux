import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../models/app_session.dart';
import '../../models/cli_tool.dart';
import '../../models/workspace.dart';
import '../../services/terminal/terminal_session.dart';

typedef ResolvedLaunchMembers = ({String memberId, CliTool cli});

class TabConnectPrepResult {
  const TabConnectPrepResult({
    required this.launchSession,
    required this.resolved,
    required this.shell,
  });

  final AppSession launchSession;
  final ResolvedLaunchMembers resolved;
  final TerminalSession shell;
}

/// Callbacks the shared tab-connect prep pipeline needs from
/// [SessionLaunchService].
typedef SessionTabConnectPrepCallbacks = ({
  Future<AppSession> Function({
    required SessionOpenRequest request,
    required AppSession session,
    required ChatTab tab,
  })
  persistSessionIfNeeded,
  Future<ResolvedLaunchMembers> Function({
    required AppSession session,
    required SessionOpenRequest request,
    Workspace? workspace,
  })
  resolveLaunchMembers,
  void Function(String memberId) updateSelectedMember,
  TerminalSession Function({
    required ChatTab tab,
    required String shellKey,
    required CliTool cli,
    required AppSession session,
  })
  shellForLaunch,
  bool Function(ChatTab tab, int generation) launchStillValid,
});

/// Shared persist, resolve, and shell prep for new and existing tabs.
Future<TabConnectPrepResult?> runSessionTabConnectPrep({
  required SessionTabConnectPrepCallbacks callbacks,
  required int generation,
  required ChatTab tab,
  required AppSession session,
  required SessionOpenRequest request,
  required Workspace? workspace,
}) async {
  final launchSession = await callbacks.persistSessionIfNeeded(
    request: request,
    session: session,
    tab: tab,
  );
  if (!callbacks.launchStillValid(tab, generation)) return null;
  tab.persistedSession = launchSession;

  final resolved = await callbacks.resolveLaunchMembers(
    session: launchSession,
    request: request,
    workspace: workspace,
  );
  if (!callbacks.launchStillValid(tab, generation)) return null;

  callbacks.updateSelectedMember(resolved.memberId);
  tab.selectedMemberId = resolved.memberId;

  final shell = callbacks.shellForLaunch(
    tab: tab,
    shellKey: resolved.memberId,
    cli: resolved.cli,
    session: launchSession,
  );

  return TabConnectPrepResult(
    launchSession: launchSession,
    resolved: resolved,
    shell: shell,
  );
}
