/// Handles OS notification taps for session-idle deep links (hot start only).
Future<void> handleSessionIdleNotificationTap({
  required String? payload,
  required void Function(String location) go,
  Future<void> Function(String location)? markReadMatchingPayload,
  Future<void> Function()? focusWindow,
}) async {
  final location = payload?.trim() ?? '';
  if (location.isEmpty) return;
  if (!location.startsWith('/home-v2/workspace/')) return;

  // Both collaborators are best-effort side effects; navigation is the
  // invariant. `focusWindow` in particular reaches window_manager, which has no
  // iOS/Android implementation and throws MissingPluginException there.
  try {
    await markReadMatchingPayload?.call(location);
  } on Object catch (_) {}
  try {
    await focusWindow?.call();
  } on Object catch (_) {}
  go(location);
}
