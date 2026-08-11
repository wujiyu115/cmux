import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_notification.dart';
import '../../pages/home_workspace/home_workspace_route.dart';
import '../../router/app_router.dart';
import '../agent_status/agent_attention_state.dart';
import 'desktop_system_notifier.dart';
import 'notification_recorder.dart';

/// The three notify-worthy agent lifecycle edges. CLI-neutral: the per-CLI
/// `AgentStatusNormalizer` has already mapped raw hooks to attention + the
/// interrupt flag, so this driver never inspects a `CliTool`.
enum AgentNoticeKind { done, interrupted, waiting }

/// Resolved, localized copy + the enabled flag for one notify pass. Null when
/// there is no live app context (startup / teardown windows).
class AgentAttentionNotifyContext {
  const AgentAttentionNotifyContext({
    required this.enabled,
    required this.titles,
    required this.bodies,
  });

  final bool enabled;
  final Map<AgentNoticeKind, String> titles;
  final Map<AgentNoticeKind, String> bodies;
}

/// Where a seat lives + how to name it, for the notification body and tap route.
class AgentNoticeAttribution {
  const AgentNoticeAttribution({
    required this.title,
    required this.workspaceId,
    this.workspaceLabel = '',
    this.location = '',
  });

  /// Notification headline — the session's own name (its task), when known.
  final String title;

  /// Workspace the seat belongs to; drives the tap deep-link.
  final String workspaceId;

  /// Human label of [workspaceId], surfaced in the body so the user sees which
  /// workspace/directory the agent is in.
  final String workspaceLabel;

  /// Explicit tap deep-link, for seats that are not chat sessions.
  ///
  /// A workspace-terminal seat id (`ws:<paneId>`) is not a session id, so the
  /// default composition would build a route to a session that does not exist.
  /// When set, this is used verbatim instead.
  final String location;
}

/// Turns [AgentAttentionCubit] seat transitions into OS + in-app notifications:
/// an agent finishing (done), being cancelled (interrupted), or asking for
/// authorization (waiting). Semantic counterpart to the PTY-idle heuristic in
/// `TerminalIdleNotificationService`; that service defers to this one for panes
/// that report agent status.
class AgentAttentionNotificationService {
  AgentAttentionNotificationService({
    required AgentAttentionCubit attention,
    Future<bool> Function()? isAppFocused,
    bool Function(String sessionId, String memberId)? isForegroundSeat,
    Future<void> Function({
      required String title,
      required String body,
      String? subtitle,
      String? payload,
    })?
    showSystemNotification,
    NotificationRecorder? Function()? recorder,
    AgentAttentionNotifyContext? Function()? resolveContext,
    AgentNoticeAttribution? Function(String sessionId, String memberId)?
    resolveAttribution,
  }) : _attention = attention,
       _isAppFocused =
           isAppFocused ?? DesktopSystemNotifier.instance.isAppFocused,
       _isForegroundSeat = isForegroundSeat ?? ((_, __) => false),
       _showSystemNotification =
           showSystemNotification ??
           DesktopSystemNotifier.instance.showNotification,
       _recorder = recorder ?? (() => NotificationRecorder.maybeCurrent),
       _resolveContext = resolveContext ?? _defaultResolveContext,
       _resolveAttribution = resolveAttribution ?? ((_, __) => null);

  final AgentAttentionCubit _attention;
  final Future<bool> Function() _isAppFocused;
  final bool Function(String sessionId, String memberId) _isForegroundSeat;
  final Future<void> Function({
    required String title,
    required String body,
    String? subtitle,
    String? payload,
  })
  _showSystemNotification;
  final NotificationRecorder? Function() _recorder;
  final AgentAttentionNotifyContext? Function() _resolveContext;
  final AgentNoticeAttribution? Function(String sessionId, String memberId)
  _resolveAttribution;

  /// Per-seat last-observed attention, for rising-edge detection.
  final Map<String, AgentSeatAttention> _last = {};

  StreamSubscription<AgentAttentionState>? _sub;

  void start() {
    _sub ??= _attention.stream.listen((state) => unawaited(_onState(state)));
    // Seed without firing so a state already present at startup is a baseline,
    // not a fresh transition.
    _seed(_attention.state);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _last.clear();
  }

  void _seed(AgentAttentionState state) {
    for (final entry in state.seats.entries) {
      _last[entry.key] = entry.value.attention;
    }
  }

  Future<void> _onState(AgentAttentionState state) async {
    final notices = _collectNotices(state);
    if (notices.isEmpty) return;

    final context = _resolveContext();
    if (context == null || !context.enabled) return;

    final focused = await _isAppFocused();
    for (final notice in notices) {
      // While focused and looking at this very seat, don't nag.
      if (focused && _isForegroundSeat(notice.sessionId, notice.memberId)) {
        continue;
      }
      _emit(notice, context);
    }
  }

