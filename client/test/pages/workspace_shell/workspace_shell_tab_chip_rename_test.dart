import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';

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

Widget _wrap({
  required ChatCubit chatCubit,
  required Widget child,
  WorkspaceTerminalRegistry? registry,
}) {
  Widget subtree = RepositoryProvider<SessionRepository>.value(
    value: SessionRepository(),
    child: BlocProvider<ChatCubit>.value(
      value: chatCubit,
      child: Scaffold(body: child),
    ),
  );
  if (registry != null) {
    subtree = RepositoryProvider<WorkspaceTerminalRegistry>.value(
      value: registry,
      child: subtree,
    );
  }
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: subtree,
  );
}

/// One workspace group holding a single surface ("Local") backed by a real
/// [TerminalSession] that never launches.
(WorkspaceTerminalRegistry, String) _shellRegistry() {
  final registry = WorkspaceTerminalRegistry();
  final group = registry.groupFor('ws1');
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
  entry.titleLabel = 'Local';
  return (registry, group.surfaces.single.id);
}

Widget _shellChip(String surfaceId) => WorkspaceShellTabChip(
  shellSurfaceId: surfaceId,
  title: 'Local',
  active: true,
  onTap: _noop,
  onClose: _noop,
);

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

  testWidgets('shell tab context menu renames through the registry', (
    tester,
  ) async {
    final chatCubit = seededCubit();
    addTearDown(chatCubit.close);
    final (registry, surfaceId) = _shellRegistry();
    addTearDown(registry.disposeAll);

    await tester.pumpWidget(
      _wrap(
        chatCubit: chatCubit,
        registry: registry,
        child: _shellChip(surfaceId),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byType(WorkspaceShellTabChip),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Rename terminal'), findsOneWidget);
    expect(find.text('Rename conversation'), findsNothing);
    await tester.tap(find.text('Rename terminal'));
    await tester.pumpAndSettle();

    // Dialog opens pre-filled with the pane label, not the display title.
    expect(find.text('Rename Terminal'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Local'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Build server  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final group = registry.groupOf('ws1');
    expect(group!.surfaceById(surfaceId)!.name, 'Build server');
    // Live repaint: the chip follows the group without a cubit change.
    expect(find.text('Build server'), findsOneWidget);
  });

  testWidgets('double-tapping a shell tab opens the rename dialog', (
    tester,
  ) async {
    final chatCubit = seededCubit();
    addTearDown(chatCubit.close);
    final (registry, surfaceId) = _shellRegistry();
    addTearDown(registry.disposeAll);

    await tester.pumpWidget(
      _wrap(
        chatCubit: chatCubit,
        registry: registry,
        child: _shellChip(surfaceId),
      ),
    );
    await tester.pump();

    final chip = find.byType(WorkspaceShellTabChip);
    await tester.tap(chip);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(find.text('Rename Terminal'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Deploy');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(registry.groupOf('ws1')!.surfaceById(surfaceId)!.name, 'Deploy');
  });

  testWidgets('blank shell rename is discarded', (tester) async {
    final chatCubit = seededCubit();
    addTearDown(chatCubit.close);
    final (registry, surfaceId) = _shellRegistry();
    addTearDown(registry.disposeAll);

    await tester.pumpWidget(
      _wrap(
        chatCubit: chatCubit,
        registry: registry,
        child: _shellChip(surfaceId),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byType(WorkspaceShellTabChip),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename terminal'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(registry.groupOf('ws1')!.surfaceById(surfaceId)!.name, '');
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
    expect(find.text('Rename terminal'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });
}
