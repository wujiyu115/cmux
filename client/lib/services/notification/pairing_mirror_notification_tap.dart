import 'mobile_agent_notice_presenter.dart';

/// True when [payload] came from a forwarded agent notice, so the mobile tap
/// handler owns it instead of the desktop session-idle one.
bool isPairingMirrorPayload(String? payload) =>
    (payload?.trim() ?? '').startsWith(kPairingMirrorPayloadPrefix);

/// Handles a tapped agent notification on the phone: opens the mirror the host
/// named. Separate from `handleSessionIdleNotificationTap` because the two have
/// different contracts and collaborators (`go` vs `openMirror`).
///
/// Hot start only. `DesktopSystemNotifier.ensureInitialized` never consumes
/// `getNotificationAppLaunchDetails`, so a tap that launches a killed app just
/// lands on the paired-hosts list.
Future<void> handlePairingMirrorNotificationTap({
  required String? payload,
  required Future<void> Function(String catalogId) openMirror,
}) async {
  final raw = payload?.trim() ?? '';
  if (!raw.startsWith(kPairingMirrorPayloadPrefix)) return;
  final catalogId = raw.substring(kPairingMirrorPayloadPrefix.length).trim();
  if (catalogId.isEmpty) return;
  await openMirror(catalogId);
}
