import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/app/error_log_service.dart';
import 'logger_utils.dart';

export 'logger_utils.dart' show AppLogger;

/// App-wide logger — [AppLogger.instance] is the single implementation.
final appLogger = AppLogger.instance;

/// Initializes global Flutter error hooks, and the rotating file log when
/// [fileLogging] is on.
///
/// [fileLogging] comes from `DebugLogSettings` and is off by default; the console
/// sink and the error hooks are unconditional, so turning disk logs off costs no
/// diagnostics on a developer machine.
Future<void> initAppLogging(
  String appDataRoot, {
  required bool fileLogging,
}) async {
  await AppLogger.instance.setFileLoggingEnabled(
    fileLogging,
    appDataRoot: appDataRoot,
  );
  await ErrorLogService.instance.initialize(appDataRoot: appDataRoot);

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    final error = details.exception;
    final stack = details.stack ?? StackTrace.current;
    AppLogger.instance.e(
      '[FlutterError] ${details.summary}',
      error: error,
      stackTrace: stack,
      recordError: false,
    );
    unawaited(
      ErrorLogService.instance.recordError(
        error,
        stack,
        module: 'flutter',
        action: details.library ?? 'framework',
        context: details.context?.toString(),
      ),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.instance.e(
      '[PlatformDispatcher] unhandled async error',
      error: error,
      stackTrace: stack,
      recordError: false,
    );
    unawaited(
      ErrorLogService.instance.recordError(
        error,
        stack,
        module: 'async',
        action: 'unhandled',
      ),
    );
    return true;
  };
}
