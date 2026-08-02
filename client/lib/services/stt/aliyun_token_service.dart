import 'dart:convert';

import 'package:http/http.dart' as http;

import 'aliyun_signature.dart';
import 'stt_provider.dart';

/// Mints and caches the short-lived token the NLS WebSocket gateway wants.
///
/// The AccessKey pair never goes near the socket: it signs one RPC here, and
/// only the resulting token travels in the WebSocket URL.
class AliyunTokenService {
  AliyunTokenService({
    required http.Client client,
    required String Function() nonceFactory,
    required DateTime Function() now,
  }) : _client = client,
       _nonceFactory = nonceFactory,
       _now = now;

  static const _endpoint = 'https://nls-meta.cn-shanghai.aliyuncs.com/';

  /// Renew this early so a token cannot expire mid-handshake.
  static const _renewMargin = Duration(minutes: 1);

  final http.Client _client;
  final String Function() _nonceFactory;
  final DateTime Function() _now;

  String? _token;
  DateTime? _expiresAt;
  String? _cachedForKeyId;

  Future<String> getToken({
    required String accessKeyId,
    required String accessKeySecret,
  }) async {
    if (_token != null &&
        _cachedForKeyId == accessKeyId &&
        _expiresAt != null &&
        _now().add(_renewMargin).isBefore(_expiresAt!)) {
      return _token!;
    }

    final params = <String, String>{
      'AccessKeyId': accessKeyId,
      'Action': 'CreateToken',
      'Format': 'JSON',
      'RegionId': 'cn-shanghai',
      'SignatureMethod': 'HMAC-SHA1',
      'SignatureNonce': _nonceFactory(),
      'SignatureVersion': '1.0',
      'Timestamp': _timestamp(_now()),
      'Version': '2019-02-28',
    };

    final signature = aliyunSignature(params, accessKeySecret);
    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {...params, 'Signature': signature},
    );

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw SttException(
        'Alibaba CreateToken failed: ${response.statusCode}',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException catch (_) {
      throw const SttException('Alibaba CreateToken returned a malformed body');
    }

    final token = body['Token'];
    if (token is! Map) {
      throw const SttException('Alibaba CreateToken returned no token');
    }
    final id = token['Id'];
    final expire = token['ExpireTime'];
    if (id is! String || id.isEmpty || expire is! int) {
      throw const SttException('Alibaba CreateToken returned no token');
    }

    _token = id;
    _expiresAt = DateTime.fromMillisecondsSinceEpoch(expire * 1000, isUtc: true);
    _cachedForKeyId = accessKeyId;
    return id;
  }

  String _timestamp(DateTime at) {
    final u = at.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)}'
        'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
  }
}
