import 'dart:io';

import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/post_frame_test_harness.dart';

String _executable() => 'flashskyai';

void _registerTempCubitCleanup({
  required Directory tmp,
  required ChatCubit cubit,
  PostFrameTestHarness? postFrame,
}) {
  addTearDown(() async {
    if (postFrame != null) {
      await postFrame.flush();
    }
    await drainPendingAsyncWork();
    await cubit.close();
    try {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows CI may retain directory handles briefly after bus teardown.
    }
  });
}

class _FakeTerminalSession extends TerminalSession {
  _FakeTerminalSession({required super.executable});

  var _running = false;
  var _connecting = false;
  final connectedMembers = <String>[];
  final connectedSessionTeams = <String?>[];

  @override
  bool get isRunning => _running || _connecting;

  @override
  bool get isConnecting => _connecting;

  @override
  void connect({
    required String workingDirectory,
    List<String> arguments = const [],
    Map<String, String>? extraEnvironment,
    void Function()? onProcessStarted,
    void Function(String message)? onProcessFailed,
    void Function()? onProcessExited,
    void Function(String line)? onFirstUserLineSubmitted,
    void Function(String line)? onEveryUserLineSubmitted,
    String? executableOverride,
  }) {
    _connecting = true;
    _connecting = false;
    _running = true;
    onProcessStarted?.call();
  }

  @override
  void disconnect() {
    _running = false;
    _connecting = false;
  }

