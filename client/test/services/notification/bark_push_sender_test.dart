import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/notification/bark_push_sender.dart';

void main() {
  group('BarkPushSender', () {
    test('posts the notice fields to <server>/push as JSON', () async {
      http.Request? seen;
      final sender = BarkPushSender(
        client: MockClient((request) async {
          seen = request;
          return http.Response('{"code":200,"message":"success"}', 200);
        }),
      );

      final result = await sender.send(
        serverUrl: 'https://bark.example',
        deviceKey: 'abc123',
        title: 'teampilot',
        subtitle: 'build',
        body: 'Agent finished',
        group: 'teampilot',
      );

      expect(result.ok, isTrue);
      expect(seen!.url.toString(), 'https://bark.example/push');
      final body = jsonDecode(seen!.body) as Map<String, Object?>;
      expect(body['device_key'], 'abc123');
      expect(body['title'], 'teampilot');
      expect(body['subtitle'], 'build');
      expect(body['body'], 'Agent finished');
      expect(body['group'], 'teampilot');
    });

    test(
      'omits subtitle and group when empty rather than sending blanks',
      () async {
        http.Request? seen;
        final sender = BarkPushSender(
          client: MockClient((request) async {
            seen = request;
            return http.Response('{"code":200}', 200);
          }),
        );

        await sender.send(
          serverUrl: 'https://bark.example',
          deviceKey: 'k',
          title: 'build',
          body: 'done',
        );

        final body = jsonDecode(seen!.body) as Map<String, Object?>;
        expect(body.containsKey('subtitle'), isFalse);
        expect(body.containsKey('group'), isFalse);
      },
    );

    test(
      'a 200 carrying a non-200 code is a failure, with Bark\'s message',
      () async {
        // The common real failure: the device key was revoked or mistyped. Bark
        // reports it inside a 200, so the HTTP status alone is not the verdict.
        final sender = BarkPushSender(
          client: MockClient(
            (_) async => http.Response(
              '{"code":400,"message":"failed to get device token"}',
              200,
            ),
          ),
        );

        final result = await sender.send(
          serverUrl: 'https://bark.example',
          deviceKey: 'stale',
          title: 't',
          body: 'b',
        );

        expect(result.ok, isFalse);
        expect(result.failure, 'failed to get device token');
      },
    );

    test('a non-200 status fails and quotes the body', () async {
      final sender = BarkPushSender(
        client: MockClient((_) async => http.Response('nope', 502)),
      );

      final result = await sender.send(
        serverUrl: 'https://bark.example',
        deviceKey: 'k',
        title: 't',
        body: 'b',
      );

      expect(result.failure, contains('502'));
      expect(result.failure, contains('nope'));
    });

    test('a 200 with an unparseable body counts as delivered', () async {
      // A Bark-shaped server we do not recognize; do not cry wolf.
      final sender = BarkPushSender(
        client: MockClient((_) async => http.Response('OK', 200)),
      );

      final result = await sender.send(
        serverUrl: 'https://bark.example',
        deviceKey: 'k',
        title: 't',
        body: 'b',
      );

      expect(result.ok, isTrue);
    });

    test('an empty device key fails without touching the network', () async {
      var calls = 0;
      final sender = BarkPushSender(
        client: MockClient((_) async {
          calls++;
          return http.Response('{"code":200}', 200);
        }),
      );

      final result = await sender.send(
        serverUrl: 'https://bark.example',
        deviceKey: '   ',
        title: 't',
        body: 'b',
      );

      expect(result.ok, isFalse);
      expect(calls, 0);
    });

    test(
      'a server URL with no scheme fails with the URL in the message',
      () async {
        final sender = BarkPushSender(
          client: MockClient((_) async => http.Response('{"code":200}', 200)),
        );

        final result = await sender.send(
          serverUrl: 'bark.example',
          deviceKey: 'k',
          title: 't',
          body: 'b',
        );

        expect(result.ok, isFalse);
        expect(result.failure, contains('bark.example'));
      },
    );

    test('a transport error is reported, not thrown', () async {
      final sender = BarkPushSender(
        client: MockClient((_) async => throw http.ClientException('no route')),
      );

      final result = await sender.send(
        serverUrl: 'https://bark.example',
        deviceKey: 'k',
        title: 't',
        body: 'b',
      );

      expect(result.ok, isFalse);
      expect(result.failure, contains('no route'));
    });
  });
}
