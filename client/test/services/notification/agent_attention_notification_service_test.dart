import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/notification/agent_attention_notification_service.dart';

class _Emit {
  _Emit(this.title, this.body, this.subtitle, this.payload);
  final String title;
  final String body;
  final String? subtitle;
  final String? payload;
}

void main() {
  late AgentAttentionCubit attention;
  late List<_Emit> emitted;
  bool focused = false;
  bool enabled = true;
  String foregroundSession = '';
  AgentNoticeAttribution? Function(String, String) attribution =
      (_, __) => null;

  AgentAttentionNotificationService build() => AgentAttentionNotificationService(
    attention: attention,
    isAppFocused: () async => focused,
    isForegroundSeat: (sessionId, memberId) => sessionId == foregroundSession,
    showSystemNotification:
        ({required title, required body, subtitle, payload}) async {
          emitted.add(_Emit(title, body, subtitle, payload));
        },
    recorder: () => null,
    resolveContext: () => enabled
        ? const AgentAttentionNotifyContext(
            enabled: true,
            titles: {
              AgentNoticeKind.done: 'done',
              AgentNoticeKind.interrupted: 'interrupted',
              AgentNoticeKind.waiting: 'waiting',
            },
            bodies: {
              AgentNoticeKind.done: 'done-body',
              AgentNoticeKind.interrupted: 'interrupted-body',
              AgentNoticeKind.waiting: 'waiting-body',
            },
          )
        : const AgentAttentionNotifyContext(
            enabled: false,
            titles: {},
            bodies: {},
          ),
    resolveAttribution: attribution,
  );

  void apply(String event, {bool interrupt = false}) {
    attention.applyEvent(
      sessionId: 's1',
      memberId: 's1',
      event: AgentStatusEvent(
        state: switch (event) {
          'done' => AgentSeatAttention.done,
          'waiting' => AgentSeatAttention.waiting,
          _ => AgentSeatAttention.working,
        },
        hookEventName: event,
        interrupted: interrupt,
      ),
      skipPermissions: false,
    );
  }

  setUp(() {
    attention = AgentAttentionCubit(pruneInterval: null);
    emitted = [];
    focused = false;
    enabled = true;
    foregroundSession = '';
    attribution = (_, __) => null;
  });

  tearDown(() => attention.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('working → done fires the done notice', () async {
    build().start();
    apply('working');
    await settle();
    apply('done');
    await settle();

    expect(emitted, hasLength(1));
    expect(emitted.single.body, 'done-body');
  });

  test('done via interrupt fires the interrupted notice', () async {
    build().start();
    apply('working');
    await settle();
    apply('done', interrupt: true);
    await settle();

    expect(emitted.single.body, 'interrupted-body');
  });

  test('→ waiting fires the waiting notice', () async {
    build().start();
    apply('waiting');
    await settle();

    expect(emitted.single.body, 'waiting-body');
  });

  test('same state does not re-fire', () async {
    build().start();
    apply('waiting');
    await settle();
    apply('waiting');
    await settle();

    expect(emitted, hasLength(1));
  });

  test('focused + foreground seat is suppressed', () async {
    focused = true;
    foregroundSession = 's1';
    build().start();
    apply('done');
    await settle();

    expect(emitted, isEmpty);
  });

  test('focused but not the foreground seat still fires', () async {
    focused = true;
    foregroundSession = 'other';
    build().start();
    apply('done');
    await settle();

    expect(emitted, hasLength(1));
  });

  test('attribution names the session and carries workspace in the body', () async {
    attribution = (_, __) => const AgentNoticeAttribution(
      title: 'Fix login bug',
      workspaceId: 'ws-1',
      workspaceLabel: 'my-repo',
    );
    build().start();
    apply('done');
    await settle();

    expect(emitted.single.title, 'Fix login bug');
    expect(emitted.single.body, 'my-repo · done-body');
    // Subtitle keeps the lifecycle label.
    expect(emitted.single.subtitle, 'done');
  });

  test('tap payload deep-links to the seat session tab', () async {
    attribution = (_, __) => const AgentNoticeAttribution(
      title: 'Fix login bug',
      workspaceId: 'ws-1',
      workspaceLabel: 'my-repo',
    );
    build().start();
    apply('done');
    await settle();

    expect(emitted.single.payload, '/home-v2/workspace/ws-1?session=s1');
  });

  test('disabled context suppresses everything', () async {
    enabled = false;
    build().start();
    apply('done');
    await settle();

    expect(emitted, isEmpty);
  });
}
