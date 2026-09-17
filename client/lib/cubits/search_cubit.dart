import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/search/ripgrep_search_engine.dart';
import '../services/search/search_query.dart';
import '../services/search/search_result_models.dart';
import '../services/search/search_result_rows.dart';
import '../services/search/workspace_search_service.dart';
import '../services/workspace/workspace_tools_scope.dart';
import '../utils/debounce/debounces.dart';

enum SearchStatus { idle, invalidPattern, running, done }

/// State for one workspace's search panel.
class SearchState extends Equatable {
  const SearchState({
    this.query = const SearchQuery(),
    this.status = SearchStatus.idle,
    this.results,
    this.patternError,
  });

  final SearchQuery query;
  final SearchStatus status;

  /// Null until a search finished (or was cancelled into a new run).
  final SearchResults? results;

  /// Non-null when [query] is a regex that failed to compile.
  final String? patternError;

  SearchState copyWith({
    SearchQuery? query,
    SearchStatus? status,
    SearchResults? results,
    bool clearResults = false,
    String? patternError,
    bool clearPatternError = false,
  }) => SearchState(
    query: query ?? this.query,
    status: status ?? this.status,
    results: clearResults ? null : (results ?? this.results),
    patternError: clearPatternError
        ? null
        : (patternError ?? this.patternError),
  );

  /// Flat rows for the results list (null while no results).
  List<SearchRow> get rows => results == null ? const [] : buildSearchRows(results!);

  @override
  List<Object?> get props => [query, status, results, patternError];
}

/// Per-workspace search controller. One instance per open workspace
/// (retained by [WorkspaceSearchStore] so state survives tab switches);
/// nothing persists to disk in v1.
class SearchCubit extends Cubit<SearchState> {
  SearchCubit({required WorkspaceSearchService service})
    : _service = service,
      super(const SearchState());

  static const _debounceKey = 'search_in_files';
  static const _debounceDuration = Duration(milliseconds: 200);

  final WorkspaceSearchService _service;

  /// Focus target for the Ctrl+Shift+F command (the lazy-mounted panel
  /// grabs it via the store).
  final FocusNode queryFocusNode = FocusNode(debugLabel: 'search-query');

  /// Supplies the current tools scope per run (the panel rebinds it on
  /// scope changes; null while the panel is unmounted).
  WorkspaceToolsScopeState? Function()? scopeResolver;

  SearchRunHandle? _activeRun;
  int _generation = 0;

  void setQuery(String text) => _updateQuery(state.query.copyWith(text: text));
  void setPathFilter(String value) =>
      _updateQuery(state.query.copyWith(pathFilter: value));
  void toggleCaseSensitive() =>
      _updateQuery(state.query.copyWith(caseSensitive: !state.query.caseSensitive));
  void toggleWholeWord() =>
      _updateQuery(state.query.copyWith(wholeWord: !state.query.wholeWord));
  void toggleUseRegex() =>
      _updateQuery(state.query.copyWith(useRegex: !state.query.useRegex));
  void setIncludeGlobs(String value) =>
      _updateQuery(state.query.copyWith(includeGlobs: value));
  void setExcludeGlobs(String value) =>
      _updateQuery(state.query.copyWith(excludeGlobs: value));

  void _updateQuery(SearchQuery query) {
    if (query == state.query) return;
    emit(state.copyWith(query: query, clearResults: true));
    if (query.isEmpty) {
      Debounces.debounce(_debounceKey, Duration.zero, () {
        if (state.query.isEmpty) _setIdle();
      });
      return;
    }
    Debounces.debounce(_debounceKey, _debounceDuration, _runDebouncedSearch);
  }

  void _setIdle() {
    _activeRun?.cancel();
    _activeRun = null;
    emit(
      state.copyWith(
        status: SearchStatus.idle,
        clearResults: true,
        clearPatternError: true,
      ),
    );
  }

  void _runDebouncedSearch() {
    final query = state.query;
    if (query.isEmpty) return;
    final scope = scopeResolver?.call();
    if (scope == null || !scope.isReady) return;

    final (:pattern, :patternError) = query.compilePattern();
    if (pattern == null) {
      emit(
        state.copyWith(
          status: SearchStatus.invalidPattern,
          patternError: patternError,
          clearResults: true,
        ),
      );
      return;
    }

    _activeRun?.cancel();
    final generation = ++_generation;
    emit(state.copyWith(status: SearchStatus.running, clearPatternError: true));

    final run = _service.search(scope: scope, query: query, pattern: pattern);
    _activeRun = run;
    run.results.then((results) {
      if (isClosed || generation != _generation) return;
      _activeRun = null;
      emit(state.copyWith(status: SearchStatus.done, results: results));
    });
  }

  /// Re-runs the current query immediately (scope changed / manual retry).
  void rerun() {
    if (state.query.isEmpty) return;
    Debounces.debounce(_debounceKey, Duration.zero, _runDebouncedSearch);
  }

  @override
  Future<void> close() {
    _activeRun?.cancel();
    _activeRun = null;
    queryFocusNode.dispose();
    return super.close();
  }
}
