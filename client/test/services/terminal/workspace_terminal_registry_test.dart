import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/terminal_split.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';

TerminalSession _testSession() => TerminalSession(
  executable: '/bin/bash',
  validateLaunch: false,
  parseExecutable: false,
);

WorkspaceTerminalEntry _add(WorkspaceTerminalGroup g, {bool select = true}) {
  return g.addEntry(
    cwd: '/tmp',
    spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
    session: _testSession(),
    select: select,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkspaceTerminalRegistry', () {
    test('groupFor lazily creates and reuses a group per workspace', () {
      final reg = WorkspaceTerminalRegistry();
      final a1 = reg.groupFor('A');
      final a2 = reg.groupFor('A');
      final b1 = reg.groupFor('B');
      expect(identical(a1, a2), isTrue);
      expect(identical(a1, b1), isFalse);
      reg.disposeAll();
    });

    test('addEntry / entries stays scoped to its workspace group', () {
      final reg = WorkspaceTerminalRegistry();
      final a = reg.groupFor('A');
      final entry = a.addEntry(
        cwd: '/tmp/a',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      expect(a.entries.single, entry);
      expect(a.activeId, entry.id);
      expect(reg.groupFor('B').entries, isEmpty);
      reg.disposeAll();
    });

    test('disposeWorkspace disposes entries and drops the group', () {
      final reg = WorkspaceTerminalRegistry();
      final a = reg.groupFor('A');
      final entry = a.addEntry(
        cwd: '/tmp/a',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      reg.disposeWorkspace('A');
      expect(entry.session.isRunning, isFalse);
      expect(reg.groupFor('A').entries, isEmpty);
      reg.disposeAll();
    });

    test('removeEntry reselects the active id', () {
      final reg = WorkspaceTerminalRegistry();
      final a = reg.groupFor('A');
      final e1 = a.addEntry(
        cwd: '/tmp/a',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      final e2 = a.addEntry(
        cwd: '/tmp/a2',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      expect(a.activeId, e2.id);
      a.removeEntry(e2.id);
      expect(a.activeId, e1.id);
      expect(a.entries.single, e1);
      reg.disposeAll();
    });
  });

  group('WorkspaceTerminalGroup surfaces', () {
    test('addEntry creates one single-leaf surface per entry', () {
      final g = WorkspaceTerminalGroup();
      final e1 = _add(g);
      final e2 = _add(g);
      expect(g.surfaces.length, 2);
      expect(g.surfaces[0].paneIds, [e1.id]);
      expect(g.surfaces[1].paneIds, [e2.id]);
      // Each entry still lists once, in insertion order.
      expect(g.entries.map((e) => e.id), [e1.id, e2.id]);
      g.dispose();
    });

    test('activeId derives from the active surface focused pane', () {
      final g = WorkspaceTerminalGroup();
      expect(g.activeId, isNull);
      final e1 = _add(g);
      expect(g.activeId, e1.id);
      expect(g.activeSurfaceId, g.surfaces.single.id);
      final e2 = _add(g, select: false);
      // select:false keeps the first surface active.
      expect(g.activeId, e1.id);
      expect(g.entryById(e2.id), e2);
      g.dispose();
    });

    test('activeId setter switches surface cross-tab and is tolerant', () {
      final g = WorkspaceTerminalGroup();
      final e1 = _add(g);
      final e2 = _add(g);
      expect(g.activeId, e2.id);
      var notified = 0;
      g.addListener(() => notified++);
      g.activeId = e1.id;
      expect(g.activeSurfaceId, g.surfaceForPane(e1.id)!.id);
      expect(g.activeId, e1.id);
      expect(notified, 1);
      // Identical → no notify.
      g.activeId = e1.id;
      expect(notified, 1);
      // Null and unknown ids → no-op.
      g.activeId = null;
      g.activeId = 'nope';
      expect(notified, 1);
      expect(g.activeId, e1.id);
      g.dispose();
    });

    test('removeEntry tears down its surface and activates the neighbour', () {
      final g = WorkspaceTerminalGroup();
      final e1 = _add(g);
      final e2 = _add(g);
      expect(g.surfaces.length, 2);
      final closed = g.removeEntry(e2.id);
      expect(closed, isFalse);
      expect(g.surfaces.length, 1);
      expect(g.activeSurfaceId, g.surfaceForPane(e1.id)!.id);
      expect(g.activeId, e1.id);
      final last = g.removeEntry(e1.id);
      expect(last, isTrue);
      expect(g.surfaces, isEmpty);
      expect(g.activeSurfaceId, isNull);
      expect(g.activeId, isNull);
      g.dispose();
    });

    test('removeEntry on unknown id returns emptiness of pane list', () {
      final g = WorkspaceTerminalGroup();
      expect(g.removeEntry('nope'), isTrue);
      _add(g);
      expect(g.removeEntry('nope'), isFalse);
      g.dispose();
    });

    test('removeSurface disposes every pane and activates the neighbour', () {
      final g = WorkspaceTerminalGroup();
      final e1 = _add(g);
      final first = g.activeSurfaceId!;
      final e2 = g.addPaneToSurface(
        surfaceId: first,
        axis: SplitAxis.vertical,
        cwd: '/tmp',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
      );
      final e3 = _add(g); // second surface, now active
      expect(g.surfaces.length, 2);
      expect(g.activeSurfaceId, g.surfaceForPane(e3.id)!.id);

      // Close the non-active multi-pane surface: both its panes go, active stays.
      final empty = g.removeSurface(first);
      expect(empty, isFalse);
      expect(g.surfaces.length, 1);
      expect(g.entries.map((e) => e.id), [e3.id]);
      expect(g.entryById(e1.id), isNull);
      expect(g.entryById(e2.id), isNull);
      expect(e1.session.isRunning, isFalse);
      expect(e2.session.isRunning, isFalse);
      expect(g.activeSurfaceId, g.surfaceForPane(e3.id)!.id);

      // Closing the last surface empties the group.
      final last = g.removeSurface(g.activeSurfaceId!);
      expect(last, isTrue);
      expect(g.surfaces, isEmpty);
      expect(g.entries, isEmpty);
      expect(g.activeSurfaceId, isNull);
      g.dispose();
    });

    test('removeSurface migrates active when the active surface closes', () {
      final g = WorkspaceTerminalGroup();
      final e1 = _add(g);
      final e2 = _add(g); // active
      expect(g.activeSurfaceId, g.surfaceForPane(e2.id)!.id);
      final closed = g.removeSurface(g.surfaceForPane(e2.id)!.id);
      expect(closed, isFalse);
      expect(g.activeSurfaceId, g.surfaceForPane(e1.id)!.id);
      g.dispose();
    });

    test('removeSurface on unknown id returns emptiness of surface list', () {
      final g = WorkspaceTerminalGroup();
      expect(g.removeSurface('nope'), isTrue);
      _add(g);
      expect(g.removeSurface('nope'), isFalse);
      g.dispose();
    });

    test('addPaneToSurface builds a 2-leaf tree with the new pane focused', () {
      final g = WorkspaceTerminalGroup();
      final e1 = _add(g);
      final surfaceId = g.activeSurfaceId!;
      final e2 = g.addPaneToSurface(
        surfaceId: surfaceId,
        axis: SplitAxis.vertical,
        cwd: '/tmp',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
      );
      // Still one surface, now two leaves.
      expect(g.surfaces.single.id, surfaceId);
      expect(g.surfaces.single.paneIds, [e1.id, e2.id]);
      expect(g.surfaces.single.focusedPaneId, e2.id);
      expect(g.activeId, e2.id);
      // Both panes remain listed in entries.
      expect(g.entries.map((e) => e.id), [e1.id, e2.id]);
      // canCloseActivePane is true with two panes.
      expect(g.canCloseActivePane, isTrue);
      g.dispose();
    });

    test('addPaneToSurface throws on unknown surfaceId', () {
      final g = WorkspaceTerminalGroup();
      _add(g);
      expect(
        () => g.addPaneToSurface(
          surfaceId: 'nope',
          axis: SplitAxis.vertical,
          cwd: '/tmp',
          spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
          session: _testSession(),
        ),
        throwsStateError,
      );
      g.dispose();
    });

    test('focusNextPane / focusPrevPane wrap inside a multi-pane surface', () {
      final g = WorkspaceTerminalGroup();
      final e1 = _add(g);
      final e2 = g.addPaneToSurface(
        surfaceId: g.activeSurfaceId!,
        axis: SplitAxis.vertical,
        cwd: '/tmp',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
      );
      expect(g.activeId, e2.id);
      g.focusNextPane();
      expect(g.activeId, e1.id); // wrapped
      g.focusNextPane();
      expect(g.activeId, e2.id);
      g.focusPrevPane();
      expect(g.activeId, e1.id);
      g.dispose();
    });

    test('toggleZoom flips the active surface zoomed pane', () {
      final g = WorkspaceTerminalGroup();
      final e1 = _add(g);
      expect(g.activeSurface!.zoomedPaneId, isNull);
      g.toggleZoom();
      expect(g.activeSurface!.zoomedPaneId, e1.id);
      g.toggleZoom();
      expect(g.activeSurface!.zoomedPaneId, isNull);
      g.dispose();
    });

    test('renamePane / renameSurface write into the owning surface', () {
      final g = WorkspaceTerminalGroup();
      final e1 = _add(g);
      g.renamePane(e1.id, 'build');
      expect(g.activeSurface!.displayNameFor(e1.id), 'build');
      g.renamePane(e1.id, '');
      expect(g.activeSurface!.displayNameFor(e1.id), '');
      g.renameSurface(g.activeSurfaceId!, 'Shells');
      expect(g.activeSurface!.name, 'Shells');
      g.dispose();
    });

    test('canCloseActivePane is false with a single pane', () {
      final g = WorkspaceTerminalGroup();
      _add(g);
      expect(g.canCloseActivePane, isFalse);
      g.dispose();
    });

    test('updateSurface replaces by id and notifies', () {
      final g = WorkspaceTerminalGroup();
      _add(g);
      var notified = 0;
      g.addListener(() => notified++);
      final s = g.activeSurface!;
      g.updateSurface(s.copyWith(name: 'X'));
      expect(g.activeSurface!.name, 'X');
      expect(notified, 1);
      g.dispose();
    });
  });
}
