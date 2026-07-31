import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/services/pairing/session_catalog.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

class _FakeSession extends Mock implements TerminalSession {}

SessionCatalogEntry _pane(
  String paneId,
  TerminalSession s, {
  String workspaceId = 'group1',
}) {
  return SessionCatalogEntry(
    PairedSessionRef(
      catalogId: PairedSessionRef.paneCatalogId(paneId),
      title: 'pane $paneId',
      subtitle: '',
      workspaceId: workspaceId,
      paneId: paneId,
    ),
    s,
  );
}

void main() {
  group('PairedSessionRef id space', () {
    test('paneCatalogId is stable and namespaced', () {
      expect(PairedSessionRef.paneCatalogId('p9'), 'ws:p9');
      expect(
        PairedSessionRef.paneCatalogId('p9'),
        PairedSessionRef.paneCatalogId('p9'),
      );
    });
  });

  group('SessionCatalog', () {
    test('list flattens all registered sources', () {
      final catalog = SessionCatalog()
        ..addSource(() => [_pane('p1', _FakeSession())])
        ..addSource(() => [_pane('p2', _FakeSession())]);

      final ids = catalog.list().map((e) => e.ref.catalogId).toList();
      expect(ids, ['ws:p1', 'ws:p2']);
    });

    test('list reflects live source contents on each call', () {
      var entries = <SessionCatalogEntry>[];
      final catalog = SessionCatalog()..addSource(() => entries);
      expect(catalog.list(), isEmpty);
      entries = [_pane('p1', _FakeSession())];
      expect(catalog.list(), hasLength(1));
    });

    test('resolve maps a catalogId back to its live entry', () {
      final target = _FakeSession();
      final catalog = SessionCatalog()
        ..addSource(() => [_pane('p1', target)])
        ..addSource(() => [_pane('p2', _FakeSession())]);

      final resolved = catalog.resolve('ws:p1');
      expect(resolved, isNotNull);
      expect(identical(resolved!.session, target), isTrue);
      expect(catalog.resolve('does-not-exist'), isNull);
    });

    test('entries carry the workspace that owns the pane', () {
      final catalog = SessionCatalog()
        ..addSource(() => [_pane('p1', _FakeSession(), workspaceId: 'wsA')]);
      expect(catalog.list().single.ref.workspaceId, 'wsA');
    });

    test('changes fires on notifyChanged', () async {
      final catalog = SessionCatalog();
      expectLater(catalog.changes, emits(null));
      catalog.notifyChanged();
    });
  });
}
