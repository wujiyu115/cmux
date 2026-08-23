import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_notification.dart';
import '../../router/app_router.dart';
import '../../utils/logging/logger.dart';
import '../terminal/workspace_terminal_registry.dart';
import 'desktop_system_notifier.dart';
import 'notification_recorder.dart';
import 'terminal_idle_edge_detector.dart';

/// Resolved, localized strings + the enabled flag for one notification fire.
/// Null when there is no live app context (startup / teardown windows).
class TerminalIdleNotifyContext {
  const TerminalIdleNotifyContext({
    required this.enabled,
    required this.title,
    required this.subtitle,
    this.notifyWhileWatching = true,
  });

  final bool enabled;
  final String title;
  final String subtitle;

  /// When false, the active pane of the active surface is skipped while the
  /// window is focused. Mirrors `SessionPreferences.notifyWhileWatching`.
  final bool notifyWhileWatching;
}

/// Polls every embedded terminal's [WorkspaceTerminalGroup] for panes that go
/// from a burst of PTY output (working) to quiet (idle) — the "agent finished
/// a turn" edge — and raises a notification.
///
/// Replaces the old [ChatState.workingSessionIds] listener, which can no longer
/// fire now that plain terminal sessions never populate that set. Detection
/// hangs off [TerminalActivityTracker.isWorking] per pane instead.
///
/// **Opt-in** (`SessionPreferences.notifyOnPtyIdle`, off by default). This reads
/// raw output volume, not a lifecycle signal, so it cannot tell a finished turn
/// from a long `npm build` or from an agent thinking between tool calls. Panes
/// whose agent reports through the status hook are excluded outright — see
/// [_reportsAgentStatus] — and get exact notices from
/// `AgentAttentionNotificationService` regardless of this flag.
class TerminalIdleNotificationService {
  TerminalIdleNotificationService({
    required WorkspaceTerminalRegistry registry,
    Duration pollInterval = const Duration(milliseconds: 750),
    Duration minimumWorkDuration = const Duration(seconds: 5),
    Duration idleGrace = const Duration(seconds: 8),
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
       _edges = TerminalIdleEdgeDetector(
         minimumWorkDuration: minimumWorkDuration,
         idleGrace: idleGrace,
       ),
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
  final TerminalIdleEdgeDetector _edges;
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

  Timer? _timer;
  bool _ticking = false;

  void start() {
    _timer ??= Timer.periodic(_pollInterval, (_) => unawaited(_tick()));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _edges.clear();
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
        // pane of the active surface — don't nag about it, unless the user opted
        // into being notified anyway (notifyWhileWatching).
        if (!context.notifyWhileWatching && focused && pane.isActive) {
          appLogger.d(
            '[terminal-idle] notify suppressed: watching pane '
            '${pane.attribution}',
          );
          continue;
        }
        _emit(pane, context);
      }
    } finally {
      _ticking = false;
    }
  }

  /// Feeds every group's panes to [_edges] and returns the panes whose quiet has
  /// now held long enough to announce.
  List<_IdlePane> _collectIdleTransitions() {
    final now = _now();
    final live = <String>{};
    final becameIdle = <_IdlePane>[];

    for (final group in _registry.groups) {
      for (final entry in group.entries) {
        final id = entry.id;
        live.add(id);
        final notify = _edges.observe(
          paneId: id,
          working: entry.connected && entry.session.activityTracker.isWorking,
          // Panes that report agent lifecycle are notified by
          // `AgentAttentionNotificationService` on the semantic edge; this
          // PTY-burst heuristic would fire a second time for the same turn.
          reportsAgentStatus: _reportsAgentStatus(id),
          now: now,
        );
        if (!notify) continue;
        becameIdle.add(
          _IdlePane(
            attribution: group.paneAttribution(id),
            workspaceId: group.workspaceId,
            isActive: group.activeId == id,
          ),
        );
      }
    }

    _edges.retainOnly(live);
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
    final preferences = context
        .read<SessionPreferencesCubit>()
        .state
        .preferences;
    return TerminalIdleNotifyContext(
      // Both gates: `notifyOnSessionIdle` is the master for turn-finished
      // notices, `notifyOnPtyIdle` opts into *this* heuristic specifically. The
      // second defaults to off, so out of the box only panes that actually
      // report agent lifecycle notify.
      enabled: preferences.notifyOnSessionIdle && preferences.notifyOnPtyIdle,
      notifyWhileWatching: preferences.notifyWhileWatching,
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
