import '../../cubits/chat_cubit.dart';
import '../terminal/workspace_terminal_registry.dart';

/// Resolves an agent-status seat id to whether its most recent user input
/// came from a paired phone (`ws:<paneId>` seats look through the workspace
/// terminal registry; `AppSession.sessionId` seats look through the chat
/// cubit's member shells).
///
/// Feeds the Bark push gate: phone-originated turns are exactly the ones
/// worth pushing back to the phone — a desktop-typed turn means the user is
/// at the desk and a push would be noise.
class SeatInputOrigin {
  SeatInputOrigin({
    required ChatCubit chat,
    required WorkspaceTerminalRegistry workspaceTerminals,
  }) : _chat = chat,
       _workspaceTerminals = workspaceTerminals;

  final ChatCubit _chat;
  final WorkspaceTerminalRegistry _workspaceTerminals;

  static const _workspacePanePrefix = 'ws:';

  /// Whether the seat's latest input was typed on a paired phone. Unknown
  /// seats (already closed, or never connected) report false — pushing on
  /// guesswork is the noisy direction.
  bool lastInputWasRemote(String seatId) {
    if (seatId.startsWith(_workspacePanePrefix)) {
      final paneId = seatId.substring(_workspacePanePrefix.length);
      final located = _workspaceTerminals.locatePane(paneId);
      final session = located?.$2.session;
      return session?.lastInputWasRemote ?? false;
    }
    return _chat.sessionLastInputWasRemote(seatId);
  }
}
