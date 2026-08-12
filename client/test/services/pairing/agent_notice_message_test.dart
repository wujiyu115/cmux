import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/agent_notice_message.dart';

void main() {
  test('PairingAgentNotice round-trips through json', () {
    const notice = PairingAgentNotice(
      kind: PairingAgentNoticeKind.waiting,
      seatId: 'ws:pane-1',
      catalogId: 'ws:pane-1',
      workspaceId: 'ws-1',
      workspaceLabel: 'teampilot',
      title: 'zsh · client',
      atMs: 1700000000000,
    );

    final decoded = PairingAgentNotice.tryFromJson(notice.toJson());

    expect(decoded, isNotNull);
    expect(decoded!.kind, PairingAgentNoticeKind.waiting);
    expect(decoded.seatId, 'ws:pane-1');
    expect(decoded.catalogId, 'ws:pane-1');
    expect(decoded.workspaceId, 'ws-1');
    expect(decoded.workspaceLabel, 'teampilot');
    expect(decoded.title, 'zsh · client');
    expect(decoded.atMs, 1700000000000);
    expect(decoded.isMirrorable, isTrue);
  });

  test('PairingAgentNotice omits a null catalogId and stays non-mirrorable', () {
    const notice = PairingAgentNotice(
      kind: PairingAgentNoticeKind.done,
      seatId: 'sess-1',
    );

    final json = notice.toJson();
    expect(json.containsKey('catalogId'), isFalse);

    final decoded = PairingAgentNotice.tryFromJson(json)!;
    expect(decoded.catalogId, isNull);
    expect(decoded.isMirrorable, isFalse);
  });

  test('PairingAgentNotice.tryFromJson rejects unknown or missing kind', () {
    // A newer desktop adding a kind must not crash an older phone.
    expect(
      PairingAgentNotice.tryFromJson({'kind': 'exploded', 'seatId': 'a'}),
      isNull,
    );
    expect(PairingAgentNotice.tryFromJson({'seatId': 'a'}), isNull);
    expect(PairingAgentNotice.tryFromJson({'kind': 42, 'seatId': 'a'}), isNull);
  });

  test('PairingAgentNotice.tryFromJson rejects a missing seatId', () {
    expect(PairingAgentNotice.tryFromJson({'kind': 'done'}), isNull);
    expect(
      PairingAgentNotice.tryFromJson({'kind': 'done', 'seatId': '   '}),
      isNull,
    );
  });

  test('PairingAgentNotice.tryFromJson defaults absent optional fields', () {
    final decoded = PairingAgentNotice.tryFromJson({
      'kind': 'interrupted',
      'seatId': 'ws:pane-2',
      'workspaceLabel': 7, // wrong type — treated as absent
    })!;

    expect(decoded.kind, PairingAgentNoticeKind.interrupted);
    expect(decoded.workspaceId, '');
    expect(decoded.workspaceLabel, '');
    expect(decoded.title, '');
    expect(decoded.atMs, 0);
    expect(decoded.catalogId, isNull);
  });

  test('PairingAgentNotice.tryFromJson coerces a double atMs', () {
    final decoded = PairingAgentNotice.tryFromJson({
      'kind': 'done',
      'seatId': 'ws:pane-3',
      'atMs': 1700000000000.0,
    })!;

    expect(decoded.atMs, 1700000000000);
  });

  test('withCatalogId keeps every other field', () {
    const notice = PairingAgentNotice(
      kind: PairingAgentNoticeKind.done,
      seatId: 'ws:pane-4',
      workspaceId: 'ws-9',
      workspaceLabel: 'label',
      title: 'title',
      atMs: 5,
    );

    final stamped = notice.withCatalogId('ws:pane-4');

    expect(stamped.catalogId, 'ws:pane-4');
    expect(stamped.kind, notice.kind);
    expect(stamped.seatId, notice.seatId);
    expect(stamped.workspaceId, notice.workspaceId);
    expect(stamped.workspaceLabel, notice.workspaceLabel);
    expect(stamped.title, notice.title);
    expect(stamped.atMs, notice.atMs);
    expect(stamped.withCatalogId(null).catalogId, isNull);
  });
}
