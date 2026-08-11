import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_notification.dart';
import '../../router/app_router.dart';
import '../terminal/workspace_terminal_registry.dart';
import 'desktop_system_notifier.dart';
import 'notification_recorder.dart';

/// Resolved, localized strings + the enabled flag for one notification fire.
/// Null when there is no live app context (startup / teardown windows).
class TerminalIdleNotifyContext {
  const TerminalIdleNotifyContext({
    required this.enabled,
    required this.title,
    required this.subtitle,
  });

  final bool enabled;
  final String title;
  final String subtitle;
}

/// Polls every embedded terminal's [WorkspaceTerminalGroup] for panes that go
/// from a burst of PTY output (working) to quiet (idle) — the "agent finished
/// a turn" edge — and raises a notification.
///
/// Replaces the old [ChatState.workingSessionIds] listener, which can no longer
/// fire now that plain terminal sessions never populate that set. Detection
/// hangs off [TerminalActivityTracker.isWorking] per pane instead.
class TerminalIdleNotificationService {
  TerminalIdleNotificationService({
    required WorkspaceTerminalRegistry registry,
    Duration pollInterval = const Duration(milliseconds: 750),
    Duration minimumWorkDuration = const Duration(seconds: 2),
    Future<bool> Function()? isAppFocused,
    Future<void> Function({
      required String title,
      required String body,
      String? subtitle,
      String? payload,
    })?
    showSystemNotification,
    NotificationRecorder? Function()? recorder,
    TerminalIdleNotifyContext? Function()? resolveContext,
    DateTime Function()? now,
    bool Function(String paneId)? reportsAgentStatus,
  }) : _registry = registry,
       _reportsAgentStatus = reportsAgentStatus ?? ((_) => false),
       _pollInterval = pollInterval,
       _minimumWorkDuration = minimumWorkDuration,
       _isAppFocused =
           isAppFocused ?? DesktopSystemNotifier.instance.isAppFocused,
       _showSystemNotification =
           showSystemNotification ??
           DesktopSystemNotifier.instance.showNotification,
       _recorder = recorder ?? (() => NotificationRecorder.maybeCurrent),
       _resolveContext = resolveContext ?? _defaultResolveContext,
       _now = now ?? DateTime.now;

  final WorkspaceTerminalRegistry _registry;

  /// True when the pane's agent reports lifecycle events through the status
  /// hook. Those panes are notified by `AgentAttentionNotificationService`
  /// instead — this PTY-burst heuristic would fire a second time for the same
  /// turn. Defaults to "never", so callers that don't wire it keep the old
  /// behaviour.
  final bool Function(String paneId) _reportsAgentStatus;
  final Duration _pollInterval;
  final Duration _minimumWorkDuration;
  final Future<bool> Function() _isAppFocused;
  final Future<void> Function({
    required String title,
    required String body,
    String? subtitle,
    String? payload,
  })
  _showSystemNotification;
  final NotificationRecorder? Function() _recorder;
  final TerminalIdleNotifyContext? Function() _resolveContext;
  final DateTime Function() _now;

  /// Per-pane last-observed working flag.
  final Map<String, bool> _wasWorking = {};

  /// Per-pane timestamp of the idle → working rising edge, used to drop
  /// trivially short bursts (a quick `ls`) below [_minimumWorkDuration].
  final Map<String, DateTime> _workingSince = {};

  Timer? _timer;
  bool _ticking = false;

  void start() {
    _timer ??= Timer.periodic(_pollInterval, (_) => unawaited(_tick()));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _wasWorking.clear();
    _workingSince.clear();
  }

  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      final becameIdle = _collectIdleTransitions();
      if (becameIdle.isEmpty) return;

      final context = _resolveContext();
      if (context == null || !context.enabled) return;

      final focused = await _isAppFocused();
      for (final pane in becameIdle) {
        // While the window is focused, assume the user is watching the active
        // pane of the active surface — don't nag about it.
        if (focused && pane.isActive) continue;
        _emit(pane, context);
      }
    } finally {
      _ticking = false;
    }
  }

  /// Scans every group's panes, updates the working/idle bookkeeping, and
  /// returns the panes that just crossed working → idle this tick.
  List<_IdlePane> _collectIdleTransitions() {
    final now = _now();
    final live = <String>{};
    final becameIdle = <_IdlePane>[];

    for (final group in _registry.groups) {
      for (final entry in group.entries) {
        final id = entry.id;
        live.add(id);
        final working = entry.connected && entry.session.activityTracker.isWorking;
        final was = _wasWorking[id] ?? false;

        // Defer to the status-hook service for panes that report agent
        // lifecycle: it already notifies on the semantic edge, and this
        // PTY-burst heuristic would fire a second time for the same turn. Keep
        // the bookkeeping current so the pane doesn't surface a stale edge if it
        // later stops reporting.
        if (_reportsAgentStatus(id)) {
          _wasWorking[id] = working;
          _workingSince.remove(id);
          continue;
        }

        if (working && !was) {
          _workingSince[id] = now;
        } else if (!working && was) {
          final since = _workingSince.remove(id);
          final workedLongEnough =
              since != null && now.difference(since) >= _minimumWorkDuration;
          if (workedLongEnough) {
            becameIdle.add(
              _IdlePane(
                attribution: group.paneAttribution(id),
                workspaceId: group.workspaceId,
                isActive: group.activeId == id,
              ),
            );
          }
        }
        _wasWorking[id] = working;
      }
    }

    // Drop bookkeeping for panes that no longer exist.
    _wasWorking.removeWhere((id, _) => !live.contains(id));
    _workingSince.removeWhere((id, _) => !live.contains(id));
    return becameIdle;
  }

  void _emit(_IdlePane pane, TerminalIdleNotifyContext context) {
    final title = pane.attribution.trim().isNotEmpty
        ? pane.attribution.trim()
        : context.title;
    final payload = pane.workspaceId.isEmpty
        ? ''
        : '/home-v2/workspace/${pane.workspaceId}';

    _recorder()?.record(
      title: title,
      message: context.subtitle,
      variant: TpToastVariant.success,
      payload: payload,
      source: AppNotificationSource.cli,
    );

    unawaited(
      _showSystemNotification(
        title: title,
        body: context.subtitle,
        subtitle: context.title,
        payload: payload.isEmpty ? null : payload,
      ).catchError((_) {}),
    );
  }

  static TerminalIdleNotifyContext? _defaultResolveContext() {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return null;
    final l10n = context.l10n;
    final enabled = context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .notifyOnSessionIdle;
    return TerminalIdleNotifyContext(
      enabled: enabled,
      title: l10n.sessionIdleNotificationTitle,
      subtitle: l10n.sessionIdleNotificationSubtitle,
    );
  }
}

/// A pane that just went idle, with the facts needed to attribute a notice.
class _IdlePane {
  const _IdlePane({
    required this.attribution,
    required this.workspaceId,
    required this.isActive,
  });

  final String attribution;
  final String workspaceId;
  final bool isActive;
}
