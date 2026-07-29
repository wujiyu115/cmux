import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/theme/app_theme.dart';

import '../../../support/post_frame_test_harness.dart';

class _MockChatCubit extends Mock implements ChatCubit {}




class _MockSessionPreferencesCubit extends Mock
    implements SessionPreferencesCubit {}


class _MockWorktreeCubit extends Mock implements WorktreeCubit {}

void _stubCubit<TState>(Cubit<TState> cubit, TState state) {
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream).thenAnswer((_) => Stream<TState>.empty());
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets(
    'initialText fills compose field once and survives draft reload',
    (tester) async {
      const seed = 'Selected context\n\n';
      final workspace = Workspace(workspaceId: 'workspace-1', createdAt: 1);
      final chatCubit = _MockChatCubit();
      final sessionPreferencesCubit = _MockSessionPreferencesCubit();
      final worktreeCubit = _MockWorktreeCubit();

      _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
      _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
      _stubCubit(worktreeCubit, const WorktreeState());
      when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);

      Widget landing(String initialText) {
        final theme = buildDarkTheme();
        return MultiRepositoryProvider(
          providers: [
            RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ChatCubit>.value(value: chatCubit),
              BlocProvider<SessionPreferencesCubit>.value(
                value: sessionPreferencesCubit,
              ),
              BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
            ],
            child: MaterialApp(
                theme: theme,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: TpTheme(
                  data: TpThemeData.fromColorScheme(
                    theme.colorScheme,
                    scale: 1,
                  ),
                  child: Scaffold(
                    body: WorkspaceChatLanding(
                      workspace: workspace,
                      initialText: initialText,
                      onSubmit: (_, _) {},
                    ),
                  ),
                ),
              ),
            ),
        );
      }

      await tester.pumpWidget(landing(seed));
      await tester.pumpAndSettle();

      TextField field() =>
          tester.widget<TextField>(find.byType(TextField).first);
      expect(field().controller!.text, seed);
      expect(field().controller!.selection.baseOffset, seed.length);

      await tester.pumpWidget(landing('replacement'));
      await tester.pump();

      expect(field().controller!.text, seed);
    },
  );
}
