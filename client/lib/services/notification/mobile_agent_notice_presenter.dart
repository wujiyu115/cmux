import 'dart:async';

import '../../l10n/l10n_extensions.dart';
import '../../router/app_router.dart';
import '../pairing/agent_notice_message.dart';
import 'desktop_system_notifier.dart';

/// Payload prefix for a notification that should open a mirrored pane. Not a
/// go_router location: mobile has no routes (the pairing shell switches on the
/// cubit's phase), and `handleSessionIdleNotificationTap` only accepts
/// `/home-v2/workspace/…`, which is a desktop route.
const kPairingMirrorPayloadPrefix = 'pairing-mirror:';

/// Localized copy for one notify pass, resolved on the phone so a zh phone
/// paired to an en desktop reads Chinese.
class MobileAgentNoticeStrings {
  const MobileAgentNoticeStrings({required this.titles, required this.bodies});

  final Map<PairingAgentNoticeKind, String> titles;
  final Map<PairingAgentNoticeKind, String> bodies;
}

/// Pops a local notification on the phone for an agent notice pushed by the
/// paired desktop. Mobile counterpart of `AgentAttentionNotificationService`'s
/// `_emit`, kept in the same composition order so both platforms read alike.
///
/// Only ever fires while the pairing client is connected — the LAN socket dies
/// when the phone backgrounds and there is no keepalive, reconnect, or backlog,
/// so notices raised while the phone sleeps are lost by design.
class MobileAgentNoticePresenter {
  MobileAgentNoticePresenter({
    Future<void> Function({
      required String title,
      required String body,
      String? subtitle,
      String? payload,
    })?
    show,
    MobileAgentNoticeStrings? Function()? resolveStrings,
  }) : _show = show ?? DesktopSystemNotifier.instance.showNotification,
       _resolveStrings = resolveStrings ?? _defaultResolveStrings;

  final Future<void> Function({
    required String title,
    required String body,
    String? subtitle,
    String? payload,
  })
  _show;
  final MobileAgentNoticeStrings? Function() _resolveStrings;

  void show(PairingAgentNotice notice) {
    final strings = _resolveStrings();
    // No live app context (startup / teardown window): drop rather than notify
    // with untranslated copy.
    if (strings == null) return;

    final kindTitle = strings.titles[notice.kind] ?? '';
    final kindBody = strings.bodies[notice.kind] ?? '';
    final title = notice.title.isNotEmpty ? notice.title : kindTitle;
    final label = notice.workspaceLabel;
    final body = label.isEmpty
        ? kindBody
        : (kindBody.isEmpty ? label : '$label · $kindBody');

    unawaited(
      _show(
        title: title,
        body: body,
        subtitle: kindTitle,
        // Null for seats the host cannot mirror (chat session tabs, dead panes):
        // the tap then only foregrounds the app.
        payload: notice.isMirrorable
            ? '$kPairingMirrorPayloadPrefix${notice.catalogId}'
            : null,
      ).catchError((_) {}),
    );
  }

  static MobileAgentNoticeStrings? _defaultResolveStrings() {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return null;
    final l10n = context.l10n;
    return MobileAgentNoticeStrings(
      titles: {
        PairingAgentNoticeKind.done: l10n.agentDoneNotificationTitle,
        PairingAgentNoticeKind.interrupted:
            l10n.agentInterruptedNotificationTitle,
        PairingAgentNoticeKind.waiting: l10n.agentWaitingNotificationTitle,
      },
      bodies: {
        PairingAgentNoticeKind.done: l10n.agentDoneNotificationBody,
        PairingAgentNoticeKind.interrupted:
            l10n.agentInterruptedNotificationBody,
        PairingAgentNoticeKind.waiting: l10n.agentWaitingNotificationBody,
      },
    );
  }
}
