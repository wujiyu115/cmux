import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Exactly the unreserved set Alibaba's RPC signing requires. Dart's own
/// `Uri.encodeComponent` / `encodeQueryComponent` pass `!*'()` through and turn
/// a space into `+`, either of which signs a different string than the server
/// reconstructs — the failure surfaces as SignatureDoesNotMatch with nothing to
/// point at.
const _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~';

/// Percent-encodes [input] per Alibaba's RPC rules: UTF-8 bytes, uppercase hex.
String aliyunPercentEncode(String input) {
  final out = StringBuffer();
  for (final byte in utf8.encode(input)) {
    final char = String.fromCharCode(byte);
    if (_unreserved.contains(char)) {
      out.write(char);
    } else {
      out.write('%');
      out.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return out.toString();
}

/// Builds the canonical string an Alibaba RPC GET signature covers.
///
/// Any `Signature` already in [params] is dropped: signing over a previous
/// signature is never correct and would make a retry unverifiable.
String aliyunStringToSign(Map<String, String> params) {
  final keys = params.keys.where((k) => k != 'Signature').toList()..sort();
  final canonical = keys
      .map((k) => '${aliyunPercentEncode(k)}=${aliyunPercentEncode(params[k]!)}')
      .join('&');
  return 'GET&${aliyunPercentEncode('/')}&${aliyunPercentEncode(canonical)}';
}

/// HMAC-SHA1 over [aliyunStringToSign], keyed by the secret with a trailing `&`
/// (the RPC scheme's empty second key component), base64 encoded.
String aliyunSignature(Map<String, String> params, String accessKeySecret) {
  final mac = Hmac(sha1, utf8.encode('$accessKeySecret&'));
  return base64Encode(
    mac.convert(utf8.encode(aliyunStringToSign(params))).bytes,
  );
}
