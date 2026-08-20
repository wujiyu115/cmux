import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';
import 'package:teampilot/repositories/session_repository.dart';

import '../../support/post_frame_test_harness.dart';

/// Records [renameSession] instead of touching `session.json`.
class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit() : super(executableResolver: () => 'true');

  final renames = <String>[];

  @override
  Future<void> renameSession(
    SessionRepository repo,
    String sessionId,
    String newName,
  ) async {
    renames.add('$sessionId:$newName');
  }
}

Widget _wrap({required ChatCubit chatCubit, required Widget child}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: RepositoryProvider<SessionRepository>.value(
      value: SessionRepository(),
      child: BlocProvider<ChatCubit>.value(
        value: chatCubit,
        child: Scaffold(body: child),
      ),
    ),
  );
}

Widget _sessionChip() => const WorkspaceShellTabChip(
  sessionId: 'sess-1',
  title: 'Old title',
  active: true,
  onTap: _noop,
  onClose: _noop,
);

void _noop() {}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  ChatCubit seededCubit() {
    final cubit = _RecordingChatCubit();
    cubit.emit(
      cubit.state.copyWith(
        sessions: [
          AppSession(
            sessionId: 'sess-1',
            workspaceId: 'ws1',
            display: 'Old title',
            createdAt: 1,
            updatedAt: 1,
          ),
        ],
      ),
    );
    return cubit;
  }

  testWidgets('session tab context menu renames through ChatCubit', (
    tester,
  ) async {
    final chatCubit = seededCubit() as _RecordingChatCubit;
    addTearDown(chatCubit.close);

    await tester.pumpWidget(_wrap(chatCubit: chatCubit, child: _sessionChip()));
    await tester.pump();

    await tester.tap(
      find.byType(WorkspaceShellTabChip),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Rename conversation'), findsOneWidget);
    await tester.tap(find.text('Rename conversation'));
    await tester.pumpAndSettle();

    // Dialog opens pre-filled with the live title.
    expect(find.text('Rename Conversation'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  New title  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(chatCubit.renames, ['sess-1:New title']);
  });

  testWidgets('double-tapping a session tab opens the rename dialog', (
    tester,
  ) async {
    final chatCubit = seededCubit() as _RecordingChatCubit;
    addTearDown(chatCubit.close);

    await tester.pumpWidget(_wrap(chatCubit: chatCubit, child: _sessionChip()));
    await tester.pump();

    final chip = find.byType(WorkspaceShellTabChip);
    await tester.tap(chip);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(find.text('Rename Conversation'), findsOneWidget);
  });

  testWidgets('blank rename is discarded', (tester) async {
    final chatCubit = seededCubit() as _RecordingChatCubit;
    addTearDown(chatCubit.close);

    await tester.pumpWidget(_wrap(chatCubit: chatCubit, child: _sessionChip()));
    await tester.pump();

    await tester.tap(
      find.byType(WorkspaceShellTabChip),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename conversation'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(chatCubit.renames, isEmpty);
  });

  testWidgets('non-session tab omits rename', (tester) async {
    final chatCubit = seededCubit();
    addTearDown(chatCubit.close);

    await tester.pumpWidget(
      _wrap(
        chatCubit: chatCubit,
        child: WorkspaceShellTabChip(
          title: 'run-task',
          active: true,
          onTap: _noop,
          onClose: _noop,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byType(WorkspaceShellTabChip),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Rename conversation'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });
}
