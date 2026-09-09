import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/main.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/quick_open/quick_open_overlay.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/quick_open_command_registrar.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

import '../../support/desktop_app_harness.dart';
import '../../support/fake_terminal_session.dart';
import '../../support/post_frame_test_harness.dart';

/// Ctrl+P must follow the *active* workspace tab. Kept-alive tabs bind their
/// opener to the shared [QuickOpenHost] on activation and unbind on
/// deactivation (see `WorkspaceSplitPane._syncQuickOpenHost`); this guards
/// against a stale binding serving the previously active workspace's index
/// roots after a tab switch.
void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(setUpDesktopAppHarness);
  tearDownAll(tearDownDesktopAppHarness);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setUpTestAppStorage();
    resetAppRouterLocationForWidgetTests();
  });

  tearDown(() {
    tearDownTestAppStorage();
    resetAppRouterLocationForWidgetTests();
  });

  testWidgets('quick open indexes the active workspace after tab switches', (
    tester,
  ) async {
    final postFrame = PostFrameTestHarness();
    final chatCubit = ChatCubit(
      executableResolver: desktopHarnessExecutable,
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              FakeTerminalSession(
                executable: executable,
                scrollbackLines: scrollbackLines,
              ),
      postFrameScheduler: postFrame.scheduler,
      sessionRepository: desktopHarnessSessionRepo,
    );
    final layoutCubit = LayoutCubit();
    addTearDown(layoutCubit.close);

    late Workspace workspaceA;
    late Workspace workspaceB;
    late Directory dirA;
    late Directory dirB;
    await tester.runAsync(() async {
      dirA = await Directory.systemTemp.createTemp('qo_binding_a_');
      dirB = await Directory.systemTemp.createTemp('qo_binding_b_');
      workspaceA = await desktopHarnessSessionRepo.createWorkspace([
        WorkspaceFolder(path: dirA.path),
      ]);
      workspaceB = await desktopHarnessSessionRepo.createWorkspace([
        WorkspaceFolder(path: dirB.path),
      ]);
      chatCubit.ingestWorkspaceSessionSnapshot(
        workspaces: [workspaceA, workspaceB],
        sessions: const [],
      );
    });
    addTearDown(() {
      for (final dir in [dirA, dirB]) {
        try {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        } on Object catch (_) {}
      }
    });

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sessionCubit =
        (await tester.runAsync(testSessionPreferencesCubit))!;
    await tester.pumpWidget(
      RepositoryProvider<WorkbenchEditorOpener>(
        create: (_) => WorkbenchEditorOpener(
          editor: EditorCubit(fs: LocalFilesystem()),
          workbench: WorkbenchCubit(),
          markdownViewModes: MarkdownViewModeStore(),
          readMarkdownOpenMode: () => MarkdownOpenMode.preview,
        ),
        child: buildTestApp(
          sessionPreferencesCubit: sessionCubit,
          chatCubit: chatCubit,
          layoutCubit: layoutCubit,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Mirror the bootstrap wiring (`buildAppShell`) that Ctrl+P rides on.
    final shellContext = tester.element(find.byType(TeamPilotApp));
    final bus = shellContext.read<CommandBus>();
    registerQuickOpenCommands(bus, shellContext.read<QuickOpenHost>());

    Future<void> openQuickOpenOn(String route) async {
      appRouter.go(route);
      await tester.pump();
      await pumpPhaseTransitions(tester);
      bus.invoke(CommandIds.quickOpen);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(QuickOpenOverlay), findsOneWidget);
    }

    Future<void> closeQuickOpen() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(QuickOpenOverlay), findsNothing);
    }

    QuickOpenOverlay currentOverlay() =>
        tester.widget<QuickOpenOverlay>(find.byType(QuickOpenOverlay));

    await openQuickOpenOn('/home-v2/workspace/${workspaceA.workspaceId}');
    var overlay = currentOverlay();
    expect(overlay.workspace.workspaceId, workspaceA.workspaceId);
    expect(overlay.indexRoots, contains(dirA.path));
    expect(overlay.indexRoots!.any((root) => root == dirB.path), isFalse);
    await closeQuickOpen();

    // Tab A stays keep-alive mounted while B becomes active; the dialog must
    // be re-bound to B, not keep serving A's roots.
    await openQuickOpenOn('/home-v2/workspace/${workspaceB.workspaceId}');
    overlay = currentOverlay();
    expect(overlay.workspace.workspaceId, workspaceB.workspaceId);
    expect(overlay.indexRoots, contains(dirB.path));
    expect(overlay.indexRoots!.any((root) => root == dirA.path), isFalse);
    await closeQuickOpen();

    // Switching back must rebind to A again (no lopsided unbind).
    await openQuickOpenOn('/home-v2/workspace/${workspaceA.workspaceId}');
    overlay = currentOverlay();
    expect(overlay.workspace.workspaceId, workspaceA.workspaceId);
    expect(overlay.indexRoots, contains(dirA.path));
    expect(overlay.indexRoots!.any((root) => root == dirB.path), isFalse);

    // Flush debounced persistence timers before the tree is disposed.
    await tester.pump(const Duration(seconds: 5));
  });
}
