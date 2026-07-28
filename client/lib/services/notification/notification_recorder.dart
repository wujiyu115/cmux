import 'package:shared_ui/shared_ui.dart';

import '../../models/app_notification.dart';

/// Hook for [AppToast] to persist notifications without importing cubits.
abstract interface class NotificationRecorder {
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
    AppNotificationSource source = AppNotificationSource.app,
  });

  static NotificationRecorder? _current;

  static NotificationRecorder? get maybeCurrent => _current;

  static void install(NotificationRecorder? recorder) {
    _current = recorder;
  }
}
