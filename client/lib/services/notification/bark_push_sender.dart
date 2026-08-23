import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/logging/logger.dart';

/// Outcome of one Bark push. [detail] is the server's own words (or the
/// transport error) and is shown verbatim next to the test button — a Bark
/// failure is almost always "device key not found", which no localized string of
/// ours could say more usefully.
class BarkPushResult {
  const BarkPushResult.ok() : failure = null;
  const BarkPushResult.failed(this.failure);

  final String? failure;

  bool get ok => failure == null;
}

/// Posts one notification to a Bark server (`POST <server>/push`).
///
/// The JSON body form is used rather than Bark's older
/// `GET /<key>/<title>/<body>` path form: notice titles carry workspace names,
/// which routinely contain `/`, `#`, and non-ASCII — all of which have to be
/// path-escaped exactly right in the URL form and silently truncate the body
/// when they are not.
class BarkPushSender {
  BarkPushSender({
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _timeout = timeout;

  final http.Client _client;
  final Duration _timeout;

  /// [title] / [subtitle] / [body] map onto Bark's three display fields; the
  /// caller decides what goes where. [group] is Bark's own grouping key in the
  /// phone's notification history.
  Future<BarkPushResult> send({
    required String serverUrl,
    required String deviceKey,
    required String title,
    required String body,
    String subtitle = '',
    String group = '',
  }) async {
    if (deviceKey.trim().isEmpty) {
      return const BarkPushResult.failed('missing device key');
    }
    final uri = Uri.tryParse('$serverUrl/push');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return BarkPushResult.failed('bad server URL: $serverUrl');
    }
    try {
      final response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'device_key': deviceKey.trim(),
              'title': title,
              if (subtitle.isNotEmpty) 'subtitle': subtitle,
              'body': body,
              if (group.isNotEmpty) 'group': group,
            }),
          )
          .timeout(_timeout);
      return _readResponse(response.statusCode, response.body);
    } on Object catch (e) {
      appLogger.d('[bark] push failed: $e');
      return BarkPushResult.failed('$e');
    }
  }

  /// Bark answers 200 with `{"code":200,...}` on success, and also uses 200 with
  /// a non-200 `code` for application errors (an unknown device key is the
  /// common one), so the HTTP status alone is not the verdict.
  static BarkPushResult _readResponse(int status, String body) {
    if (status != 200) {
      final trimmed = body.trim();
      return BarkPushResult.failed(
        trimmed.isEmpty ? 'HTTP $status' : 'HTTP $status: $trimmed',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on Object {
      // A 200 with an unparseable body is a Bark-shaped server we do not
      // recognize; treat it as delivered rather than crying wolf.
      return const BarkPushResult.ok();
    }
    if (decoded is! Map) return const BarkPushResult.ok();
    final code = decoded['code'];
    if (code is num && code.toInt() != 200) {
      final message = decoded['message'];
      return BarkPushResult.failed(
        message is String && message.trim().isNotEmpty
            ? message.trim()
            : 'code $code',
      );
    }
    return const BarkPushResult.ok();
  }

  void close() => _client.close();
}
