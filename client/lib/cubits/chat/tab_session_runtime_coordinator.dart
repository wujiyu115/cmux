import 'chat_tab_store.dart';
import 'tab_member_pty_delivery.dart';

/// Per-tab PTY delivery for session shells.
///
/// Plain shells have no agent turn model, so there is no idle watch and no
/// working-session aggregation — a shell is either connected or it is not.
class TabSessionRuntimeCoordinator {
  factory TabSessionRuntimeCoordinator({
    required ChatTabStore tabStore,
    required bool Function() isClosed,
    TabMemberPtyDelivery? delivery,
    void Function(String sessionId, String memberId)? onAfterTurnLatched,
  }) {
    return TabSessionRuntimeCoordinator._(
      tabStore: tabStore,
      delivery:
          delivery ??
          TabMemberPtyDelivery(
            tabStore: tabStore,
            isClosed: isClosed,
            onAfterTurnLatched: onAfterTurnLatched,
          ),
    );
  }

  TabSessionRuntimeCoordinator._({
    required ChatTabStore tabStore,
    required TabMemberPtyDelivery delivery,
  }) : _tabStore = tabStore,
       _delivery = delivery;

  final ChatTabStore _tabStore;
  final TabMemberPtyDelivery _delivery;

  void abortMemberInject(String sessionId, String memberId) =>
      _delivery.abortMemberInject(sessionId, memberId);

  /// A connected shell always accepts automation input.
  bool isMemberReadyForAutomationInput(
    String sessionId,
    String memberId, {
    bool directToPty = false,
  }) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    final shell = tab?.memberShells[memberId];
    return shell != null && shell.isConnected;
  }

  Future<void> deliverMemberStdin(
    String sessionId,
    String memberId,
    String text, {
    required bool automation,
    bool latchUserTurn = true,
  }) =>
      _delivery.deliverMemberStdin(
        sessionId,
        memberId,
        text,
        automation: automation,
        latchUserTurn: latchUserTurn,
      );

  Future<void> retryMemberDelivery(
    String sessionId,
    String memberId,
    String notice,
  ) => _delivery.retryMemberDelivery(sessionId, memberId, notice);

  Future<String?> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message, {
    bool directToPty = false,
  }) =>
      _delivery.deliverUserCommandToMember(
        sessionId,
        memberId,
        message,
        directToPty: directToPty,
      );
}
