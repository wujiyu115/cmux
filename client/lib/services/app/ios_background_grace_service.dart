import 'dart:io';

import 'package:flutter/services.dart';

import '../../utils/logging/logger.dart';

/// Extends the iOS background execution window while the app is backgrounded.
///
/// iOS suspends the process a few seconds after the UI leaves the screen; a
/// `beginBackgroundTask` assertion stretches that to ~30s, covering the
/// "switch away briefly and come right back" pattern without any background
/// entitlement. The pairing mirror's keep-alive pings keep flowing during the
/// window. [end] must be called on foreground return — the native side owns
/// the task id, so an assertion that expired while backgrounded is simply
/// never re-ended (re-used ids cannot be killed by a stale call).
class IosBackgroundGraceService {
  IosBackgroundGraceService({MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('teampilot/background_grace'),
      _enabled = enabled ?? Platform.isIOS;

  final MethodChannel _channel;
  final bool _enabled;

  bool _held = false;
  bool get isHeld => _held;

  /// Starts a background task assertion. No-op when disabled (non-iOS) or one
  /// is already held.
  Future<void> begin() async {
    if (!_enabled || _held) return;
    try {
      final granted = await _channel.invokeMethod<int>('beginBackgroundTask');
      _held = granted != null && granted >= 0;
      if (_held) {
        appLogger.d('[background-grace] assertion held');
      } else {
        appLogger.d('[background-grace] no background time granted');
      }
    } on MissingPluginException {
      appLogger.d('[background-grace] native handler missing');
    } on PlatformException catch (e) {
      appLogger.d('[background-grace] begin failed: ${e.message}');
    }
  }

  /// Releases the assertion. Safe when none is held.
  Future<void> end() async {
    if (!_enabled || !_held) return;
    _held = false;
    try {
      await _channel.invokeMethod<void>('endBackgroundTask');
    } on MissingPluginException {
      // Process teardown or engine not ready; nothing to recover.
    } on PlatformException catch (e) {
      appLogger.d('[background-grace] end failed: ${e.message}');
    }
  }
}
