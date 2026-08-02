import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/stt/aliyun_signature.dart';

void main() {
  group('aliyunPercentEncode', () {
    test('leaves only the unreserved set alone', () {
      expect(aliyunPercentEncode('aZ09-_.~'), 'aZ09-_.~');
    });

    test('encodes the characters Uri.encodeComponent lets through', () {
      // Dart's own encoders pass !*'() straight through; Alibaba's canonical
      // form requires them escaped, so a stock encoder silently signs the wrong
      // string and every request comes back SignatureDoesNotMatch.
      expect(aliyunPercentEncode("!*'()"), '%21%2A%27%28%29');
    });

    test('encodes space as %20, never +', () {
      expect(aliyunPercentEncode('a b'), 'a%20b');
    });

    test('encodes / and & and =', () {
      expect(aliyunPercentEncode('/'), '%2F');
      expect(aliyunPercentEncode('a&b=c'), 'a%26b%3Dc');
    });

    test('encodes multi-byte UTF-8 per byte in uppercase hex', () {
      expect(aliyunPercentEncode('中'), '%E4%B8%AD');
    });
  });

  group('aliyunStringToSign', () {
    test('sorts params, joins with &, then encodes the whole query once', () {
      final stringToSign = aliyunStringToSign({
        'Version': '2019-02-28',
        'Action': 'CreateToken',
        'Format': 'JSON',
      });
      // Sorted: Action, Format, Version. The inner = and & are encoded by the
      // outer pass, which is what makes this a single deterministic string.
      expect(
        stringToSign,
        'GET&%2F&Action%3DCreateToken%26Format%3DJSON%26Version%3D2019-02-28',
      );
    });

    test('excludes any Signature already present', () {
      final stringToSign = aliyunStringToSign({
        'Action': 'CreateToken',
        'Signature': 'stale',
      });
      expect(stringToSign, 'GET&%2F&Action%3DCreateToken');
    });
  });

  group('aliyunSignature', () {
    test('is HMAC-SHA1 over the stringToSign, keyed by secret + &', () {
      const params = {'Action': 'CreateToken', 'Format': 'JSON'};
      const secret = 'testsecret';
      // Recomputing the one-line formula here is deliberate. What this pins is
      // the wiring, which is where this signing scheme actually goes wrong:
      // that the HMAC covers the stringToSign (not the raw query), that the key
      // is secret + '&' (not the bare secret), that it is SHA-1 (not SHA-256),
      // and that the digest is base64 (not hex).
      final expected = base64Encode(
        Hmac(sha1, utf8.encode('$secret&'))
            .convert(utf8.encode(aliyunStringToSign(params)))
            .bytes,
      );
      expect(aliyunSignature(params, secret), expected);
    });

    test('changes when the secret changes', () {
      const params = {'Action': 'CreateToken'};
      expect(
        aliyunSignature(params, 'one'),
        isNot(aliyunSignature(params, 'two')),
      );
    });

    test('is independent of the input map order', () {
      const secret = 'testsecret';
      expect(
        aliyunSignature({'B': '2', 'A': '1'}, secret),
        aliyunSignature({'A': '1', 'B': '2'}, secret),
      );
    });
  });
}
