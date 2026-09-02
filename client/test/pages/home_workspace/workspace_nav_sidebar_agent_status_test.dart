import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workspace_groups_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/pages/home_workspace/workspace_nav_sidebar.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/workspace_shell_connector.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/widgets/session_working_spinner.dart';
import 'package:teampilot/widgets/workspace_agent_status_indicator.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late ChatCubit chatCubit;
  late AgentAttentionCubit attentionCubit;
  late WorkspaceGroupsCubit groupsCubit;

  setUp(() {
    setUpTestAppStorage();
    chatCubit = testChatCubit(executableResolver: () => 'claude');
    attentionCubit = AgentAttentionCubit(pruneInterval: null);
    groupsCubit = WorkspaceGroupsCubit();
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!attentionCubit.isClosed) await attentionCubit.close();
    if (!groupsCubit.isClosed) await groupsCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpSidebar(
    WidgetTester tester, {
    WorkspaceTerminalRegistry? terminalRegistry,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget sidebar = WorkspaceNavSidebar(
      location: '/home-v2',
      openTabs: const [],
      onHomeTap: () {},
      onCloseTab: (_) {},
    );
    if (terminalRegistry != null) {
      sidebar = RepositoryProvider<WorkspaceTerminalRegistry>.value(
        value: terminalRegistry,
        child: sidebar,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<ChatCubit>.value(value: chatCubit),
              BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
              BlocProvider<WorkspaceGroupsCubit>.value(value: groupsCubit),
            ],
            child: sidebar,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // Seeds two workspaces, each with one session, into the ChatCubit state.
  void seedWorkspaces() {
    chatCubit.ingestWorkspaceSessionSnapshot(
      workspaces: [
        Workspace(workspaceId: 'ws-a', folders: const [], createdAt: 1),
        Workspace(workspaceId: 'ws-b', folders: const [], createdAt: 2),
      ],
      sessions: [
        AppSession(
          sessionId: 'session-a',
          workspaceId: 'ws-a',
          createdAt: 1,
        ),
        AppSession(
          sessionId: 'session-b',
          workspaceId: 'ws-b',
          createdAt: 2,
        ),
      ],
    );
  }

  testWidgets('idle workspace shows no indicator', (tester) async {
    seedWorkspaces();
    await pumpSidebar(tester);

    expect(find.byType(WorkspaceAgentStatusIndicator), findsNothing);
    expect(find.byType(SessionWorkingSpinner), findsNothing);
  });

  testWidgets('working session shows spinner on its workspace row only', (
    tester,
  ) async {
    seedWorkspaces();
    attentionCubit.applyEvent(
      sessionId: 'session-a',
      memberId: 'm1',
      event: const AgentStatusEvent(state: AgentSeatAttention.working),
      skipPermissions: false,
    );
    await pumpSidebar(tester);

    expect(find.byType(SessionWorkingSpinner), findsOneWidget);
  });

  testWidgets('waiting and working show on their own workspace rows', (
    tester,
  ) async {
    seedWorkspaces();
    attentionCubit.applyEvent(
      sessionId: 'session-a',
      memberId: 'm1',
      event: const AgentStatusEvent(state: AgentSeatAttention.working),
      skipPermissions: false,
    );
    attentionCubit.applyEvent(
      sessionId: 'session-b',
      memberId: 'm1',
      event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
      skipPermissions: false,
    );
    await pumpSidebar(tester);

    expect(find.byType(SessionWorkingSpinner), findsOneWidget);
    expect(find.byIcon(Icons.front_hand_rounded), findsOneWidget);
  });

  testWidgets('waiting on one session wins over working in the same workspace', (
    tester,
  ) async {
    seedWorkspaces();
    attentionCubit.applyEvent(
      sessionId: 'session-a',
      memberId: 'm1',
      event: const AgentStatusEvent(state: AgentSeatAttention.working),
      skipPermissions: false,
    );
    attentionCubit.applyEvent(
      sessionId: 'session-a',
      memberId: 'm2',
      event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
      skipPermissions: false,
    );
    await pumpSidebar(tester);

    expect(find.byType(SessionWorkingSpinner), findsNothing);
    expect(find.byIcon(Icons.front_hand_rounded), findsOneWidget);
  });

  testWidgets('done and interrupted show distinct static icons', (
    tester,
  ) async {
    seedWorkspaces();
    attentionCubit.applyEvent(
      sessionId: 'session-a',
      memberId: 'm1',
      event: const AgentStatusEvent(state: AgentSeatAttention.done),
      skipPermissions: false,
    );
    attentionCubit.applyEvent(
      sessionId: 'session-b',
      memberId: 'm1',
      event: const AgentStatusEvent(
        state: AgentSeatAttention.done,
        interrupted: true,
      ),
      skipPermissions: false,
    );
    await pumpSidebar(tester);

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_rounded), findsOneWidget);
  });

  testWidgets('status clears when the seat map empties', (tester) async {
    seedWorkspaces();
    attentionCubit.applyEvent(
      sessionId: 'session-a',
      memberId: 'm1',
      event: const AgentStatusEvent(state: AgentSeatAttention.working),
      skipPermissions: false,
    );
    await pumpSidebar(tester);
    expect(find.byType(SessionWorkingSpinner), findsOneWidget);

    attentionCubit.clearSeat(sessionId: 'session-a', memberId: 'm1');
    await tester.pump();
    expect(find.byType(SessionWorkingSpinner), findsNothing);
  });

  testWidgets('shell-terminal seat lights only its workspace row', (
    tester,
  ) async {
    seedWorkspaces();
    final registry = WorkspaceTerminalRegistry();
    addTearDown(registry.disposeAll);
    final entry = registry.groupFor('ws-a').addEntry(
      cwd: '/tmp',
      spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
      session: TerminalSession(
        executable: '/bin/bash',
        validateLaunch: false,
        parseExecutable: false,
      ),
      select: true,
    );
    final seatId = WorkspaceShellConnector.seatIdFor(entry.id);
    attentionCubit.applyEvent(
      sessionId: seatId,
      memberId: seatId,
      event: const AgentStatusEvent(state: AgentSeatAttention.working),
      skipPermissions: false,
    );
    await pumpSidebar(tester, terminalRegistry: registry);

    expect(find.byType(SessionWorkingSpinner), findsOneWidget);
  });

  testWidgets('shell-terminal seat stops lighting the row after pane close', (
    tester,
  ) async {
    seedWorkspaces();
    final registry = WorkspaceTerminalRegistry();
    addTearDown(registry.disposeAll);
    final group = registry.groupFor('ws-a');
    final entry = group.addEntry(
      cwd: '/tmp',
      spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
      session: TerminalSession(
        executable: '/bin/bash',
        validateLaunch: false,
        parseExecutable: false,
      ),
      select: true,
    );
    final seatId = WorkspaceShellConnector.seatIdFor(entry.id);
    attentionCubit.applyEvent(
      sessionId: seatId,
      memberId: seatId,
      event: const AgentStatusEvent(state: AgentSeatAttention.working),
      skipPermissions: false,
    );
    await pumpSidebar(tester, terminalRegistry: registry);
    expect(find.byType(SessionWorkingSpinner), findsOneWidget);

    group.removeEntry(entry.id);
    // The badge rebuilds from a post-frame callback (registry notifications
    // can fire mid-build), so pump twice: once to run the callback, once to
    // render the setState it schedules.
    await tester.pump();
    await tester.pump();
    expect(find.byType(SessionWorkingSpinner), findsNothing);
  });
}
