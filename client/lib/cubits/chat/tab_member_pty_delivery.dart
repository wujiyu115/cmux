
import '../../services/terminal/fullscreen_cr_ack_config.dart';
import '../../services/terminal/fullscreen_pty_automation.dart';
import '../../services/terminal/member_pty_inject_service.dart';
import '../../services/terminal/pty_automation_retry_queue.dart';
import '../../services/terminal/terminal_input_controller.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logging/logger.dart';
import 'chat_tab_store.dart';

/// Full-screen PTY inject + automation retry for the session terminal.
final class TabMemberPtyDelivery {
  TabMemberPtyDelivery({
    required ChatTabStore tabStore,
    required bool Function() isClosed,
    void Function(String sessionId, String memberId)? onAfterTurnLatched,
    MemberPtyInjectService? ptyInject,
  }) : _tabStore = tabStore,
       _isClosed = isClosed,
       _onAfterTurnLatched = onAfterTurnLatched {
    _ptyInject =
        ptyInject ??
        MemberPtyInjectService(
          onDeliveryRetryExhausted: _onDeliveryRetryExhausted,
        );
  }

  final ChatTabStore _tabStore;
  final bool Function() _isClosed;
  final void Function(String sessionId, String memberId)? _onAfterTurnLatched;
  late final MemberPtyInjectService _ptyInject;

  bool hasPendingRetry(String sessionId, String memberId) =>
      _ptyInject.hasPendingRetry(sessionId, memberId);

  bool isBusy(String sessionId, String memberId) =>
      _ptyInject.isBusy(sessionId, memberId);

  void clearPending(String sessionId, String memberId) =>
      _ptyInject.clearPending(sessionId, memberId);

  void abortMemberInject(String sessionId, String memberId) {
    _ptyInject.requestAbort(sessionId, memberId);
    if (!_ptyInject.isBusy(sessionId, memberId)) {
      _ptyInject.clearAbort(sessionId, memberId);
    }
  }

  void tickRetries({
    required bool Function(PtyAutomationRetryTick tick) shouldSkip,
    required void Function(PtyAutomationRetryTick tick) onTick,
  }) {
    _ptyInject.tickRetries(shouldSkip: shouldSkip, onTick: onTick);
  }

  /// Bracketed-paste + CR for full-screen CLIs; [automation] uses grid ACK.
  Future<void> deliverMemberStdin(
    String sessionId,
    String memberId,
    String text, {
    required bool automation,
    bool latchUserTurn = true,
  }) async {
    final shell = _tabStore.openTabBySessionId(sessionId)?.memberShells[memberId];
    if (shell == null) {
      appLogger.w(
        '[session-runtime] pty-inject skipped no-shell '
        'member=$memberId session=$sessionId',
      );
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final isOperatorTurn = latchUserTurn;
    final usesFullScreen = _memberUsesFullScreen(sessionId, memberId);
    appLogger.d(
      '[session-runtime] pty-inject member=$memberId '
      'session=$sessionId fullscreen=$usesFullScreen '
      'automation=$automation '
      'chars=${trimmed.length}',
    );
    if (usesFullScreen) {
      await _deliverFullScreen(
        sessionId: sessionId,
        memberId: memberId,
        shell: shell,
        text: trimmed,
        automation: automation,
        isOperatorTurn: isOperatorTurn,
      );
      return;
    }
    shell.input.writeln(trimmed);
    if (isOperatorTurn) {
      _markMemberTurnStartedOnSubmitSuccess(sessionId, memberId);
    }
  }

  Future<void> retryMemberDelivery(
    String sessionId,
    String memberId,
    String notice,
  ) async {
    final shell = _tabStore.openTabBySessionId(sessionId)?.memberShells[memberId];
    if (shell == null) {
      appLogger.w(
        '[session-runtime] retry-delivery skipped no-shell '
        'member=$memberId session=$sessionId',
      );
      return;
    }
    if (_ptyAckAborted(shell, sessionId: sessionId, memberId: memberId)) return;
    if (shouldSkipAutomationRetry(sessionId, memberId)) {
      dropStaleAutomationRetry(sessionId, memberId, shell);
      return;
    }
    final trimmed = notice.trim();
    if (trimmed.isEmpty) return;

    appLogger.d(
      '[session-runtime] retry-delivery member=$memberId session=$sessionId',
    );
    if (!_memberUsesGridPasteAck(sessionId, memberId)) {
      final settle = _pasteSettleForMember(
        sessionId,
        memberId,
        automation: false,
      );
      await shell.input.submitFullScreenInput(trimmed, pasteSettleDelay: settle);
      return;
    }
    final settle = _pasteSettleForMember(
      sessionId,
      memberId,
      automation: true,
    );
    await _ptyInject.retry(
      input: shell.input,
      probe: shell.probe,
      sessionId: sessionId,
      memberId: memberId,
      text: trimmed,
      pasteSettle: settle,
      aborted: () =>
          _ptyAckAborted(shell, sessionId: sessionId, memberId: memberId),
      crAckConfig: _crAckForMember(sessionId, memberId),
    );
  }

  /// Injects [message] at the member prompt (compose landing, automation, first
  /// prompt). Returns `null` unless [directToPty] is set (no bus routing).
  Future<String?> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message, {
    bool directToPty = false,
  }) async {
    if (!directToPty) return null;
    await deliverMemberStdin(
      sessionId,
      memberId,
      message,
      automation: true,
    );
    return null;
  }

