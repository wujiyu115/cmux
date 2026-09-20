import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../router/app_router.dart';
import '../../services/notification/notification_recorder.dart';

/// TeamPilot transient feedback — product facade over [TpToast].
abstract final class AppToast {
  static DateTime? _lastGlobalShownAt;
  static String? _lastGlobalMessage;

  /// Shows a toast when [context] is available.
  ///
  /// [record] controls whether a non-info toast is also persisted into the
  /// notification center. Feedback-only confirmations (clipboard copies and
  /// similar echo actions) pass `false`: the user just performed the action
  /// and knows it — a notification-list entry is noise.
  static void show(
    BuildContext context, {
    required String message,
    TpToastVariant variant = TpToastVariant.info,
    TpToastAction? action,
    Duration? duration,
    bool record = true,
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty || !context.mounted) return;

    _present(
      context: context,
      message: trimmed,
      variant: variant,
      action: action,
      duration: duration,
      record: record,
    );
  }

  /// Shows a toast without [BuildContext] (services, error utils).
  static void showGlobal({
    required String message,
    TpToastVariant variant = TpToastVariant.info,
    TpToastAction? action,
    Duration? duration,
    bool deduplicate = true,
    bool record = true,
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    if (deduplicate) {
      final now = DateTime.now();
      if (_lastGlobalMessage == trimmed &&
          _lastGlobalShownAt != null &&
          now.difference(_lastGlobalShownAt!) < const Duration(seconds: 2)) {
        return;
      }
      _lastGlobalMessage = trimmed;
      _lastGlobalShownAt = now;
    }

    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    _present(
      context: context,
      message: trimmed,
      variant: variant,
      action: action,
      duration: duration,
      record: record,
    );
  }

  /// Dismisses any visible toast.
  static void dismiss() {
    TpToast.dismiss();
  }

  static void _present({
    required BuildContext context,
    required String message,
    required TpToastVariant variant,
    TpToastAction? action,
    Duration? duration,
    required bool record,
  }) {
    TpToast.show(
      context,
      message: message,
      variant: variant,
      action: action,
      duration: duration,
    );

    if (record && variant != TpToastVariant.info) {
      NotificationRecorder.maybeCurrent?.record(
        message: message,
        variant: variant,
      );
    }
  }
}

extension AppToastContext on BuildContext {
  void showAppToast(
    String message, {
    TpToastVariant variant = TpToastVariant.info,
    TpToastAction? action,
    Duration? duration,
    bool record = true,
  }) {
    AppToast.show(
      this,
      message: message,
      variant: variant,
      action: action,
      duration: duration,
      record: record,
    );
  }
}
