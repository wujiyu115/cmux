import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/search_cubit.dart';
import 'package:teampilot/services/quick_open/quick_open_index.dart';
import 'package:teampilot/services/search/ripgrep_search_engine.dart';
import 'package:teampilot/services/search/search_query.dart';
import 'package:teampilot/services/search/search_result_rows.dart';
import 'package:teampilot/services/search/search_result_models.dart';
import 'package:teampilot/services/search/workspace_search_service.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';

import '../support/test_runtime_context.dart';

/// [WorkspaceSearchService] stand-in returning a canned result.
class _FakeService extends WorkspaceSearchService {
  _FakeService() : super(indexRegistry: QuickOpenIndexRegistry());

  int callCount = 0;
  SearchQuery? lastQuery;
  List<SearchRunHandle> cancelled = [];

  @override
  SearchRunHandle search({
    required WorkspaceToolsScopeState scope,
    required SearchQuery query,
    required RegExp pattern,
  }) {
    callCount++;
    lastQuery = query;
    final run = SearchRunHandle(
      results: Future.value(_resultsFor(query)),
      cancel: () {},
    );
    return run;
  }

  SearchResults _resultsFor(SearchQuery query) => SearchResults(
    totalMatches: 1,
    truncated: false,
    engine: SearchEngineKind.builtin,
    files: [
      SearchFileResult(
        targetId: 'local',
        absolutePath: '/repo/${query.text}.dart',
        displayPath: 'lib/${query.text}.dart',
        matches: const [
          SearchMatch(
            lineNo: 2,
            snippet: 'hit',
            spans: [SearchMatchSpan(start: 0, end: 3)],
          ),
        ],
      ),
    ],
  );
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

void main() {
  test('empty query stays idle and never runs', () async {
    final service = _FakeService();
    final cubit = SearchCubit(service: service)..scopeResolver = _readyScope;

    cubit.setQuery('');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(cubit.state.status, SearchStatus.idle);
    expect(service.callCount, 0);
    await cubit.close();
  });

  test('debounced query runs and publishes results', () async {
    final service = _FakeService();
    final cubit = SearchCubit(service: service)..scopeResolver = _readyScope;

    cubit.setQuery('foo');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(cubit.state.status, SearchStatus.done);
    expect(service.callCount, 1);
    expect(cubit.state.results?.files.single.displayPath, 'lib/foo.dart');
    await cubit.close();
  });

  test('invalid regex reports pattern error without running', () async {
    final service = _FakeService();
    final cubit = SearchCubit(service: service)..scopeResolver = _readyScope;

    cubit.toggleUseRegex();
    cubit.setQuery('[unclosed');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(cubit.state.status, SearchStatus.invalidPattern);
    expect(cubit.state.patternError, '[unclosed');
    expect(service.callCount, 0);
    await cubit.close();
  });

  test('toggles update the query', () async {
    final service = _FakeService();
    final cubit = SearchCubit(service: service)..scopeResolver = _readyScope;

    cubit.toggleCaseSensitive();
    cubit.toggleWholeWord();
    cubit.toggleUseRegex();
    cubit.setIncludeGlobs('*.dart');
    cubit.setExcludeGlobs('build/**');

    expect(
      cubit.state.query,
      const SearchQuery(
        text: '',
        caseSensitive: true,
        wholeWord: true,
        useRegex: true,
        includeGlobs: '*.dart',
        excludeGlobs: 'build/**',
      ),
    );
    await cubit.close();
  });

  test('close disposes the focus node without throwing', () async {
    final cubit = SearchCubit(service: _FakeService());
    final node = cubit.queryFocusNode;
    await cubit.close();
    // A disposed node throws on debug checks; keep this light — dispose ran.
    expect(node.debugLabel, 'search-query');
  });
  test('cancel stops the running search and keeps partial results', () async {
    final completer = Completer<SearchResults>();
    var cancelled = false;
    final service = _CancellableFakeService(completer, () => cancelled = true);
    final cubit = SearchCubit(service: service)..scopeResolver = _readyScope;

    cubit.setQuery('foo');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(cubit.state.status, SearchStatus.running);

    cubit.cancel();
    expect(cancelled, isTrue);
    expect(cubit.state.status, SearchStatus.running); // Not done yet.

    completer.complete(
      SearchResults(
        totalMatches: 0,
        truncated: true,
        engine: SearchEngineKind.ripgrep,
        files: const [],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cubit.state.status, SearchStatus.done);
    expect(cubit.state.results?.truncated, isTrue);
    await cubit.close();
  });
  test('file collapse toggles per file and collapses/expands all', () async {
    final cubit = SearchCubit(service: _FakeService())
      ..scopeResolver = _readyScope;

    cubit.setQuery('foo');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(cubit.state.status, SearchStatus.done);
    final results = cubit.state.results!;
    expect(results.files, hasLength(1));

    // Per-file toggle: match rows disappear from `rows`, header stays.
    final path = results.files.single.absolutePath;
    cubit.toggleFileCollapse(path);
    expect(cubit.state.collapsedFiles, {path});
    expect(
      cubit.state.rows.whereType<SearchMatchRow>(),
      isEmpty,
    );
    cubit.toggleFileCollapse(path);
    expect(cubit.state.collapsedFiles, isEmpty);
    expect(
      cubit.state.rows.whereType<SearchMatchRow>(),
      hasLength(1),
    );

    // Collapse-all then expand-all.
    cubit.toggleAllFilesCollapse();
    expect(cubit.state.collapsedFiles, {path});
    cubit.toggleAllFilesCollapse();
    expect(cubit.state.collapsedFiles, isEmpty);

    // A new query resets the collapse state.
    cubit.toggleFileCollapse(path);
    cubit.setQuery('bar');
    expect(cubit.state.collapsedFiles, isEmpty);
    await cubit.close();
  });
}

/// [WorkspaceSearchService] stand-in whose run only finishes when the test
/// completes it, mirroring a live in-flight search.
class _CancellableFakeService extends WorkspaceSearchService {
  _CancellableFakeService(this._completer, this._onCancel)
    : super(indexRegistry: QuickOpenIndexRegistry());

  final Completer<SearchResults> _completer;
  final void Function() _onCancel;

  @override
  SearchRunHandle search({
    required WorkspaceToolsScopeState scope,
    required SearchQuery query,
    required RegExp pattern,
  }) {
    return SearchRunHandle(results: _completer.future, cancel: _onCancel);
  }
}
