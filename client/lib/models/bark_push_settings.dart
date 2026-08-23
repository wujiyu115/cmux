import 'package:flutter/foundation.dart';

/// When the desktop forwards agent notices to Bark.
///
/// [whenDisconnected] is the default: a phone with a live pairing connection
/// already pops its own local notification from the `agent.notice` frame, so a
/// push on top of that is the same event twice. [always] trades that duplicate
/// for not depending on the connection state being accurate.
enum BarkPushMode {
  off,
  whenDisconnected,
  always;

  static BarkPushMode fromName(Object? raw) => BarkPushMode.values.firstWhere(
    (mode) => mode.name == raw,
    orElse: () => BarkPushMode.whenDisconnected,
  );
}

/// The non-secret half of the Bark push channel. The device key is a bearer
/// capability — anyone holding it can push to that phone — so it lives in the
/// keychain instead, alongside the SSH secrets; see `BarkPushRepository`.
@immutable
class BarkPushSettings {
  const BarkPushSettings({
    this.mode = BarkPushMode.whenDisconnected,
    this.serverUrl = defaultServerUrl,
  });

  /// Bark's hosted relay. Self-hosters replace it; the path (`/push`) is added
  /// by the sender, so this is an origin, not an endpoint.
  static const defaultServerUrl = 'https://api.day.app';

  static const defaults = BarkPushSettings();

  final BarkPushMode mode;
  final String serverUrl;

  /// Trimmed origin with any trailing slashes removed, or the default when the
  /// user cleared the field. Empty is never a usable server, and silently
  /// falling back beats failing every push with a confusing URL error.
  String get normalizedServerUrl {
    final trimmed = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return trimmed.isEmpty ? defaultServerUrl : trimmed;
  }

  BarkPushSettings copyWith({BarkPushMode? mode, String? serverUrl}) =>
      BarkPushSettings(
        mode: mode ?? this.mode,
        serverUrl: serverUrl ?? this.serverUrl,
      );

  Map<String, Object?> toJson() => {'mode': mode.name, 'serverUrl': serverUrl};

  factory BarkPushSettings.fromJson(Map<String, Object?> json) {
    final url = json['serverUrl'];
    return BarkPushSettings(
      mode: BarkPushMode.fromName(json['mode']),
      serverUrl: url is String && url.trim().isNotEmpty
          ? url
          : defaultServerUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BarkPushSettings &&
      other.mode == mode &&
      other.serverUrl == serverUrl;

  @override
  int get hashCode => Object.hash(mode, serverUrl);
}
