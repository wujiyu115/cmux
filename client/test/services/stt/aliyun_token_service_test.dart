import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/stt/aliyun_token_service.dart';
import 'package:teampilot/services/stt/stt_provider.dart';

void main() {
  /// Unix seconds, as the CreateToken response reports expiry.
  int secondsSinceEpoch(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

  late DateTime now;
  late List<Uri> requested;

  setUp(() {
    now = DateTime.utc(2026, 8, 2, 12);
    requested = [];
  });

  /// A CreateToken endpoint that always succeeds, expiring [ttl] from [now].
  MockClient okClient({Duration ttl = const Duration(hours: 1)}) {
    return MockClient((request) async {
      requested.add(request.url);
      return http.Response(
        jsonEncode({
          'Token': {
            'Id': 'token-${requested.length}',
            'ExpireTime': secondsSinceEpoch(now.add(ttl)),
          },
        }),
        200,
      );
    });
  }

  AliyunTokenService serviceWith(http.Client client) => AliyunTokenService(
    client: client,
    nonceFactory: () => 'fixed-nonce',
    now: () => now,
  );

  test('returns the token id from the response', () async {
    final service = serviceWith(okClient());
    final token = await service.getToken(
      accessKeyId: 'id',
      accessKeySecret: 'secret',
    );
    expect(token, 'token-1');
  });

  test('signs the request with the documented parameter set', () async {
    final service = serviceWith(okClient());
    await service.getToken(accessKeyId: 'id', accessKeySecret: 'secret');
    final query = requested.single.queryParameters;
    expect(requested.single.host, 'nls-meta.cn-shanghai.aliyuncs.com');
    expect(query['Action'], 'CreateToken');
    expect(query['Version'], '2019-02-28');
    expect(query['AccessKeyId'], 'id');
    expect(query['SignatureMethod'], 'HMAC-SHA1');
    expect(query['SignatureVersion'], '1.0');
    expect(query['SignatureNonce'], 'fixed-nonce');
    // Second-precision UTC, no fractional part — the gateway rejects anything
    // else with an InvalidTimeStamp error.
    expect(query['Timestamp'], '2026-08-02T12:00:00Z');
    expect(query['Signature'], isNotEmpty);
  });

  test('reuses a cached token instead of signing again', () async {
    final service = serviceWith(okClient());
    await service.getToken(accessKeyId: 'id', accessKeySecret: 'secret');
    final second = await service.getToken(
      accessKeyId: 'id',
      accessKeySecret: 'secret',
    );
    expect(second, 'token-1');
    expect(requested, hasLength(1));
  });

  test('refetches once the cached token is near expiry', () async {
    final service = serviceWith(okClient(ttl: const Duration(minutes: 10)));
    await service.getToken(accessKeyId: 'id', accessKeySecret: 'secret');
    now = now.add(const Duration(minutes: 10));
    final second = await service.getToken(
      accessKeyId: 'id',
      accessKeySecret: 'secret',
    );
    expect(second, 'token-2');
    expect(requested, hasLength(2));
  });

  test('refetches when the credentials change', () async {
    // A cached token belongs to the key that minted it; handing it to a new key
    // pair would fail the WebSocket handshake with a stale-token error that
    // looks like a code bug.
    final service = serviceWith(okClient());
    await service.getToken(accessKeyId: 'id', accessKeySecret: 'secret');
    final second = await service.getToken(
      accessKeyId: 'other',
      accessKeySecret: 'secret',
    );
    expect(second, 'token-2');
    expect(requested, hasLength(2));
  });

  test('throws SttException on a non-200 response', () async {
    final service = serviceWith(
      MockClient((_) async => http.Response('{"Message":"denied"}', 403)),
    );
    await expectLater(
      service.getToken(accessKeyId: 'id', accessKeySecret: 'bad'),
      throwsA(isA<SttException>()),
    );
  });

  test('throws SttException when the body carries no token', () async {
    final service = serviceWith(
      MockClient((_) async => http.Response('{"Token":{}}', 200)),
    );
    await expectLater(
      service.getToken(accessKeyId: 'id', accessKeySecret: 'secret'),
      throwsA(isA<SttException>()),
    );
  });

  test('throws SttException on a malformed body', () async {
    final service = serviceWith(
      MockClient((_) async => http.Response('not json', 200)),
    );
    await expectLater(
      service.getToken(accessKeyId: 'id', accessKeySecret: 'secret'),
      throwsA(isA<SttException>()),
    );
  });
}
