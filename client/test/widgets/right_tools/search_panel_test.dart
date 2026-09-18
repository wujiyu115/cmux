import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/search_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';
import 'package:teampilot/services/quick_open/quick_open_index.dart';
import 'package:teampilot/services/search/ripgrep_search_engine.dart';
import 'package:teampilot/services/search/search_query.dart';
import 'package:teampilot/services/search/search_result_models.dart';
import 'package:teampilot/services/search/workspace_search_service.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/widgets/right_tools/right_tools_lifecycle.dart';

import 'package:teampilot/widgets/right_tools/search_panel.dart';
import 'package:teampilot/models/layout_preferences.dart';

import '../../support/test_runtime_context.dart';

/// [WorkspaceSearchService] stand-in returning a fixed two-file result so the
/// panel renders the full results tree deterministically.
class _TwoFileService extends WorkspaceSearchService {
  _TwoFileService() : super(indexRegistry: QuickOpenIndexRegistry());

  @override
  SearchRunHandle search({
    required WorkspaceToolsScopeState scope,
    required SearchQuery query,
    required RegExp pattern,
  }) {
    return SearchRunHandle(
      results: Future.value(_results),
      cancel: () {},
    );
  }
}

final SearchResults _results = SearchResults(
  totalMatches: 3,
  truncated: false,
  engine: SearchEngineKind.ripgrep,
  files: const [
    SearchFileResult(
      targetId: 'local',
      absolutePath: '/repo/service/home/helper/home_pet_helper.lua',
      displayPath: 'service/home/helper/home_pet_helper.lua',
      matches: [
        SearchMatch(
          lineNo: 4,
          snippet: "log('home_pet marry')",
          spans: [SearchMatchSpan(start: 5, end: 13)],
        ),
        SearchMatch(
          lineNo: 9,
          snippet: "log('home_pet divorce')",
          spans: [SearchMatchSpan(start: 5, end: 13)],
        ),
      ],
    ),
    SearchFileResult(
      targetId: 'local',
      absolutePath: '/repo/lualib/const.lua',
      displayPath: 'lualib/const.lua',
      matches: [
        SearchMatch(
          lineNo: 2,
          snippet: 'M.GIFT_PET = "home_pet_back"',
          spans: [SearchMatchSpan(start: 15, end: 23)],

        ),
      ],
    ),
  ],
);
/// Stand-in that mirrors the built-in fallback: empty results tagged with
/// [SearchEngineKind.builtin] (ripgrep unavailable on the plane).
class _BuiltinEmptyService extends WorkspaceSearchService {
  _BuiltinEmptyService() : super(indexRegistry: QuickOpenIndexRegistry());

  @override
  SearchRunHandle search({
    required WorkspaceToolsScopeState scope,
    required SearchQuery query,
    required RegExp pattern,
  }) {
    return SearchRunHandle(
      results: Future.value(
        const SearchResults.empty(engine: SearchEngineKind.builtin),
      ),
      cancel: () {},
    );
  }
}

WorkspaceToolsScopeState _readyScope() => WorkspaceToolsScopeState(
  tools: WorkspaceToolsContext(
    targetId: 'local',
    context: testRuntimeContext('/repo'),
  ),
  roots: const ['/repo'],
  targetSlices: [
    WorkspaceTargetSlice(
      targetId: 'local',
      tools: WorkspaceToolsContext(
        targetId: 'local',
        context: testRuntimeContext('/repo'),
      ),
      roots: const ['/repo'],
    ),
  ],
  resolving: false,
);
Widget _host(SearchCubit cubit) {
  final theme = ThemeData(useMaterial3: true);
  final scope = _readyScope();
  return TpTheme(
    data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: theme,
      home: Scaffold(
        body: RightToolsLifecycle(
          data: RightToolsLifecycleData(
            scope: scope,
            fileTreeCubit: null,
            pokeOnTurnEnd: () {},
            ensureFileTreeReady: () {},
          ),
          child: Provider<WorkbenchEditorOpener>(
            create: (_) => WorkbenchEditorOpener(
              editor: EditorCubit(),
              workbench: WorkbenchCubit(),
              readMarkdownOpenMode: () => MarkdownOpenMode.remember,
              markdownViewModes: MarkdownViewModeStore(),
              readEditorPreviewTabs: () => false,
            ),
            child: BlocProvider<SearchCubit>.value(
              value: cubit,
              child: SearchPanel(cubit: cubit, workspaceId: 'w1'),
            ),
          ),
        ),
      ),
    ),
  );
}
void main() {
  testWidgets('VS Code layout: toggles in query field, summary row, tree', (
    tester,
  ) async {
    final cubit = SearchCubit(service: _TwoFileService())
      ..scopeResolver = _readyScope;

    await tester.pumpWidget(_host(cubit));
    await tester.enterText(find.byType(TextField).first, 'home_pet');
    await tester.pumpAndSettle();

    // Toggles live inside the query field's suffix, not in a separate row.
    final queryField = find.widgetWithText(TextField, 'home_pet');
    expect(queryField, findsOneWidget);
    expect(
      find.descendant(
        of: queryField,
        matching: find.byType(Tooltip),
      ),
      findsNWidgets(3),
    );

    // Summary row: "3 results in 2 files" (en locale).
    expect(find.text('3 results in 2 files'), findsOneWidget);

    // Two file headers: name semibold + dim dir; three match lines.
    expect(find.text('home_pet_helper.lua'), findsOneWidget);
    expect(find.text('service/home/helper'), findsOneWidget);
    expect(find.text('const.lua'), findsOneWidget);
    expect(find.text('lualib'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNWidgets(2));

    await cubit.close();
  });

  testWidgets('builtin engine notice shows even with zero results', (
    tester,
  ) async {
    final cubit = SearchCubit(service: _BuiltinEmptyService())
      ..scopeResolver = _readyScope;

    await tester.pumpWidget(_host(cubit));
    await tester.enterText(find.byType(TextField).first, 'nomatch');
    await tester.pumpAndSettle();

    // Zero results AND the no-ripgrep notice, both visible.
    expect(find.text('No results'), findsOneWidget);
    expect(
      find.text('ripgrep not found — using the built-in scan (slower)'),
      findsOneWidget,
    );
    await cubit.close();
  });

  testWidgets('tapping a file header collapses its match rows', (
    tester,
  ) async {
    final cubit = SearchCubit(service: _TwoFileService())
      ..scopeResolver = _readyScope;

    await tester.pumpWidget(_host(cubit));
    await tester.enterText(find.byType(TextField).first, 'home_pet');
    await tester.pumpAndSettle();
    expect(find.text("log('home_pet marry')"), findsOneWidget);

    // Tap the file header (row area, not the name link) — match rows fold.
    await tester.tap(find.byIcon(Icons.expand_more).first);
    await tester.pumpAndSettle();
    expect(cubit.state.collapsedFiles, {
      '/repo/service/home/helper/home_pet_helper.lua',
    });
    expect(find.text("log('home_pet marry')"), findsNothing);
    expect(find.text('M.GIFT_PET = "home_pet_back"'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await cubit.close();
  });
}
