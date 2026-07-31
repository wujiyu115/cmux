import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/services/pairing/session_catalog.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

class _FakeSession extends Mock implements TerminalSession {}

SessionCatalogEntry _chat(String sessionId, String? memberId, TerminalSession s) {
  return SessionCatalogEntry(
    PairedSessionRef(
      catalogId: PairedSessionRef.chatId(sessionId, memberId),
      kind: PairedSessionKind.chat,
      title: 'chat $sessionId',
      subtitle: '',
      sessionId: sessionId,
      memberId: memberId,
    ),
    s,
  );
}

SessionCatalogEntry _ws(String paneId, TerminalSession s) {
  return SessionCatalogEntry(
    PairedSessionRef(
      catalogId: PairedSessionRef.workspaceId(paneId),
      kind: PairedSessionKind.workspace,
      title: 'pane $paneId',
      subtitle: '',
      sessionId: 'group1',
      paneId: paneId,
    ),
    s,
  );
}

void main() {
  group('PairedSessionRef id space', () {
    test('chatId is stable and disjoint from workspaceId', () {
      expect(PairedSessionRef.chatId('s1', null), 'chat:s1:main');
      expect(PairedSessionRef.chatId('s1', 'm2'), 'chat:s1:m2');
      expect(PairedSessionRef.workspaceId('p9'), 'ws:p9');
      expect(
        PairedSessionRef.chatId('s1', null),
        isNot(PairedSessionRef.workspaceId('s1')),
      );
    });
  });

  group('SessionCatalog', () {
    test('list flattens all registered sources', () {
      final chatSession = _FakeSession();
      final wsSession = _FakeSession();
      final catalog = SessionCatalog()
        ..addSource(() => [_chat('s1', null, chatSession)])
        ..addSource(() => [_ws('p1', wsSession)]);

      final ids = catalog.list().map((e) => e.ref.catalogId).toList();
      expect(ids, ['chat:s1:main', 'ws:p1']);
    });

    test('list reflects live source contents on each call', () {
      var entries = <SessionCatalogEntry>[];
      final catalog = SessionCatalog()..addSource(() => entries);
      expect(catalog.list(), isEmpty);
      entries = [_chat('s1', null, _FakeSession())];
      expect(catalog.list(), hasLength(1));
    });

    test('resolve maps a catalogId back to its live entry', () {
      final target = _FakeSession();
      final catalog = SessionCatalog()
        ..addSource(() => [_chat('s1', 'm1', target)])
        ..addSource(() => [_ws('p1', _FakeSession())]);

      final resolved = catalog.resolve('chat:s1:m1');
      expect(resolved, isNotNull);
      expect(identical(resolved!.session, target), isTrue);
      expect(catalog.resolve('does-not-exist'), isNull);
    });

    test('changes fires on notifyChanged', () async {
      final catalog = SessionCatalog();
      expectLater(catalog.changes, emits(null));
      catalog.notifyChanged();
    });
  });
}
