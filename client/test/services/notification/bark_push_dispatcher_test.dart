import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/bark_push_settings.dart';
import 'package:teampilot/services/notification/bark_push_dispatcher.dart';
import 'package:teampilot/services/notification/bark_push_sender.dart';
import 'package:teampilot/services/pairing/agent_notice_message.dart';

void main() {
  group('BarkPushDispatcher', () {
    late List<Map<String, Object?>> sent;
    late BarkPushSender sender;

    setUp(() {
      sent = [];
      sender = BarkPushSender(
        client: MockClient((request) async {
          sent.add({'url': request.url.toString(), 'body': request.body});
          return http.Response('{"code":200}', 200);
        }),
      );
    });

    BarkPushDispatcher build({
      BarkPushMode mode = BarkPushMode.whenDisconnected,
      String deviceKey = 'key',
      bool connected = false,
    }) => BarkPushDispatcher(
      sender: sender,
      target: () => BarkPushTarget(
        mode: mode,
        serverUrl: 'https://bark.example',
        deviceKey: deviceKey,
      ),
      hasConnectedPhone: () => connected,
      resolveStrings: () => const BarkPushStrings(
        kindBodies: {
          PairingAgentNoticeKind.done: 'Agent finished a turn',
          PairingAgentNoticeKind.waiting: 'Agent needs permission',
          PairingAgentNoticeKind.interrupted: 'Agent was interrupted',
        },
      ),
    );

    PairingAgentNotice notice({
      PairingAgentNoticeKind kind = PairingAgentNoticeKind.done,
      String workspaceLabel = 'teampilot',
      String title = 'build',
    }) => PairingAgentNotice(
      kind: kind,
      seatId: 'ws:p1',
      workspaceId: 'ws-1',
      workspaceLabel: workspaceLabel,
      title: title,
    );

    /// One microtask drain: `handle` is sync and fires the send unawaited.
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('pushes when no phone is connected', () async {
      build().handle(notice());
      await settle();
      expect(sent, hasLength(1));
    });

    test(
      'workspace is the title, tab is the subtitle, workspace is the group',
      () async {
        // Two agents finishing at once produce identical bodies; the workspace and
        // tab are the only things that tell them apart on the lock screen.
        build().handle(notice(workspaceLabel: 'teampilot', title: 'claude'));
        await settle();

        final body = sent.single['body'] as String;
        expect(body, contains('"title":"teampilot"'));
        expect(body, contains('"subtitle":"claude"'));
        expect(body, contains('"group":"teampilot"'));
        expect(body, contains('Agent finished a turn'));
      },
    );

    test('falls back to the tab title when the workspace is unknown', () async {
      build().handle(notice(workspaceLabel: '', title: 'claude'));
      await settle();

      final body = sent.single['body'] as String;
      expect(body, contains('"title":"claude"'));
      expect(body, isNot(contains('"subtitle"')));
    });

    test(
      'whenDisconnected skips a push the connected phone already got',
      () async {
        build(connected: true).handle(notice());
        await settle();
        expect(sent, isEmpty);
      },
    );

    test('always pushes even with a phone connected', () async {
      build(mode: BarkPushMode.always, connected: true).handle(notice());
      await settle();
      expect(sent, hasLength(1));
    });

    test('off never pushes', () async {
      build(mode: BarkPushMode.off).handle(notice());
      await settle();
      expect(sent, isEmpty);
    });

    test('an unconfigured key never pushes, whatever the mode', () async {
      // The default mode is whenDisconnected, so a fresh install would otherwise
      // try to push to nobody on every notice.
      build(mode: BarkPushMode.always, deviceKey: '').handle(notice());
      await settle();
      expect(sent, isEmpty);
    });

    test('waiting and interrupted are pushed too, not just done', () async {
      final dispatcher = build();
      dispatcher.handle(notice(kind: PairingAgentNoticeKind.waiting));
      dispatcher.handle(notice(kind: PairingAgentNoticeKind.interrupted));
      await settle();

      expect(sent, hasLength(2));
      expect(sent.first['body'], contains('needs permission'));
      expect(sent.last['body'], contains('was interrupted'));
    });

    test('no localized copy yet (startup window) drops rather than pushing '
        'untranslated text', () async {
      BarkPushDispatcher(
        sender: sender,
        target: () => const BarkPushTarget(
          mode: BarkPushMode.always,
          serverUrl: 'https://bark.example',
          deviceKey: 'key',
        ),
        hasConnectedPhone: () => false,
        resolveStrings: () => null,
      ).handle(notice());
      await settle();

      expect(sent, isEmpty);
    });
  });
}
