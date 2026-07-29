import 'dart:async';

import '../../utils/logging/logger.dart';
import 'chat_tab_store.dart';
import 'tab_session_runtime_coordinator.dart';

/// Bridges member input readiness to PTY shells for the personal launch path.
///
/// Simple (unteamed) sessions run a single PTY keyed on the session id. This
/// waits for that shell to reach the TUI prompt before automation / prompt
/// inject.
class TabMemberMaterializer {
  TabMemberMaterializer({
    required TabSessionRuntimeCoordinator runtime,
    required ChatTabStore tabStore,
    required bool Function() isClosed,
  }) : _runtime = runtime,
       _tabStore = tabStore,
       _isClosed = isClosed;

  final TabSessionRuntimeCoordinator _runtime;
  final ChatTabStore _tabStore;
  final bool Function() _isClosed;

  final Map<(String, String), Completer<void>> _memberReady = {};

  void markMemberReady(String sessionId, String memberId) {
    _memberReady.remove((sessionId, memberId))?.complete();
  }

  /// PTY connect + TUI/agent startup complete — used before automation inject.
  ///
  /// [directToPty]: compose-landing operator input — boot frame only, inject at
  /// the TUI prompt.
  Future<void> ensureMemberInputReady(
    String sessionId,
    String memberId, {
    bool directToPty = false,
  }) async {
    await materializeMember(sessionId, memberId, '');
    var waitTicks = 0;
    while (!_isClosed()) {
      final shellReady = _runtime.isMemberReadyForAutomationInput(
        sessionId,
        memberId,
        directToPty: directToPty,
      );
      if (shellReady) {
        appLogger.d(
          '[member-materializer] input-ready member=$memberId '
          'session=$sessionId directToPty=$directToPty',
        );
        return;
      }
      waitTicks++;
      if (waitTicks == 1 || waitTicks % 50 == 0) {
        appLogger.d(
          '[member-materializer] input-ready still-waiting '
          'member=$memberId session=$sessionId ticks=$waitTicks '
          '${_inputReadyGateSummary(sessionId, memberId)}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  String _inputReadyGateSummary(String sessionId, String memberId) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null) return 'gate=no-tab';
    final shell = tab.memberShells[memberId];
    if (shell == null) {
      return 'gate=no-shell keys=${tab.memberShells.keys.toList()} '
          'selected=${tab.selectedMemberId}';
    }
    final coord = _runtime.isMemberReadyForAutomationInput(
      sessionId,
      memberId,
      directToPty: true,
    );
    return 'gate shellRunning=${shell.isRunning} '
        'shellConnected=${shell.isConnected} '
        'shellConnecting=${shell.isConnecting} '
        'boot=${shell.activityTracker.bootFrameDebugSummary} '
        'automationReady=$coord '
        'selected=${tab.selectedMemberId}';
  }

  Future<void> materializeMember(
    String sessionId,
    String memberId,
    String bootstrap,
  ) async {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null) return;

    final ready = Completer<void>();
    _memberReady[(sessionId, memberId)] = ready;
    final shell = tab.memberShells[memberId];
    if (shell != null && shell.isRunning) {
      markMemberReady(sessionId, memberId);
    } else {
      appLogger.d(
        '[member-materializer] personal await-connect '
        'member=$memberId session=$sessionId '
        'shellNull=${shell == null} '
        'running=${shell?.isRunning} '
        'connecting=${shell?.isConnecting} '
        'keys=${tab.memberShells.keys.toList()} '
        'selected=${tab.selectedMemberId}',
      );
    }
    await ready.future;
  }

  void injectMemberStdin(String sessionId, String memberId, String text) {
    unawaited(
      _runtime.deliverMemberStdin(
        sessionId,
        memberId,
        text,
        automation: true,
        latchUserTurn: false,
      ),
    );
  }

  void retryDelivery(String sessionId, String memberId, String notice) {
    unawaited(_runtime.retryMemberDelivery(sessionId, memberId, notice));
  }
}
