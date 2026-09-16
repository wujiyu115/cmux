import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/chat/model/session_open_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/main.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/terminal/workspace_shell_connector.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/notification/session_idle_notification_tap.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';
import 'package:teampilot/services/workbench/workbench_shell_launcher.dart';

import '../../support/desktop_app_harness.dart';
import '../../support/fake_terminal_session.dart';
import '../../support/post_frame_test_harness.dart';

/// Notification taps deep-link to `/home-v2/workspace/:id?session=:sessionId`
/// (AgentAttentionNotificationService) or `?pane=:paneId` (terminal idle).
/// The tap must land on the tab that raised the notification — not the
/// workspace's first/last-active tab.
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

  testWidgets(
    'session deep link from another workspace selects the originating tab',
    (tester) async {
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

      late Workspace workspaceW;
      late Workspace workspaceX;
      late Directory dirW;
      late Directory dirX;
      const s1 = 'noti-s1';
      const s2 = 'noti-s2';
      const s3 = 'noti-s3';
      await tester.runAsync(() async {
        dirW = await Directory.systemTemp.createTemp('noti_deeplink_w_');
        dirX = await Directory.systemTemp.createTemp('noti_deeplink_x_');
        workspaceW = await desktopHarnessSessionRepo.createWorkspace([
          WorkspaceFolder(path: dirW.path),
        ]);
        workspaceX = await desktopHarnessSessionRepo.createWorkspace([
          WorkspaceFolder(path: dirX.path),
        ]);
        await desktopHarnessSessionRepo.createSession(
          workspaceW.workspaceId,
          fixedSessionId: s1,
        );
        await desktopHarnessSessionRepo.createSession(
          workspaceW.workspaceId,
          fixedSessionId: s2,
        );
        await desktopHarnessSessionRepo.createSession(
          workspaceW.workspaceId,
          fixedSessionId: s3,
        );
        await desktopHarnessSessionRepo.createSession(
          workspaceX.workspaceId,
          fixedSessionId: 'noti-x1',
        );
        await chatCubit.loadWorkspaceData(desktopHarnessSessionRepo);
      });
      addTearDown(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
        await chatCubit.close();
        for (final dir in [dirW, dirX]) {
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
            readEditorPreviewTabs: () => true,
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

      WorkbenchCubit workbenchOf() =>
          tester.element(find.byType(TeamPilotApp)).read<WorkbenchCubit>();

      // Open W and open its three session tabs (s1 ends up active).
      appRouter.go('/home-v2/workspace/${workspaceW.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await tester.runAsync(() async {
        for (final sessionId in [s1, s2, s3]) {
          final session = chatCubit.state.sessions
              .where((s) => s.sessionId == sessionId)
              .first;
          await chatCubit.requestOpenSession(
            SessionOpenRequest(
              session: session,
              workspace: workspaceW,
              repo: desktopHarnessSessionRepo,
              connectImmediately: false,
            ),
          );
          await postFrame.flush();
        }
        // Leave s1 as the visible/active tab (the "first tab" baseline).
        final s1Session = chatCubit.state.sessions
            .where((s) => s.sessionId == s1)
            .first;
        await chatCubit.requestOpenSession(
          SessionOpenRequest(
            session: s1Session,
            workspace: workspaceW,
            repo: desktopHarnessSessionRepo,
            connectImmediately: false,
          ),
        );
        await postFrame.flush();
        await drainPendingAsyncWork();
      });
      await pumpPhaseTransitions(tester);
      expect(
        workbenchOf().state.bucket(workspaceW.workspaceId).activeTabId,
        WorkbenchTabId.session(s1),
        reason: 'baseline: s1 is the active tab before the notification',
      );

      // User switches to workspace X, then taps a notification from W:s3.
      appRouter.go('/home-v2/workspace/${workspaceX.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);

      appRouter.go(
        '/home-v2/workspace/${workspaceW.workspaceId}?session=$s3',
      );
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await tester.runAsync(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
      });
      await pumpPhaseTransitions(tester);

      expect(
        chatCubit.state.activeSessionId,
        s3,
        reason: 'deep link must make s3 the active chat session',
      );
      expect(
        workbenchOf().state.bucket(workspaceW.workspaceId).activeTabId,
        WorkbenchTabId.session(s3),
        reason: 'deep link must activate s3 in the workbench strip',
      );
      expect(
        appRouter.routerDelegate.currentConfiguration.uri.toString(),
        '/home-v2/workspace/${workspaceW.workspaceId}',
        reason: 'query is stripped after the deep link is consumed',
      );

      // Flush debounced persistence timers before the tree is disposed.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'pane deep link from another workspace selects the originating shell tab',
    (tester) async {
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

      late Workspace workspaceW;
      late Workspace workspaceX;
      late Directory dirW;
      late Directory dirX;
      const s1 = 'noti-s1';
      await tester.runAsync(() async {
        dirW = await Directory.systemTemp.createTemp('noti_pane_w_');
        dirX = await Directory.systemTemp.createTemp('noti_pane_x_');
        workspaceW = await desktopHarnessSessionRepo.createWorkspace([
          WorkspaceFolder(path: dirW.path),
        ]);
        workspaceX = await desktopHarnessSessionRepo.createWorkspace([
          WorkspaceFolder(path: dirX.path),
        ]);
        await desktopHarnessSessionRepo.createSession(
          workspaceW.workspaceId,
          fixedSessionId: s1,
        );
        await desktopHarnessSessionRepo.createSession(
          workspaceX.workspaceId,
          fixedSessionId: 'noti-x1',
        );
        await chatCubit.loadWorkspaceData(desktopHarnessSessionRepo);
      });
      addTearDown(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
        await chatCubit.close();
        for (final dir in [dirW, dirX]) {
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
            readEditorPreviewTabs: () => true,
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

      WorkbenchCubit workbenchOf() =>
          tester.element(find.byType(TeamPilotApp)).read<WorkbenchCubit>();
      WorkspaceTerminalRegistry registryOf() =>
          tester.element(find.byType(TeamPilotApp))
                  .read<WorkspaceTerminalRegistry>();

      // Open W, open its first session tab, and give the workspace a live
      // shell terminal pane (the seat a pane notification comes from).
      appRouter.go('/home-v2/workspace/${workspaceW.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await tester.runAsync(() async {
        final session = chatCubit.state.sessions
            .where((s) => s.sessionId == s1)
            .first;
        await chatCubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            workspace: workspaceW,
            repo: desktopHarnessSessionRepo,
            connectImmediately: false,
          ),
        );
        await postFrame.flush();
        await drainPendingAsyncWork();
      });
      await pumpPhaseTransitions(tester);

      final group = registryOf().groupFor(workspaceW.workspaceId);
      late final String paneId;
      await tester.runAsync(() async {
        final entry = group.addEntry(
          cwd: dirW.path,
          spec: const WorkspaceTerminalLocalSpec('bash'),
          session: FakeTerminalSession(executable: 'bash'),
          select: true,
          titleLabel: 'agent shell',
        );
        paneId = entry.id;
      });
      await pumpPhaseTransitions(tester);
      final surfaceId = group.surfaceForPane(paneId)!.id;
      expect(
        workbenchOf().state.bucket(workspaceW.workspaceId).activeTabId,
        WorkbenchTabId.session(s1),
        reason: 'baseline: the session tab is active, not the shell tab',
      );

      // User switches to workspace X, then taps a pane notification from W.
      appRouter.go('/home-v2/workspace/${workspaceX.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);

      appRouter.go(
        '/home-v2/workspace/${workspaceW.workspaceId}?pane=$paneId',
      );
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await tester.runAsync(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
      });
      await pumpPhaseTransitions(tester);

      expect(
        group.activeId,
        paneId,
        reason: 'deep link must focus the originating pane',
      );
      expect(
        workbenchOf().state.bucket(workspaceW.workspaceId).activeTabId,
        WorkbenchTabId.shell(surfaceId),
        reason: 'deep link must activate the pane\'s shell tab',
      );
      expect(
        appRouter.routerDelegate.currentConfiguration.uri.toString(),
        '/home-v2/workspace/${workspaceW.workspaceId}',
        reason: 'query is stripped after the deep link is consumed',
      );

      // Flush debounced persistence timers before the tree is disposed.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'session deep link while already on the workspace switches to the tab',
    (tester) async {
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

      late Workspace workspaceW;
      late Directory dirW;
      const s1 = 'noti-s1';
      const s2 = 'noti-s2';
      await tester.runAsync(() async {
        dirW = await Directory.systemTemp.createTemp('noti_same_w_');
        workspaceW = await desktopHarnessSessionRepo.createWorkspace([
          WorkspaceFolder(path: dirW.path),
        ]);
        await desktopHarnessSessionRepo.createSession(
          workspaceW.workspaceId,
          fixedSessionId: s1,
        );
        await desktopHarnessSessionRepo.createSession(
          workspaceW.workspaceId,
          fixedSessionId: s2,
        );
        await chatCubit.loadWorkspaceData(desktopHarnessSessionRepo);
      });
      addTearDown(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
        await chatCubit.close();
        try {
          if (dirW.existsSync()) dirW.deleteSync(recursive: true);
        } on Object catch (_) {}
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
            readEditorPreviewTabs: () => true,
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

      WorkbenchCubit workbenchOf() =>
          tester.element(find.byType(TeamPilotApp)).read<WorkbenchCubit>();

      // Open W with both session tabs, s1 active.
      appRouter.go('/home-v2/workspace/${workspaceW.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await tester.runAsync(() async {
        for (final sessionId in [s1, s2]) {
          final session = chatCubit.state.sessions
              .where((s) => s.sessionId == sessionId)
              .first;
          await chatCubit.requestOpenSession(
            SessionOpenRequest(
              session: session,
              workspace: workspaceW,
              repo: desktopHarnessSessionRepo,
              connectImmediately: false,
            ),
          );
          await postFrame.flush();
        }
        final s1Session = chatCubit.state.sessions
            .where((s) => s.sessionId == s1)
            .first;
        await chatCubit.requestOpenSession(
          SessionOpenRequest(
            session: s1Session,
            workspace: workspaceW,
            repo: desktopHarnessSessionRepo,
            connectImmediately: false,
          ),
        );
        await postFrame.flush();
        await drainPendingAsyncWork();
      });
      await pumpPhaseTransitions(tester);
      expect(
        workbenchOf().state.bucket(workspaceW.workspaceId).activeTabId,
        WorkbenchTabId.session(s1),
      );

      // Notification arrives from s2 while the user is already on W (query-only
      // navigation: path unchanged, route stays active).
      appRouter.go(
        '/home-v2/workspace/${workspaceW.workspaceId}?session=$s2',
      );
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await tester.runAsync(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
      });
      await pumpPhaseTransitions(tester);

      expect(
        chatCubit.state.activeSessionId,
        s2,
        reason: 'query-only deep link must switch the active session',
      );
      expect(
        workbenchOf().state.bucket(workspaceW.workspaceId).activeTabId,
        WorkbenchTabId.session(s2),
        reason: 'query-only deep link must switch the workbench tab',
      );

      // Flush debounced persistence timers before the tree is disposed.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'session deep link from home opens the target session tab',
    (tester) async {
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

      late Workspace workspaceW;
      late Directory dirW;
      const s1 = 'noti-s1';
      const s3 = 'noti-s3';
      await tester.runAsync(() async {
        dirW = await Directory.systemTemp.createTemp('noti_home_w_');
        workspaceW = await desktopHarnessSessionRepo.createWorkspace([
          WorkspaceFolder(path: dirW.path),
        ]);
        await desktopHarnessSessionRepo.createSession(
          workspaceW.workspaceId,
          fixedSessionId: s1,
        );
        await desktopHarnessSessionRepo.createSession(
          workspaceW.workspaceId,
          fixedSessionId: s3,
        );
        await chatCubit.loadWorkspaceData(desktopHarnessSessionRepo);
      });
      addTearDown(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
        await chatCubit.close();
        try {
          if (dirW.existsSync()) dirW.deleteSync(recursive: true);
        } on Object catch (_) {}
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
            readEditorPreviewTabs: () => true,
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

      WorkbenchCubit workbenchOf() =>
          tester.element(find.byType(TeamPilotApp)).read<WorkbenchCubit>();

      // Open W once so the tab stays kept-alive, open only s1, then go home.
      appRouter.go('/home-v2/workspace/${workspaceW.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await tester.runAsync(() async {
        final session = chatCubit.state.sessions
            .where((s) => s.sessionId == s1)
            .first;
        await chatCubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            workspace: workspaceW,
            repo: desktopHarnessSessionRepo,
            connectImmediately: false,
          ),
        );
        await postFrame.flush();
        await drainPendingAsyncWork();
      });
      await pumpPhaseTransitions(tester);

      appRouter.go('/home-v2');
      await tester.pump();
      await pumpPhaseTransitions(tester);

      // Notification from s3 (whose tab is NOT open) while at home.
      appRouter.go(
        '/home-v2/workspace/${workspaceW.workspaceId}?session=$s3',
      );
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await tester.runAsync(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
      });
      await pumpPhaseTransitions(tester);

      expect(
        chatCubit.state.activeSessionId,
        s3,
        reason: 'deep link from home must open and select s3',
      );
      expect(
        workbenchOf().state.bucket(workspaceW.workspaceId).activeTabId,
        WorkbenchTabId.session(s3),
        reason: 'deep link from home must activate s3 in the workbench strip',
      );

      // Flush debounced persistence timers before the tree is disposed.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  // The user's live scenario: several agent shells in ONE workspace, user
  // already on it, clicking the same pane's OS toast repeatedly. The tap goes
  // through the real tap handler (handleSessionIdleNotificationTap).
  testWidgets(
    'pane deep link while on the workspace focuses the pane, repeatedly',
    (tester) async {
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

      late Workspace workspaceW;
      late Directory dirW;
      const s1 = 'noti-s1';
      await tester.runAsync(() async {
        dirW = await Directory.systemTemp.createTemp('noti_live_w_');
        workspaceW = await desktopHarnessSessionRepo.createWorkspace([
          WorkspaceFolder(path: dirW.path),
        ]);
        await desktopHarnessSessionRepo.createSession(
          workspaceW.workspaceId,
          fixedSessionId: s1,
        );
        await chatCubit.loadWorkspaceData(desktopHarnessSessionRepo);
      });
      addTearDown(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
        await chatCubit.close();
        try {
          if (dirW.existsSync()) dirW.deleteSync(recursive: true);
        } on Object catch (_) {}
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
            readEditorPreviewTabs: () => true,
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

      WorkbenchCubit workbenchOf() =>
          tester.element(find.byType(TeamPilotApp)).read<WorkbenchCubit>();
      WorkspaceTerminalRegistry registryOf() =>
          tester.element(find.byType(TeamPilotApp))
                  .read<WorkspaceTerminalRegistry>();

      // Open W with its session tab, then three shell panes; pane 1 focused.
      appRouter.go('/home-v2/workspace/${workspaceW.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await tester.runAsync(() async {
        final session = chatCubit.state.sessions
            .where((s) => s.sessionId == s1)
            .first;
        await chatCubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            workspace: workspaceW,
            repo: desktopHarnessSessionRepo,
            connectImmediately: false,
          ),
        );
        await postFrame.flush();
        await drainPendingAsyncWork();
      });
      await pumpPhaseTransitions(tester);

      final group = registryOf().groupFor(workspaceW.workspaceId);
      final paneIds = <String>[];
      await tester.runAsync(() async {
        for (final label in ['shell-1', 'shell-2', 'shell-3']) {
          final entry = group.addEntry(
            cwd: dirW.path,
            spec: const WorkspaceTerminalLocalSpec('bash'),
            session: FakeTerminalSession(executable: 'bash'),
            select: true,
            titleLabel: label,
          );
          paneIds.add(entry.id);
        }
      });
      await pumpPhaseTransitions(tester);
      // Baseline: last pane is focused, but the session tab is the active
      // workbench tab ("the first tab" the user reports landing on).
      group.activeId = paneIds[0];
      await pumpPhaseTransitions(tester);
      expect(
        workbenchOf().state.bucket(workspaceW.workspaceId).activeTabId,
        WorkbenchTabId.session(s1),
        reason: 'baseline: session tab active before the notification tap',
      );

      Future<void> tapPaneNotification(String paneId) async {
        await tester.runAsync(
          () => handleSessionIdleNotificationTap(
            payload:
                '/home-v2/workspace/${workspaceW.workspaceId}?pane=$paneId',
            go: appRouter.go,
          ),
        );
        await tester.pump();
        await pumpPhaseTransitions(tester);
        await tester.runAsync(() async {
          await postFrame.flush();
          await drainPendingAsyncWork();
        });
        await pumpPhaseTransitions(tester);
      }

      // First tap: notification from pane 3 while the user is on the workspace.
      await tapPaneNotification(paneIds[2]);
      expect(
        group.activeId,
        paneIds[2],
        reason: 'tap must focus the originating pane',
      );
      expect(
        workbenchOf().state.bucket(workspaceW.workspaceId).activeTabId,
        WorkbenchTabId.shell(group.surfaceForPane(paneIds[2])!.id),
        reason: 'tap must activate the pane\'s shell tab over the session tab',
      );
      expect(
        appRouter.routerDelegate.currentConfiguration.uri.toString(),
        '/home-v2/workspace/${workspaceW.workspaceId}',
        reason: 'query is stripped after the deep link is consumed',
      );

      // Second tap: another pane's notification — selection must move again.
      await tapPaneNotification(paneIds[1]);
      expect(
        group.activeId,
        paneIds[1],
        reason: 'second tap must focus the other pane',
      );
      expect(
        workbenchOf().state.bucket(workspaceW.workspaceId).activeTabId,
        WorkbenchTabId.shell(group.surfaceForPane(paneIds[1])!.id),
        reason: 'second tap must activate the other pane\'s shell tab',
      );

      // Third tap: the SAME pane again (the user's repeated-click pattern) —
      // the consumed query must not wedge the dedupe guard.
      group.activeId = paneIds[0];
      await pumpPhaseTransitions(tester);
      await tapPaneNotification(paneIds[1]);
      expect(
        group.activeId,
        paneIds[1],
        reason: 'repeat tap for the same pane must re-focus it',
      );

      // Flush debounced persistence timers before the tree is disposed.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'pane deep link keeps the target shell tab against the auto-open fallback',
    (tester) async {
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

      late Workspace workspaceW;
      late Directory dirW;
      const s1 = 'noti-s1';
      await tester.runAsync(() async {
        dirW = await Directory.systemTemp.createTemp('noti_revert_w_');
        workspaceW = await desktopHarnessSessionRepo.createWorkspace([
          WorkspaceFolder(path: dirW.path),
        ]);
        await desktopHarnessSessionRepo.createSession(
          workspaceW.workspaceId,
          fixedSessionId: s1,
        );
        await chatCubit.loadWorkspaceData(desktopHarnessSessionRepo);
      });
      addTearDown(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
        await chatCubit.close();
        try {
          if (dirW.existsSync()) dirW.deleteSync(recursive: true);
        } on Object catch (_) {}
      });

      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sessionCubit =
          (await tester.runAsync(testSessionPreferencesCubit))!;
      // Production provides a WorkbenchShellLauncher from the app shell; it is
      // what lets the split pane's auto-open terminal fallback run at all.
      // The workspace below always owns a shell, so the launcher's create
      // path never fires — standalone instances are enough for scope.
      final shellLauncher = WorkbenchShellLauncher(
        workbench: WorkbenchCubit(),
        chat: chatCubit,
        registry: WorkspaceTerminalRegistry(),
        connector: WorkspaceShellConnector(
          transportFactory: TerminalTransportFactory(
            sshProfileRepository: SshProfileRepository(),
            sshCredentialStore: InMemorySshCredentialStore(),
            sshKnownHostRepository: InMemorySshKnownHostRepository(),
          ),
          sshProfileRepository: SshProfileRepository(),
        ),
        layout: layoutCubit,
      );
      await tester.pumpWidget(
        RepositoryProvider<WorkbenchEditorOpener>(
          create: (_) => WorkbenchEditorOpener(
            editor: EditorCubit(fs: LocalFilesystem()),
            workbench: WorkbenchCubit(),
            markdownViewModes: MarkdownViewModeStore(),
            readMarkdownOpenMode: () => MarkdownOpenMode.preview,
            readEditorPreviewTabs: () => true,
          ),
          child: RepositoryProvider<WorkbenchShellLauncher>.value(
            value: shellLauncher,
            child: buildTestApp(
              sessionPreferencesCubit: sessionCubit,
              chatCubit: chatCubit,
              layoutCubit: layoutCubit,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      WorkbenchCubit workbenchOf() =>
          tester.element(find.byType(TeamPilotApp)).read<WorkbenchCubit>();
      WorkspaceTerminalRegistry registryOf() =>
          tester.element(find.byType(TeamPilotApp))
                  .read<WorkspaceTerminalRegistry>();

      // Two shell panes (addEntry wraps each in its own surface → two shell
      // tabs in the strip).
      final group = registryOf().groupFor(workspaceW.workspaceId);
      late final String pane1;
      late final String pane2;
      await tester.runAsync(() async {
        final entry1 = group.addEntry(
          cwd: dirW.path,
          spec: const WorkspaceTerminalLocalSpec('bash'),
          session: FakeTerminalSession(executable: 'bash'),
          select: true,
          titleLabel: 'shell-1',
        );
        final entry2 = group.addEntry(
          cwd: dirW.path,
          spec: const WorkspaceTerminalLocalSpec('bash'),
          session: FakeTerminalSession(executable: 'bash'),
          select: true,
          titleLabel: 'shell-2',
        );
        pane1 = entry1.id;
        pane2 = entry2.id;
      });
      final tab1 = WorkbenchTabId.shell(group.surfaceForPane(pane1)!.id);
      final tab2 = WorkbenchTabId.shell(group.surfaceForPane(pane2)!.id);
      workbenchOf().ensureTab(workspaceW.workspaceId, tab1);
      workbenchOf().ensureTab(workspaceW.workspaceId, tab2);
      // The user's focus sits on the FIRST shell tab when the notification
      // from the SECOND tab's pane arrives.
      workbenchOf().select(workspaceW.workspaceId, tab1);
      group.activeId = pane1;

      appRouter.go('/home-v2/workspace/${workspaceW.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);
      expect(
        workbenchOf().state.bucket(workspaceW.workspaceId).activeTabId,
        tab1,
        reason: 'baseline: the first shell tab is active before the tap',
      );

      await tester.runAsync(
        () => handleSessionIdleNotificationTap(
          payload:
              '/home-v2/workspace/${workspaceW.workspaceId}?pane=$pane2',
          go: appRouter.go,
        ),
      );
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await tester.runAsync(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
      });
      await pumpPhaseTransitions(tester);

      expect(
        group.activeId,
        pane2,
        reason: 'tap must focus the originating pane',
      );
      expect(
        workbenchOf().state.bucket(workspaceW.workspaceId).activeTabId,
        tab2,
        reason: 'the auto-open terminal fallback must not revert the tab '
            'activated by the deep link back to the previously focused shell',
      );
      expect(
        appRouter.routerDelegate.currentConfiguration.uri.toString(),
        '/home-v2/workspace/${workspaceW.workspaceId}',
        reason: 'query is stripped after the deep link is consumed',
      );

      // Flush debounced persistence timers before the tree is disposed.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'pane deep link to a workspace whose page is not yet mounted is not '
    'stolen by another workspace page',
    (tester) async {
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

      late Workspace workspaceW;
      late Workspace workspaceX;
      late Directory dirW;
      late Directory dirX;
      await tester.runAsync(() async {
        dirW = await Directory.systemTemp.createTemp('noti_steal_w_');
        dirX = await Directory.systemTemp.createTemp('noti_steal_x_');
        workspaceW = await desktopHarnessSessionRepo.createWorkspace([
          WorkspaceFolder(path: dirW.path),
        ]);
        workspaceX = await desktopHarnessSessionRepo.createWorkspace([
          WorkspaceFolder(path: dirX.path),
        ]);
        await desktopHarnessSessionRepo.createSession(
          workspaceW.workspaceId,
          fixedSessionId: 'noti-w1',
        );
        await desktopHarnessSessionRepo.createSession(
          workspaceX.workspaceId,
          fixedSessionId: 'noti-x1',
        );
        await chatCubit.loadWorkspaceData(desktopHarnessSessionRepo);
      });
      addTearDown(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
        await chatCubit.close();
        for (final dir in [dirW, dirX]) {
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
            readEditorPreviewTabs: () => true,
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

      WorkbenchCubit workbenchOf() =>
          tester.element(find.byType(TeamPilotApp)).read<WorkbenchCubit>();
      WorkspaceTerminalRegistry registryOf() =>
          tester.element(find.byType(TeamPilotApp))
                  .read<WorkspaceTerminalRegistry>();

      // Open W only: its keep-alive page is mounted, while X's page has never
      // mounted (a workspace page mounts one frame after its tab becomes
      // active). X already owns two live shell panes.
      appRouter.go('/home-v2/workspace/${workspaceW.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);

      final groupX = registryOf().groupFor(workspaceX.workspaceId);
      late final String pane1;
      late final String pane2;
      await tester.runAsync(() async {
        final entry1 = groupX.addEntry(
          cwd: dirX.path,
          spec: const WorkspaceTerminalLocalSpec('bash'),
          session: FakeTerminalSession(executable: 'bash'),
          select: true,
          titleLabel: 'shell-1',
        );
        final entry2 = groupX.addEntry(
          cwd: dirX.path,
          spec: const WorkspaceTerminalLocalSpec('bash'),
          session: FakeTerminalSession(executable: 'bash'),
          select: true,
          titleLabel: 'shell-2',
        );
        pane1 = entry1.id;
        pane2 = entry2.id;
      });
      // The notification comes from X's second pane while pane 1 is focused.
      groupX.activeId = pane1;
      await pumpPhaseTransitions(tester);

      await tester.runAsync(
        () => handleSessionIdleNotificationTap(
          payload:
              '/home-v2/workspace/${workspaceX.workspaceId}?pane=$pane2',
          go: appRouter.go,
        ),
      );
      // Frame 1: W's keep-alive page also sees the foreign pane query; only
      // frames later does X's own page mount and consume it.
      await tester.pump();
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await tester.runAsync(() async {
        await postFrame.flush();
        await drainPendingAsyncWork();
      });
      await pumpPhaseTransitions(tester);

      expect(
        groupX.activeId,
        pane2,
        reason: 'the owning workspace must consume the pane deep link',
      );
      expect(
        workbenchOf().state.bucket(workspaceX.workspaceId).activeTabId,
        WorkbenchTabId.shell(groupX.surfaceForPane(pane2)!.id),
        reason: 'the owning workspace must activate the pane\'s shell tab',
      );
      expect(
        appRouter.routerDelegate.currentConfiguration.uri.toString(),
        '/home-v2/workspace/${workspaceX.workspaceId}',
        reason: 'query is stripped after the deep link is consumed',
      );

      // Flush debounced persistence timers before the tree is disposed.
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
