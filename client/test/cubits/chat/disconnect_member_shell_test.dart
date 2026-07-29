import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_open_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';

import '../../support/fake_terminal_session.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'disconnectMemberShell targets arbitrary session member, not only active',
    () async {
      final tmp = await Directory.systemTemp.createTemp('disconnect_member_');
      addTearDown(() => deleteTempDirBestEffort(tmp));
      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        const WorkspaceFolder(path: '/work'),
      ]);
      final sessionA = await repo.createSession(
        workspace.workspaceId,
      );
      final sessionB = await repo.createSession(
        workspace.workspaceId,
      );

      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: () => 'flashskyai',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                FakeTerminalSession(
                  executable: executable,
                  scrollbackLines: scrollbackLines,
                ),
        postFrameScheduler: postFrame.scheduler,
        lifecycleService: SessionLifecycleService(),
      );
      addTearDown(() => tearDownChatCubitWithSessionPersist(cubit, postFrame));
      await cubit.loadWorkspaceData(repo);
      cubit.activateWorkspaceTab(
        workspaceTabKey: workspace.workspaceId,
      );

      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: sessionA,
          repo: repo,
        ),
      );
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: sessionB,
          repo: repo,
        ),
      );
      await drainPendingAsyncWork();
      await postFrame.flush();

      final tabA = cubit.tabStore.openTabBySessionId(sessionA.sessionId)!;
      final tabB = cubit.tabStore.openTabBySessionId(sessionB.sessionId)!;
      final memberId = sessionA.sessionId;

      final shellA = FakeTerminalSession(executable: 'bin-a');
      final shellB = FakeTerminalSession(executable: 'bin-b');
      shellA.connect(workingDirectory: '/work');
      shellB.connect(workingDirectory: '/work');
      tabA.memberShells[memberId] = shellA;
      tabB.memberShells[memberId] = shellB;
      tabA.selectedMemberId = memberId;
      tabB.selectedMemberId = memberId;

      // Make A the active tab; Resource Manager kill must still hit B.
      final indexA = cubit.tabStore
          .tabsForWorkspace(workspace.workspaceId)
          .indexWhere((t) => t.info.id == sessionA.sessionId);
      expect(indexA, greaterThanOrEqualTo(0));
      cubit.selectTab(indexA);
      expect(cubit.state.activeSessionId, sessionA.sessionId);
      expect(shellA.isRunning, isTrue);
      expect(shellB.isRunning, isTrue);

      cubit.disconnectMemberShell(sessionB.sessionId, memberId);

      expect(shellB.isRunning, isFalse);
      expect(shellA.isRunning, isTrue);
      expect(tabB.memberShells.containsKey(memberId), isTrue);
    },
  );
}