  bool shouldSkipAutomationRetry(
    String sessionId,
    String memberId, {
    String? dueRetryText,
  }) => false;

  void dropStaleAutomationRetry(
    String sessionId,
    String memberId,
    TerminalSession shell,
  ) {
    _ptyInject.clearPending(sessionId, memberId);
    shell.markUserTurnIdle();
    appLogger.d(
      '[session-runtime] automation-retry-skipped member=$memberId '
      'session=$sessionId',
    );
  }

  Future<void> retryAutomationTick(PtyAutomationRetryTick tick) async {
    final shell =
        _tabStore.openTabBySessionId(tick.sessionId)?.memberShells[tick.memberId];
    if (shell == null) return;
    if (_ptyAckAborted(
      shell,
      sessionId: tick.sessionId,
      memberId: tick.memberId,
    )) {
      return;
    }
    if (shouldSkipAutomationRetry(
      tick.sessionId,
      tick.memberId,
      dueRetryText: tick.text,
    )) {
      dropStaleAutomationRetry(tick.sessionId, tick.memberId, shell);
      return;
    }
    final settle = _pasteSettleForMember(
      tick.sessionId,
      tick.memberId,
      automation: true,
    );
    if (!_memberUsesGridPasteAck(tick.sessionId, tick.memberId)) {
      await shell.input.submitFullScreenInput(tick.text, pasteSettleDelay: settle);
      _markMemberTurnStartedOnSubmitSuccess(tick.sessionId, tick.memberId);
      return;
    }
    final outcome = await _ptyInject.retry(
      input: shell.input,
      probe: shell.probe,
      sessionId: tick.sessionId,
      memberId: tick.memberId,
      text: tick.text,
      pasteSettle: settle,
      aborted: () => _ptyAckAborted(
        shell,
        sessionId: tick.sessionId,
        memberId: tick.memberId,
      ),
      crAckConfig: _crAckForMember(tick.sessionId, tick.memberId),
    );
    if (outcome == FullscreenPtyDeliveryOutcome.submitted) {
      _markMemberTurnStartedOnSubmitSuccess(tick.sessionId, tick.memberId);
    }
  }

  Future<void> _deliverFullScreen({
    required String sessionId,
    required String memberId,
    required TerminalSession shell,
    required String text,
    required bool automation,
    required bool isOperatorTurn,
  }) async {
    final gridAck = _memberUsesGridPasteAck(sessionId, memberId);
    final settle = _pasteSettleForMember(
      sessionId,
      memberId,
      automation: automation && gridAck,
    );
    if (automation && gridAck) {
      final outcome = await _ptyInject.deliver(
        input: shell.input,
        probe: shell.probe,
        sessionId: sessionId,
        memberId: memberId,
        text: text,
        pasteSettle: settle,
        aborted: () =>
            _ptyAckAborted(shell, sessionId: sessionId, memberId: memberId),
        crAckConfig: _crAckForMember(sessionId, memberId),
      );
      if (isOperatorTurn &&
          outcome == FullscreenPtyDeliveryOutcome.submitted) {
        _markMemberTurnStartedOnSubmitSuccess(sessionId, memberId);
      }
      return;
    }
    await shell.input.submitFullScreenInput(text, pasteSettleDelay: settle);
    if (isOperatorTurn) {
      _markMemberTurnStartedOnSubmitSuccess(sessionId, memberId);
    }
  }

  bool _ptyAckAborted(
    TerminalSession shell, {
    String? sessionId,
    String? memberId,
  }) {
    if (_isClosed() || !shell.isConnected) return true;
    if (sessionId != null &&
        memberId != null &&
        _ptyInject.isAbortRequested(sessionId, memberId)) {
      if (!_ptyInject.isBusy(sessionId, memberId)) {
        _ptyInject.clearAbort(sessionId, memberId);
      }
      return true;
    }
    return false;
  }

  /// Plain shells never take over the screen, so submit is line-based.
  bool _memberUsesFullScreen(String sessionId, String memberId) => false;

  bool _memberUsesGridPasteAck(String sessionId, String memberId) => true;

  Duration _pasteSettleForMember(
    String sessionId,
    String memberId, {
    required bool automation,
  }) {
    const base = TerminalInputController.fullScreenSubmitDelay;
    if (!automation) return base;
    return Duration(
      milliseconds: base.inMilliseconds < 500 ? 500 : base.inMilliseconds,
    );
  }

  FullscreenCrAckConfig _crAckForMember(String sessionId, String memberId) =>
      const FullscreenCrAckConfig(
        strategy: FullscreenCrAckStrategy.anchorCellClears,
      );

  void _markMemberTurnStartedOnSubmitSuccess(
    String sessionId,
    String memberId,
  ) {
    _onAfterTurnLatched?.call(sessionId, memberId);
  }

  void _onDeliveryRetryExhausted(
    String sessionId,
    String memberId,
    FullscreenPtyDeliveryOutcome outcome,
  ) {
    _ptyInject.clearPending(sessionId, memberId);
  }
}