  @override
  void dispose() {
    _running = false;
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('ChatCubit team session scope', () {
    late ChatCubit cubit;

    setUp(() {
      cubit = ChatCubit(
        executableResolver: _executable,
        automationRepository: testAutomationRepository(),
      );
    });

    tearDown(() async {
      await cubit.close();
    });

    test('visible lists mirror full data when scope is off', () {
      const workspaceId = 'p1';
      cubit.ingestWorkspaceSessionSnapshot(
        workspaces: [
          Workspace(
            workspaceId: workspaceId,
            folders: [WorkspaceFolder(path: '/a')],
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1'],
          ),
        ],
        sessions: [
          AppSession(
            sessionId: 's1',
            workspaceId: workspaceId,
            folders: [WorkspaceFolder(path: '/a')],
            sessionTeam: 'team-a',
            createdAt: 1,
            updatedAt: 1,
          ),
        ],
      );
      expect(cubit.state.workspaces.length, 1);
      expect(cubit.state.visibleWorkspaces, cubit.state.workspaces);
      expect(cubit.state.visibleSessions, cubit.state.sessions);
    });

    test('scope on filters sessions and workspaces by selected team id', () {
      const pA = 'p-a';
      const pB = 'p-b';
      cubit.ingestWorkspaceSessionSnapshot(
        workspaces: [
          Workspace(
            workspaceId: pA,
            folders: [WorkspaceFolder(path: '/a')],
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1', 's2'],
          ),
          Workspace(
            workspaceId: pB,
            folders: [WorkspaceFolder(path: '/b')],
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s3'],
          ),
        ],
        sessions: [
          AppSession(
            sessionId: 's1',
            workspaceId: pA,
            folders: [WorkspaceFolder(path: '/a')],
            sessionTeam: 'tid-1',
            createdAt: 1,
            updatedAt: 1,
          ),
          AppSession(
            sessionId: 's2',
            workspaceId: pA,
            folders: [WorkspaceFolder(path: '/a')],
            sessionTeam: 'tid-2',
            createdAt: 1,
            updatedAt: 1,
          ),
          AppSession(
            sessionId: 's3',
            workspaceId: pB,
            folders: [WorkspaceFolder(path: '/b')],
            sessionTeam: 'tid-1',
            createdAt: 1,
            updatedAt: 1,
          ),
        ],
      );

      cubit.setTeamSessionScope(
        scopeSessionsToSelectedTeam: true,
        selectedTeamId: 'tid-1',
      );

      expect(cubit.state.sessions.length, 3);
      expect(
        cubit.state.visibleSessions.map((e) => e.sessionId).toList()..sort(),
        ['s1', 's3'],
      );
      expect(cubit.state.visibleWorkspaces.map((e) => e.workspaceId).toSet(), {
        'p-a',
        'p-b',
      });
    });

    test('scope on with no selected team shows personal sessions only', () {
      const pid = 'p1';
      cubit.ingestWorkspaceSessionSnapshot(
        workspaces: [
          Workspace(
            workspaceId: pid,
            folders: [WorkspaceFolder(path: '/a')],
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1'],
          ),
        ],
        sessions: [
          AppSession(
            sessionId: 's1',
            workspaceId: pid,
            folders: [WorkspaceFolder(path: '/a')],
            sessionTeam: 'tid',
            createdAt: 1,
            updatedAt: 1,
          ),
        ],
      );
      cubit.setTeamSessionScope(
        scopeSessionsToSelectedTeam: true,
        selectedTeamId: null,
      );
      expect(cubit.state.visibleSessions, isEmpty);
      expect(cubit.state.visibleWorkspaces.map((e) => e.workspaceId).toList(), [
        pid,
      ]);
    });

    test('changing scope or team id updates visible lists', () {
      const pid = 'p1';
      cubit.ingestWorkspaceSessionSnapshot(
        workspaces: [
          Workspace(
            workspaceId: pid,
            folders: [WorkspaceFolder(path: '/a')],
            createdAt: 1,
            updatedAt: 1,
            sessionIds: ['s1', 's2'],
          ),
        ],
        sessions: [
          AppSession(
            sessionId: 's1',
            workspaceId: pid,
            folders: [WorkspaceFolder(path: '/a')],
            sessionTeam: 'alpha',
            createdAt: 1,
            updatedAt: 1,
          ),
          AppSession(
            sessionId: 's2',
            workspaceId: pid,
            folders: [WorkspaceFolder(path: '/a')],
            sessionTeam: 'beta',
            createdAt: 1,
            updatedAt: 1,
          ),
        ],
      );

      cubit.setTeamSessionScope(
        scopeSessionsToSelectedTeam: true,
        selectedTeamId: 'alpha',
      );
      expect(cubit.state.visibleSessions.single.sessionId, 's1');

      cubit.setTeamSessionScope(
        scopeSessionsToSelectedTeam: true,
        selectedTeamId: 'beta',
      );
      expect(cubit.state.visibleSessions.single.sessionId, 's2');

      cubit.setTeamSessionScope(
        scopeSessionsToSelectedTeam: false,
        selectedTeamId: 'beta',
      );
      expect(cubit.state.visibleSessions.length, 2);
    });
  });

  group('connectWorkspaceSession', () {
    late Directory tmp;
    late SessionRepository repo;
    late ChatCubit cubit;
    late PostFrameTestHarness postFrame;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      setUpTestAppStorage();
      tmp = Directory(AppStorage.paths.basePath);
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                _FakeTerminalSession(executable: executable),
      );
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp'),
      ]);
      await cubit.loadWorkspaceData(repo);
      cubit.setActiveWorkspace(workspace.workspaceId);
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork();
      await cubit.close();
      await drainPendingAsyncWork();
      tearDownTestAppStorage();
    });


    test(
      'personal connect materializes first session when tabs empty',
      () async {
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp/personal-connect'),
        ]);
        await cubit.loadWorkspaceData(repo);
        cubit.setActiveWorkspace(workspace.workspaceId);
        expect(cubit.state.tabs, isEmpty);

        await cubit.connectWorkspaceSession(
          PersonalSessionConnect(workspaceId: workspace.workspaceId),
          repo: repo,
        );
        await postFrame.flush();
        await drainPendingAsyncWork();

        expect(cubit.state.tabs.length, 1);
        expect(cubit.state.sessions.single.sessionTeam, '');
      },
    );

    test(
      'requestOpenSession stages tab and connecting before async prep completes',
      () async {
        final tmp = await Directory.systemTemp.createTemp('chat_cubit_stage_');
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        final session = await repo.createSession(workspace.workspaceId);
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);
        await cubit.loadWorkspaceData(repo);

        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            workspace: workspace,
            repo: repo,
          ),
        );

        expect(cubit.state.tabs, hasLength(1));
        expect(cubit.state.activeSessionId, session.sessionId);
        expect(cubit.state.sessionConnectingId, session.sessionId);
      },
    );

    test(
      'requestCreateAndOpenSession stages tab before disk persist completes',
      () async {
        final tmp = await Directory.systemTemp.createTemp('chat_cubit_create_');
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          const WorkspaceFolder(path: '/remote', targetId: 'ssh:host'),
        ]);
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);
        await cubit.loadWorkspaceData(repo);

        await cubit.requestCreateAndOpenSession(
          SessionCreateRequest(
            workspace: workspace,
            isPersonal: true,
            repo: repo,
            cli: CliTool.claude,
          ),
        );

        expect(cubit.state.tabs, hasLength(1));
        expect(cubit.state.activeSessionId, isNotEmpty);
        expect(cubit.state.sessionConnectingId, cubit.state.activeSessionId);
        expect(cubit.state.sessions, hasLength(1));
      },
    );

    test(
      'requestOpenSession stages team tab before async readiness check',
      () async {
        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_team_stage_',
        );
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          const WorkspaceFolder(path: '/remote', targetId: 'ssh:host'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,
          sessionTeam: team.id,
          rosterMembers: team.members,

          memberClis: {for (final m in team.members) m.id: CliTool.claude},
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);
        await cubit.loadWorkspaceData(repo);

        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            workspace: workspace,
            team: team,
            member: team.members.first,
            repo: repo,
          ),
        );

        expect(cubit.state.tabs, hasLength(1));
        expect(cubit.state.activeSessionId, session.sessionId);
        expect(cubit.state.sessionConnectingId, session.sessionId);
      },
    );




    test(
      'deleteSession of the active open tab enters new-chat landing',
      () async {
        const team = TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
        );
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_delete_active_',
        );
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/a'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,
          sessionTeam: team.id,
          rosterMembers: team.members,

          memberClis: {for (final m in team.members) m.id: CliTool.claude},
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

        await cubit.loadWorkspaceData(repo);
        cubit.setActiveWorkspace(workspace.workspaceId);
        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: session,
            team: team,
            member: team.members.first,
            repo: repo,
          ),
        );
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(cubit.state.tabs, hasLength(1));
        expect(cubit.state.newChatActive, isFalse);
        expect(cubit.state.activeSessionId, session.sessionId);

        await cubit.deleteSession(repo, session.sessionId);
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(cubit.state.tabs, isEmpty);
        expect(cubit.state.newChatActive, isTrue);
        expect(cubit.state.activeSessionId, isNull);
        expect(
          cubit.state.sessions.any((s) => s.sessionId == session.sessionId),
          isFalse,
        );
      },
    );



  });
}
