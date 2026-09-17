import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/widgets/right_tools/right_tools_tool_preferences.dart';
import 'package:teampilot/widgets/right_tools/right_tools_tool_views.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/test_runtime_context.dart';

class _MutableLister implements WorktreeLister {
  _MutableLister(this.worktrees);

  List<GitWorktree> worktrees;

  @override
  Future<List<GitWorktree>> list(String repoPath) async => worktrees;
}

GitWorktree _wt(String path, String branch) => GitWorktree(
  path: path,
  branch: branch,
  head: 'h',
  isBare: false,
  isMainWorktree: path == '/repo',
);

/// Both tool tabs hidden → the tabbed panel collapses to nothing, leaving the
/// worktree branch bar as the only meaningful content under test.
Widget _host(WorktreeCubit cubit) {
  final theme = ThemeData(useMaterial3: true);
  return TpTheme(
    data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: theme,
      home: Scaffold(
        body: BlocProvider<WorktreeCubit>.value(
          value: cubit,
          child: RightToolsToolViews(
            preferences: const RightToolsToolPreferences(
              fileTreeVisible: false,
              gitVisible: false,
              searchVisible: false,
            ),
            cwd: '/repo',
            workspaceId: 'w1',
            toolsScopeId: 'w1',
            dismissDrawerOnAction: false,
            fileTreeCubit: FileTreeCubit(fs: InMemoryFilesystem()),
            workContext: testRuntimeContext('/repo'),
            scope: const WorkspaceToolsScopeState(resolving: false),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('branch label follows a disk-side branch switch', (tester) async {
    final lister = _MutableLister([
      _wt('/repo', 'refs/heads/main'),
      _wt('/wt/a', 'refs/heads/dev'),
    ]);
    final cubit = WorktreeCubit(lister: lister);
    await cubit.load('/repo');

    await tester.pumpWidget(_host(cubit));
    await tester.pump();
    expect(find.text('main'), findsOneWidget);

    // `git checkout` in the terminal → forced re-list → the label repaints.
    lister.worktrees = [
      _wt('/repo', 'refs/heads/feature'),
      _wt('/wt/a', 'refs/heads/dev'),
    ];
    await cubit.refresh();
    // First pump delivers the state to the BlocBuilder, second paints it.
    await tester.pump();
    await tester.pump();

    expect(find.text('feature'), findsOneWidget);
    expect(find.text('main'), findsNothing);
    await cubit.close();
  });

  testWidgets('branch label is hidden for a single-worktree repo', (tester) async {
    final lister = _MutableLister([_wt('/repo', 'refs/heads/main')]);
    final cubit = WorktreeCubit(lister: lister);
    await cubit.load('/repo');

    await tester.pumpWidget(_host(cubit));
    await tester.pump();
    expect(find.text('main'), findsNothing);
    await cubit.close();
  });
}
