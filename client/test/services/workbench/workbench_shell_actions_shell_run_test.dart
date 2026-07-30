import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/terminal_split.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/terminal/workspace_terminal_run_service.dart';
import 'package:teampilot/services/workbench/workbench_shell_actions.dart';

TerminalSession _testSession() => TerminalSession(
  executable: '/bin/bash',
  validateLaunch: false,
  parseExecutable: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('workbenchSelectSyncsChatTab', () {
    test('only session kind syncs ChatCubit.selectTab', () {
      for (final kind in WorkbenchTabKind.values) {
        expect(
          workbenchSelectSyncsChatTab(kind),
          kind == WorkbenchTabKind.session,
          reason: '$kind',
        );
      }
    });
  });

  group('shouldRemoveRunWorkbenchTab', () {
    test('orphaned run tab (session gone) always removes strip tab', () {
      expect(
        shouldRemoveRunWorkbenchTab(
          sessionFound: false,
          dismissSucceeded: false,
        ),
        isTrue,
      );
    });

    test('found session removes strip tab only when dismiss succeeds', () {
      expect(
        shouldRemoveRunWorkbenchTab(
          sessionFound: true,
          dismissSucceeded: false,
        ),
        isFalse,
      );
      expect(
        shouldRemoveRunWorkbenchTab(
          sessionFound: true,
          dismissSucceeded: true,
        ),
        isTrue,
      );
    });
  });

  group('disposeWorkbenchShellDomain', () {
    test('notifies run service for every pane then removes the surface', () {
      final closed = <String>[];
      final runService = WorkspaceTerminalRunService(onEntryClosed: closed.add);
      final registry = WorkspaceTerminalRegistry();
      addTearDown(registry.disposeAll);

      final group = registry.groupFor('tab-scope');
      final entry = group.addEntry(
        cwd: '/tmp',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      final surfaceId = group.surfaceForPane(entry.id)!.id;

      disposeWorkbenchShellDomain(
        runService: runService,
        group: group,
        surfaceId: surfaceId,
      );

      expect(closed, [entry.id]);
      expect(group.entries, isEmpty);
      expect(group.surfaces, isEmpty);
      expect(group.activeId, isNull);
    });

    test('closes every pane in a multi-pane surface', () {
      final closed = <String>[];
      final runService = WorkspaceTerminalRunService(onEntryClosed: closed.add);
      final registry = WorkspaceTerminalRegistry();
      addTearDown(registry.disposeAll);

      final group = registry.groupFor('tab-scope');
      final first = group.addEntry(
        cwd: '/tmp',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      final surfaceId = group.surfaceForPane(first.id)!.id;
      final second = group.addPaneToSurface(
        surfaceId: surfaceId,
        axis: SplitAxis.horizontal,
        cwd: '/tmp',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
      );

      disposeWorkbenchShellDomain(
        runService: runService,
        group: group,
        surfaceId: surfaceId,
      );

      expect(closed, containsAll([first.id, second.id]));
      expect(group.entries, isEmpty);
      expect(group.surfaces, isEmpty);
    });
  });
}