  /// Diffs seat attention against the last snapshot, returning the rising edges
  /// worth a notification. Also prunes bookkeeping for seats that vanished.
  List<_AgentNotice> _collectNotices(AgentAttentionState state) {
    final live = <String>{};
    final notices = <_AgentNotice>[];

    for (final entry in state.seats.entries) {
      final key = entry.key;
      live.add(key);
      final current = entry.value.attention;
      final previous = _last[key];
      _last[key] = current;
      if (current == previous) continue;

      final kind = switch (current) {
        AgentSeatAttention.waiting => AgentNoticeKind.waiting,
        AgentSeatAttention.done =>
          (entry.value.lastEvent?.interrupted ?? false)
              ? AgentNoticeKind.interrupted
              : AgentNoticeKind.done,
        AgentSeatAttention.working => null,
      };
      if (kind == null) continue;

      final seat = _splitSeatKey(key);
      if (seat == null) continue;
      notices.add(
        _AgentNotice(
          sessionId: seat.$1,
          memberId: seat.$2,
          kind: kind,
        ),
      );
    }

    _last.removeWhere((key, _) => !live.contains(key));
    return notices;
  }

  void _emit(_AgentNotice notice, AgentAttentionNotifyContext context) {
    final attribution = _resolveAttribution(notice.sessionId, notice.memberId);
    final fallbackTitle = context.titles[notice.kind] ?? '';
    final title = (attribution?.title.trim().isNotEmpty ?? false)
        ? attribution!.title.trim()
        : fallbackTitle;
    // Body carries which workspace/directory the agent is in, then the
    // CLI-neutral lifecycle line ("done" / "waiting" / "interrupted").
    final kindBody = context.bodies[notice.kind] ?? '';
    final workspaceLabel = attribution?.workspaceLabel.trim() ?? '';
    final body = workspaceLabel.isEmpty
        ? kindBody
        : (kindBody.isEmpty ? workspaceLabel : '$workspaceLabel · $kindBody');
    final workspaceId = attribution?.workspaceId ?? '';
    // Deep-link straight to the seat's session tab so the tap lands on the
    // very terminal that needs attention, not just its workspace. Seats that
    // are not chat sessions supply their own route instead.
    final explicitLocation = attribution?.location.trim() ?? '';
    final payload = explicitLocation.isNotEmpty
        ? explicitLocation
        : (workspaceId.isEmpty
              ? ''
              : (notice.sessionId.trim().isEmpty
                    ? '/home-v2/workspace/$workspaceId'
                    : HomeWorkspaceRoute.sessionLocation(
                        workspaceId: workspaceId,
                        sessionId: notice.sessionId,
                      )));

    _recorder()?.record(
      title: title,
      message: body,
      variant: notice.kind == AgentNoticeKind.interrupted
          ? TpToastVariant.warning
          : TpToastVariant.success,
      payload: payload,
      source: AppNotificationSource.cli,
    );

    unawaited(
      _showSystemNotification(
        title: title,
        body: body,
        subtitle: fallbackTitle,
        payload: payload.isEmpty ? null : payload,
      ).catchError((_) {}),
    );
  }

  /// Split an [agentSeatKey] back into (sessionId, memberId); null if malformed.
  /// The key joins the two ids with a NUL separator (see [agentSeatKey]).
  static (String, String)? _splitSeatKey(String key) {
    final i = key.indexOf(String.fromCharCode(0));
    if (i < 0) return null;
    return (key.substring(0, i), key.substring(i + 1));
  }

  static AgentAttentionNotifyContext? _defaultResolveContext() {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return null;
    final l10n = context.l10n;
    final enabled = context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .notifyOnSessionIdle;
    return AgentAttentionNotifyContext(
      enabled: enabled,
      titles: {
        AgentNoticeKind.done: l10n.agentDoneNotificationTitle,
        AgentNoticeKind.interrupted: l10n.agentInterruptedNotificationTitle,
        AgentNoticeKind.waiting: l10n.agentWaitingNotificationTitle,
      },
      bodies: {
        AgentNoticeKind.done: l10n.agentDoneNotificationBody,
        AgentNoticeKind.interrupted: l10n.agentInterruptedNotificationBody,
        AgentNoticeKind.waiting: l10n.agentWaitingNotificationBody,
      },
    );
  }
}

class _AgentNotice {
  const _AgentNotice({
    required this.sessionId,
    required this.memberId,
    required this.kind,
  });

  final String sessionId;
  final String memberId;
  final AgentNoticeKind kind;
}
