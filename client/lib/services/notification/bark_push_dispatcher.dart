import 'dart:async';

import '../../l10n/l10n_extensions.dart';
import '../../models/bark_push_settings.dart';
import '../../router/app_router.dart';
import '../pairing/agent_notice_message.dart';
import 'bark_push_sender.dart';

/// The push channel's live configuration, read fresh on every notice so a change
/// in settings takes effect without restarting anything.
class BarkPushTarget {
  const BarkPushTarget({
    required this.mode,
    required this.serverUrl,
    required this.deviceKey,
  });

  final BarkPushMode mode;
  final String serverUrl;
  final String deviceKey;

  /// A configured channel. Mode alone is not enough: the default mode is
  /// [BarkPushMode.whenDisconnected], so a fresh install would otherwise "want"
  /// to push with no key to push to.
  bool get isUsable =>
      mode != BarkPushMode.off &&
      deviceKey.trim().isNotEmpty &&
      serverUrl.trim().isNotEmpty;
}

/// Localized per-kind copy, resolved on the desktop because Bark carries plain
/// text — unlike the paired-phone path, there is no client to render it.
class BarkPushStrings {
  const BarkPushStrings({required this.kindBodies});

  final Map<PairingAgentNoticeKind, String> kindBodies;
}

/// Forwards agent notices to Bark so the phone hears about a finished turn, an
/// interruption, or a permission prompt **without a live pairing connection**.
///
/// All three kinds go out. `waiting` matters most of the three away from the
/// desk: the agent is blocked until someone answers, and nothing else will say
/// so once the LAN socket is gone.
///
/// Reads the same notice stream that feeds paired phones, which is why it sits
/// downstream of `notifyOnSessionIdle` — that master switch has already been
/// applied by the time a notice reaches here.
class BarkPushDispatcher {
  BarkPushDispatcher({
    required BarkPushSender sender,
    required BarkPushTarget Function() target,
    required bool Function() hasConnectedPhone,
    BarkPushStrings? Function()? resolveStrings,
  }) : _sender = sender,
       _target = target,
       _hasConnectedPhone = hasConnectedPhone,
       _resolveStrings = resolveStrings ?? _defaultResolveStrings;

  final BarkPushSender _sender;
  final BarkPushTarget Function() _target;

  /// Whether some phone is authenticated on the pairing host right now. Such a
  /// phone pops its own local notice from the `agent.notice` frame, so pushing
  /// as well would deliver the same event twice — see
  /// [BarkPushMode.whenDisconnected].
  final bool Function() _hasConnectedPhone;
  final BarkPushStrings? Function() _resolveStrings;

  /// Fire-and-forget: a slow or unreachable Bark server must not hold up the
  /// desktop's own notification, and there is nothing useful to do with a
  /// failure here (the settings page's test button is where errors are surfaced).
  void handle(PairingAgentNotice notice) {
    final target = _target();
    if (!target.isUsable) return;
    if (target.mode == BarkPushMode.whenDisconnected && _hasConnectedPhone()) {
      return;
    }
    final strings = _resolveStrings();
    if (strings == null) return;

    // Workspace headlines and the tab title is the subtitle: with several agents
    // running, "which workspace" is the first thing that distinguishes two
    // otherwise identical "turn finished" pushes, and the tab title separates
    // two panes inside one workspace. Grouped by workspace so Bark's own history
    // folds them the same way.
    final workspace = notice.workspaceLabel.trim();
    final tab = notice.title.trim();
    final kindBody = strings.kindBodies[notice.kind] ?? '';
    unawaited(
      _sender.send(
        serverUrl: target.serverUrl,
        deviceKey: target.deviceKey,
        title: workspace.isNotEmpty ? workspace : tab,
        subtitle: workspace.isNotEmpty ? tab : '',
        body: kindBody,
        group: workspace,
      ),
    );
  }

  static BarkPushStrings? _defaultResolveStrings() {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return null;
    final l10n = context.l10n;
    return BarkPushStrings(
      kindBodies: {
        PairingAgentNoticeKind.done: l10n.agentDoneNotificationBody,
        PairingAgentNoticeKind.interrupted:
            l10n.agentInterruptedNotificationBody,
        PairingAgentNoticeKind.waiting: l10n.agentWaitingNotificationBody,
      },
    );
  }
}
