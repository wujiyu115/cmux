import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace_quick_open_scope_dialog.dart';
import 'package:teampilot/repositories/session_repository.dart';

void main() {
  testWidgets(
    'scope rules survive closing the dialog without a save action (e2e)',
    (tester) async {
      await tester.runAsync(() async {
        final tmp = await Directory.systemTemp.createTemp('scope_e2e_');
        addTearDown(() => tmp.deleteSync(recursive: true));

        final repo = SessionRepository(rootDir: tmp.path);
        final ws = await repo.createWorkspace([
          const WorkspaceFolder(path: '/proj'),
        ]);
        final chat = ChatCubit(executableResolver: () => 'flashskyai');
        addTearDown(chat.close);
        chat.ingestWorkspaceSessionSnapshot(
          workspaces: [ws],
          sessions: const [],
        );

        late BuildContext rowContext;
        // Providers wrap MaterialApp (as production main.dart does) so the
        // dialog — built in the root navigator's overlay — can read them.
        await tester.pumpWidget(
          MultiRepositoryProvider(
            providers: [
              RepositoryProvider<SessionRepository>.value(value: repo),
            ],
            child: BlocProvider<ChatCubit>.value(
              value: chat,
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: const Locale('en'),
                home: Scaffold(
                  body: Builder(
                    builder: (context) {
                      rowContext = context;
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        // Open the dialog through the production entry point.
        final closed = editWorkspaceQuickOpenScope(rowContext, ws);
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final field = find.widgetWithText(
          TextField,
          l10n.workspaceQuickOpenScopeAddPathHint,
        ).first;
        await tester.enterText(field, 'common');
        await tester.tap(find.byIcon(Icons.add_rounded).first);
        await tester.pump();
        expect(find.text('common'), findsWidgets);
        // Let the immediate persist reach disk before closing.
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Close via the header X — there is no save action to click, and none
        // is needed: the add already persisted.
        await tester.tap(find.byIcon(Icons.close_rounded).first);
        await tester.pumpAndSettle();
        await closed;

        // Cubit state must carry the rules...
        expect(
          chat.state.workspaces.single.indexDirRules.excluded,
          ['common'],
        );
        // ...and disk must too (fresh repository instance, like an app restart).
        final disk = await SessionRepository(rootDir: tmp.path).loadWorkspaces();
        expect(disk.single.indexDirRules.excluded, ['common']);
      });
    },
  );
}
