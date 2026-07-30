import 'dart:io';

import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/cli_tool.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/post_frame_test_harness.dart';

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
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_team_stage_',
        );
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          const WorkspaceFolder(path: '/remote', targetId: 'ssh:host'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,

        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
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
      'deleteSession of the active open tab enters new-chat landing',
      () async {
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_delete_active_',
        );
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/a'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,

        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
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
