import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/terminal_split.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/terminal/workspace_terminal_title_resolver.dart';

TerminalSession _testSession() => TerminalSession(
  executable: '/bin/bash',
  validateLaunch: false,
  parseExecutable: false,
);

WorkspaceTerminalEntry _entry(String id, String title) {
  final entry = WorkspaceTerminalEntry(
    id: id,
    cwd: '/tmp',
    spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
    session: _testSession(),
  )..titleLabel = title;
  return entry;
}

void main() {
  group('WorkspaceTerminalTitleResolver', () {
    test('returns base label when unique', () {
      final a = _entry('a', 'Local');
      expect(
        WorkspaceTerminalTitleResolver.tabTitle(
          entry: a,
          siblings: [a],
          baseLabel: 'Local',
        ),
        'Local',
      );
    });

    test('appends index when siblings share base label', () {
      final a = _entry('a', 'Local');
      final b = _entry('b', 'Local');
      final c = _entry('c', 'user@host');
      final siblings = [a, b, c];
      expect(
        WorkspaceTerminalTitleResolver.tabTitle(
          entry: a,
          siblings: siblings,
          baseLabel: 'Local',
        ),
        'Local (1)',
      );
      expect(
        WorkspaceTerminalTitleResolver.tabTitle(
          entry: b,
          siblings: siblings,
          baseLabel: 'Local',
        ),
        'Local (2)',
      );
      expect(
        WorkspaceTerminalTitleResolver.tabTitle(
          entry: c,
          siblings: siblings,
          baseLabel: 'user@host',
        ),
        'user@host',
      );
    });
  });

  group('WorkspaceTerminalTitleResolver.surfaceTabTitle', () {
    WorkspaceTerminalEntry addLabeled(WorkspaceTerminalGroup g, String label) =>
        g.addEntry(
          cwd: '/tmp',
          spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
          session: _testSession(),
          select: true,
          titleLabel: label,
        );

    test('base label comes from the surface name when set', () {
      final g = WorkspaceTerminalGroup();
      final e = addLabeled(g, 'Local');
      final surfaceId = g.surfaceForPane(e.id)!.id;
      g.renameSurface(surfaceId, 'Build');
      expect(
        WorkspaceTerminalTitleResolver.surfaceTabTitle(
          surface: g.surfaces.single,
          siblings: g.surfaces,
          entryFor: g.entryById,
        ),
        'Build',
      );
      g.dispose();
    });

    test('falls back to the focused pane label, numbering across surfaces', () {
      final g = WorkspaceTerminalGroup();
      addLabeled(g, 'Local');
      addLabeled(g, 'Local');
      addLabeled(g, 'user@host');
      final surfaces = g.surfaces;
      expect(
        WorkspaceTerminalTitleResolver.surfaceTabTitle(
          surface: surfaces[0],
          siblings: surfaces,
          entryFor: g.entryById,
        ),
        'Local (1)',
      );
      expect(
        WorkspaceTerminalTitleResolver.surfaceTabTitle(
          surface: surfaces[1],
          siblings: surfaces,
          entryFor: g.entryById,
        ),
        'Local (2)',
      );
      expect(
        WorkspaceTerminalTitleResolver.surfaceTabTitle(
          surface: surfaces[2],
          siblings: surfaces,
          entryFor: g.entryById,
        ),
        'user@host',
      );
      g.dispose();
    });

    test('splitting a surface does not change its numbering', () {
      final g = WorkspaceTerminalGroup();
      final e1 = addLabeled(g, 'Local');
      // Split the single surface into two panes: still one surface, one title.
      g.addPaneToSurface(
        surfaceId: g.surfaceForPane(e1.id)!.id,
        axis: SplitAxis.vertical,
        cwd: '/tmp',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        titleLabel: 'Local',
      );
      expect(g.surfaces.length, 1);
      expect(
        WorkspaceTerminalTitleResolver.surfaceTabTitle(
          surface: g.surfaces.single,
          siblings: g.surfaces,
          entryFor: g.entryById,
        ),
        // No "(N)" — a single surface is unique regardless of pane count.
        'Local',
      );
      g.dispose();
    });
  });
}
