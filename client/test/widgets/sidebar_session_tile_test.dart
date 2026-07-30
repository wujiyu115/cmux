import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:teampilot/widgets/session_working_spinner.dart';
import 'package:teampilot/widgets/sidebar_session_tile.dart';

import '../support/post_frame_test_harness.dart';

final _session = AppSession(
  sessionId: 'sess-1',
  workspaceId: 'ws1',
  createdAt: 1,
  updatedAt: 1,
);

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit()
    : super(
        executableResolver: () => 'true',
      );

  final selectedMembers = <String>[];
  final activeSessionAtSelectMember = <String?>[];
  final eventOrder = <String>[];

  @override
  void selectMember(String memberId) {
    eventOrder.add('selectMember:$memberId');
    activeSessionAtSelectMember.add(state.activeSessionId);
    selectedMembers.add(memberId);
    super.selectMember(memberId);
  }
}

Widget _host({
  required ChatCubit chatCubit,
  required SessionRepository sessionRepository,
  required AgentAttentionCubit attentionCubit,
  Widget? child,
  FutureOr<void> Function()? onTap,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SessionRepository>.value(value: sessionRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ChatCubit>.value(value: chatCubit),
          BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
        ],
        child: Scaffold(
          body:
              child ??
              SidebarSessionTile(
                session: _session,
                onTap: onTap ?? () {},
              ),
        ),
      ),
    ),
  );
}

AgentAttentionCubit _tileAttention() {
  return AgentAttentionCubit(pruneInterval: null);
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets(
    'title Text follows ChatCubit SessionRowContent even if widget.session is stale',
    (tester) async {
      final chatCubit = testChatCubit(executableResolver: () => 'claude');
      final attention = _tileAttention();
      addTearDown(chatCubit.close);
      addTearDown(attention.close);

      final stale = AppSession(
        sessionId: 'sess-1',
        workspaceId: 'ws1',
        display: 'StaleTitle',
        createdAt: 1,
        updatedAt: 1,
      );
      chatCubit.applyState(
        chatCubit.state.copyWith(
          sessions: [
            stale.copyWith(display: 'LiveTitle'),
          ],
        ),
      );

      await tester.pumpWidget(
        _host(
          chatCubit: chatCubit,
          attentionCubit: attention,
          sessionRepository: SessionRepository(),
          child: SidebarSessionTile(
            session: stale,
            onTap: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('LiveTitle'), findsOneWidget);
      expect(find.text('StaleTitle'), findsNothing);

      chatCubit.applyState(
        chatCubit.state.copyWith(
          sessions: [
            stale.copyWith(display: 'RenamedTitle'),
          ],
          stateVersion: chatCubit.state.stateVersion + 1,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('RenamedTitle'), findsOneWidget);
      expect(find.text('LiveTitle'), findsNothing);
    },
  );

  testWidgets('pinned session shows trailing push_pin when idle', (tester) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final attention = _tileAttention();
    addTearDown(chatCubit.close);
    addTearDown(attention.close);

    final pinned = AppSession(
      sessionId: 'sess-pinned',
      workspaceId: 'ws1',
      createdAt: 1,
      updatedAt: 1,
      pinned: true,
    );

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        attentionCubit: attention,
        sessionRepository: SessionRepository(),
        child: SidebarSessionTile(
          session: pinned,
          onTap: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
  });

  testWidgets('unpinned session does not show trailing push_pin when idle', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final attention = _tileAttention();
    addTearDown(chatCubit.close);
    addTearDown(attention.close);

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        attentionCubit: attention,
        sessionRepository: SessionRepository(),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.push_pin), findsNothing);
  });

  testWidgets('waiting marker is visible and distinct from working spinner', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final attention = _tileAttention();
    addTearDown(chatCubit.close);
    addTearDown(attention.close);

    chatCubit.emit(
      chatCubit.state.copyWith(workingSessionIds: {_session.sessionId}),
    );
    attention.applyEvent(
      sessionId: _session.sessionId,
      memberId: 'seat-a',
      event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
      skipPermissions: false,
    );

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        sessionRepository: SessionRepository(),
        attentionCubit: attention,
      ),
    );
    await tester.pump();

    expect(find.byKey(AppKeys.sidebarSessionWaitingMarker), findsOneWidget);
    expect(find.byType(SessionWorkingSpinner), findsNothing);
  });

  testWidgets('working spinner shows when session is working without waiting', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final attention = _tileAttention();
    addTearDown(chatCubit.close);
    addTearDown(attention.close);

    chatCubit.emit(
      chatCubit.state.copyWith(workingSessionIds: {_session.sessionId}),
    );

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        sessionRepository: SessionRepository(),
        attentionCubit: attention,
      ),
    );
    await tester.pump();

    expect(find.byType(SessionWorkingSpinner), findsOneWidget);
    expect(find.byKey(AppKeys.sidebarSessionWaitingMarker), findsNothing);
  });

  testWidgets('tap while waiting activates Terminal and first waiting seat', (
    tester,
  ) async {
    final chatCubit = _RecordingChatCubit();
    final attention = _tileAttention();
    addTearDown(chatCubit.close);
    addTearDown(attention.close);

    attention.applyEvent(
      sessionId: _session.sessionId,
      memberId: 'seat-waiting',
      event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
      skipPermissions: false,
    );

    var activated = false;
    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        sessionRepository: SessionRepository(),
        attentionCubit: attention,
        onTap: () => activated = true,
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(SidebarSessionTile));
    await tester.pump();

    expect(activated, isTrue);
    expect(chatCubit.selectedMembers, ['seat-waiting']);
  });

  testWidgets(
    'cross-session waiting jump awaits open before seat/Terminal',
    (tester) async {
      final sessionB = AppSession(
        sessionId: 'sess-b',
        workspaceId: 'ws1',
        createdAt: 1,
        updatedAt: 1,
      );
      final chatCubit = _RecordingChatCubit();
      final attention = _tileAttention();
      addTearDown(chatCubit.close);
      addTearDown(attention.close);

      // Session A is active; waiting is on B.
      chatCubit.emit(
        chatCubit.state.copyWith(
          activeSessionId: 'sess-a',
          selectedMemberId: 'member-a',
        ),
      );
      attention.applyEvent(
        sessionId: sessionB.sessionId,
        memberId: 'seat-b',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );

      final openCompleter = Completer<void>();
      await tester.pumpWidget(
        _host(
          chatCubit: chatCubit,
          sessionRepository: SessionRepository(),
          attentionCubit: attention,
          child: SidebarSessionTile(
            session: sessionB,
            onTap: () async {
              chatCubit.eventOrder.add('activate-start');
              await openCompleter.future;
              chatCubit.emit(
                chatCubit.state.copyWith(
                  activeSessionId: sessionB.sessionId,
                  selectedMemberId: '',
                ),
              );
              chatCubit.eventOrder.add('activate-done');
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(SidebarSessionTile));
      await tester.pump();

      // Still opening B — must not selectMember / switch Terminal on A yet.
      expect(chatCubit.selectedMembers, isEmpty);
      expect(chatCubit.state.activeSessionId, 'sess-a');

      openCompleter.complete();
      await tester.pump();
      await tester.pump();

      expect(chatCubit.state.activeSessionId, sessionB.sessionId);
      expect(chatCubit.activeSessionAtSelectMember, [sessionB.sessionId]);
      expect(chatCubit.selectedMembers, ['seat-b']);
    },
  );
}
