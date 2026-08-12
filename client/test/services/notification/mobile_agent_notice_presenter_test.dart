import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/notification/mobile_agent_notice_presenter.dart';
import 'package:teampilot/services/pairing/agent_notice_message.dart';

class _Shown {
  _Shown(this.title, this.body, this.subtitle, this.payload);
  final String title;
  final String body;
  final String? subtitle;
  final String? payload;
}

const _strings = MobileAgentNoticeStrings(
  titles: {
    PairingAgentNoticeKind.done: 'Agent finished',
    PairingAgentNoticeKind.interrupted: 'Agent interrupted',
    PairingAgentNoticeKind.waiting: 'Agent needs approval',
  },
  bodies: {
    PairingAgentNoticeKind.done: 'The agent completed its turn.',
    PairingAgentNoticeKind.interrupted: "The agent's turn was cancelled.",
    PairingAgentNoticeKind.waiting: 'The agent is waiting for authorization.',
  },
);

void main() {
  late List<_Shown> shown;

  MobileAgentNoticePresenter build({
    MobileAgentNoticeStrings? strings = _strings,
  }) {
    shown = [];
    return MobileAgentNoticePresenter(
      show: ({required title, required body, subtitle, payload}) async {
        shown.add(_Shown(title, body, subtitle, payload));
      },
      resolveStrings: () => strings,
    );
  }

  test('show composes title, body and mirror payload', () {
    build().show(
      const PairingAgentNotice(
        kind: PairingAgentNoticeKind.done,
        seatId: 'ws:pane-1',
        catalogId: 'ws:pane-1',
        workspaceLabel: 'teampilot',
        title: 'zsh · client',
      ),
    );

    expect(shown, hasLength(1));
    expect(shown.single.title, 'zsh · client');
    expect(shown.single.body, 'teampilot · The agent completed its turn.');
    expect(shown.single.subtitle, 'Agent finished');
    expect(shown.single.payload, 'pairing-mirror:ws:pane-1');
  });

  test('show falls back to the localized kind title without attribution', () {
    build().show(
      const PairingAgentNotice(
        kind: PairingAgentNoticeKind.waiting,
        seatId: 'ws:pane-2',
        catalogId: 'ws:pane-2',
      ),
    );

    expect(shown.single.title, 'Agent needs approval');
    expect(shown.single.body, 'The agent is waiting for authorization.');
  });

  test('show omits the payload for a seat the host cannot mirror', () {
    // Chat session tabs are never in the pairing catalog, so the tap can only
    // foreground the app.
    build().show(
      const PairingAgentNotice(
        kind: PairingAgentNoticeKind.interrupted,
        seatId: 'sess-1',
        workspaceLabel: 'teampilot',
        title: 'Fix the parser',
      ),
    );

    expect(shown.single.payload, isNull);
    expect(shown.single.title, 'Fix the parser');
    expect(shown.single.subtitle, 'Agent interrupted');
  });

  test('show is a no-op without a live app context', () {
    build(strings: null).show(
      const PairingAgentNotice(
        kind: PairingAgentNoticeKind.done,
        seatId: 'ws:pane-3',
      ),
    );

    expect(shown, isEmpty);
  });
}
