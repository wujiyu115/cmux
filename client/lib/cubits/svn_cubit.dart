import 'dart:async';

import '../models/git_blame.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/vcs/svn_service.dart';

class SvnState extends Equatable {
  const SvnState({
    this.repoRoot = '',
    this.svnAvailable = true,
    this.isLoading = false,
    this.busy = false,
    this.info,
    this.changes = const [],
    this.commitMessage = '',
    this.selectedPaths = const {},
    this.errorMessage,
  });

  final String repoRoot;
  final bool svnAvailable;
  final bool isLoading;
  final bool busy;

  /// `svn info` of the wc — url + revision for the group header.
  final SvnInfo? info;

  /// Non-external status rows (externals rows kept, unversioned included).
  final List<SvnFileChange> changes;

  final String commitMessage;

  /// Paths checked for the next commit (empty = commit nothing; svn has no
  /// staging area, so selection *is* the commit set).
  final Set<String> selectedPaths;

  final String? errorMessage;

  bool get isRepository => info != null;

  /// Rows shown in the changes list: externals rows are folded separately.
  List<SvnFileChange> get workRows =>
      changes.where((c) => !c.isExternalsRow).toList();

  List<SvnFileChange> get externalsRows =>
      changes.where((c) => c.isExternalsRow).toList();

  bool isDirty(String path) => changes.any((c) => c.path == path);

  SvnState copyWith({
    String? repoRoot,
    bool? svnAvailable,
    bool? isLoading,
    bool? busy,
    SvnInfo? info,
    bool clearInfo = false,
    List<SvnFileChange>? changes,
    String? commitMessage,
    Set<String>? selectedPaths,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SvnState(
      repoRoot: repoRoot ?? this.repoRoot,
      svnAvailable: svnAvailable ?? this.svnAvailable,
      isLoading: isLoading ?? this.isLoading,
      busy: busy ?? this.busy,
      info: clearInfo ? null : (info ?? this.info),
      changes: changes ?? this.changes,
      commitMessage: commitMessage ?? this.commitMessage,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
    repoRoot,
    svnAvailable,
    isLoading,
    busy,
    info,
    changes,
    commitMessage,
    selectedPaths,
    errorMessage,
  ];
}

/// Drives the svn group of the source control panel for one working copy.
///
/// Mirrors [GitCubit]: coalesced refresh (one `svn status`+`svn info` chain
/// at a time), busy-guarded mutations that refresh on success, error
/// surfaces through [SvnState.errorMessage]. Selection replaces staging:
/// the commit set is the checked rows.
class SvnCubit extends Cubit<SvnState> {
  SvnCubit({required SvnService service})
    : _service = service,
      super(const SvnState());

  final SvnService _service;

  /// In-memory blame cache, keyed by wc-relative path (mirrors GitCubit).
  final _blameCache = <String, List<GitBlameEntry>>{};
  bool _refreshInFlight = false;
  bool _refreshQueued = false;


  /// Sets (or replaces) the working-copy root and loads it.
  Future<void> setRepoRoot(String path) async {
    if (path == state.repoRoot) return;
    emit(state.copyWith(repoRoot: path, clearInfo: true, changes: const []));
    await refresh();
  }

  /// Refreshes svn info + status, coalescing concurrent calls.
  Future<void> refresh() async {
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }
    _refreshInFlight = true;
    try {
      await _runRefresh();
    } finally {
      _refreshInFlight = false;
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(refresh());
      }
    }
  }

  Future<void> _runRefresh() async {
    final dir = state.repoRoot;
    if (dir.isEmpty) return;
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final available = await _service.isAvailable;
      if (!available) {
        emit(
          state.copyWith(isLoading: false, svnAvailable: false, clearInfo: true),
        );
        return;
      }
      final info = await _service.info(dir);
      if (info == null) {
        emit(
          state.copyWith(isLoading: false, clearInfo: true, changes: const []),
        );
        return;
      }
      final changes = await _service.status(dir);
      if (isClosed) return;
      emit(
        state.copyWith(
          isLoading: false,
          svnAvailable: true,
          info: info,
          changes: changes,
        ),
      );
    } on SvnException catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: e.message,
        ),
      );
    }
  }

  void setCommitMessage(String message) {
    emit(state.copyWith(commitMessage: message));
  }

  void toggleSelected(String path) {
    final next = Set<String>.of(state.selectedPaths);
    next.contains(path) ? next.remove(path) : next.add(path);
    emit(state.copyWith(selectedPaths: next));
  }

  void selectAll() {
    emit(
      state.copyWith(
        selectedPaths: {
          for (final row in state.workRows)
            if (!row.isExternalsRow) row.path,
        },
      ),
    );
  }

  void clearSelection() {
    emit(state.copyWith(selectedPaths: const {}));
  }

  /// Commits the selected (or [paths]) rows with the current message.
  /// Returns false when the message is blank or nothing is selected.
  Future<bool> commit({List<String>? paths}) async {
    final message = state.commitMessage.trim();
    final targets = paths ?? state.selectedPaths.toList();
    if (message.isEmpty || targets.isEmpty || state.busy) return false;
    return _mutate(() async {
      await _service.commit(state.repoRoot, message, targets);
    });
  }

  Future<void> update() => _mutate(() => _service.update(state.repoRoot));

  Future<void> revert(List<String> paths) => _mutate(
    () => _service.revert(state.repoRoot, paths),
  );

  Future<void> addUnversioned(String path) =>
      _mutate(() => _service.add(state.repoRoot, [path]));

  /// Unified diff of [relativePath], or null on failure (matches
  /// [GitCubit.diff]'s contract for the diff surface).
  Future<String?> serviceDiff(String relativePath) async {
    try {
      return await _service.diff(state.repoRoot, relativePath);
    } on SvnException {
      return null;
    }
  }

  /// Full-file blame of [relativePath], cached like [GitCubit.serviceBlame]
  /// so caret moves never re-spawn svn. Returns null when the file has no
  /// blame (unversioned/binary).
  Future<List<GitBlameEntry>?> serviceBlame(String relativePath) async {
    final cached = _blameCache[relativePath];
    if (cached != null) return cached;
    final entries = await _service.blameFile(
          state.repoRoot,
          relativePath,
        ) ??
        const <GitBlameEntry>[];
    _blameCache[relativePath] = entries;
    return entries;
  }

  /// Runs [action], then refreshes. Returns false (and sets an error) on
  /// failure. Guards re-entrancy via [SvnState.busy].
  Future<bool> _mutate(Future<void> Function() action) async {
    if (state.busy) return false;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await action();
    } on SvnException catch (e) {
      emit(state.copyWith(busy: false, errorMessage: e.message));
      return false;
    }
    emit(state.copyWith(busy: false, selectedPaths: const {}));
    await refresh();
    return true;
  }
}

