import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/command_log_entry.dart';
import '../repositories/command_log_repository.dart';
import '../services/storage/app_storage.dart';
import '../services/terminal/command_log_sink.dart';

/// Days of history kept on disk. Not user-configurable yet — the settings row
/// lands with the rest of the terminal settings page.
const int commandLogRetentionDays = 30;

class CommandLogState extends Equatable {
  const CommandLogState({
    this.dates = const [],
    this.selectedDate,
    this.entries = const [],
    this.skippedLines = 0,
    this.workspaceFilter = '',
    this.surfaceFilter = '',
    this.paneFilter = '',
    this.query = '',
    this.isLoading = false,
  });

  /// Local dates with a log file, newest first.
  final List<DateTime> dates;
  final DateTime? selectedDate;

  /// All rows of [selectedDate], newest first, before filtering.
  final List<CommandLogEntry> entries;

  /// Unparseable lines in the selected day's file.
  final int skippedLines;

  /// Empty string means "all".
  final String workspaceFilter;
  final String surfaceFilter;
  final String paneFilter;
  final String query;

  final bool isLoading;

  bool get hasFilters =>
      workspaceFilter.isNotEmpty ||
      surfaceFilter.isNotEmpty ||
      paneFilter.isNotEmpty ||
      query.isNotEmpty;

  /// Rows matching the current filters, newest first.
  List<CommandLogEntry> get visible {
    final needle = query.trim().toLowerCase();
    return [
      for (final entry in entries)
        if (_matches(entry, needle)) entry,
    ];
  }

  bool _matches(CommandLogEntry entry, String needle) {
    if (workspaceFilter.isNotEmpty && entry.workspaceId != workspaceFilter) {
      return false;
    }
    if (surfaceFilter.isNotEmpty && entry.surfaceId != surfaceFilter) {
      return false;
    }
    if (paneFilter.isNotEmpty && entry.paneId != paneFilter) return false;
    if (needle.isEmpty) return true;
    return entry.command.toLowerCase().contains(needle) ||
        entry.workingDirectory.toLowerCase().contains(needle);
  }

  /// Filter options as `(id, label)`, in first-seen order.
  List<(String, String)> get workspaceOptions =>
      _options((e) => (e.workspaceId, e.workspaceLabel));
  List<(String, String)> get surfaceOptions =>
      _options((e) => (e.surfaceId, e.surfaceLabel));
  List<(String, String)> get paneOptions =>
      _options((e) => (e.paneId, e.paneLabel));

  List<(String, String)> _options(
    (String, String) Function(CommandLogEntry entry) pick,
  ) {
    final seen = <String, String>{};
    for (final entry in entries) {
      final (id, label) = pick(entry);
      if (id.isEmpty) continue;
      seen.putIfAbsent(id, () => label.isEmpty ? id : label);
    }
    return [for (final e in seen.entries) (e.key, e.value)];
  }

  CommandLogState copyWith({
    List<DateTime>? dates,
    DateTime? selectedDate,
    List<CommandLogEntry>? entries,
    int? skippedLines,
    String? workspaceFilter,
    String? surfaceFilter,
    String? paneFilter,
    String? query,
    bool? isLoading,
  }) => CommandLogState(
    dates: dates ?? this.dates,
    selectedDate: selectedDate ?? this.selectedDate,
    entries: entries ?? this.entries,
    skippedLines: skippedLines ?? this.skippedLines,
    workspaceFilter: workspaceFilter ?? this.workspaceFilter,
    surfaceFilter: surfaceFilter ?? this.surfaceFilter,
    paneFilter: paneFilter ?? this.paneFilter,
    query: query ?? this.query,
    isLoading: isLoading ?? this.isLoading,
  );

  @override
  List<Object?> get props => [
    dates,
    selectedDate,
    entries,
    skippedLines,
    workspaceFilter,
    surfaceFilter,
    paneFilter,
    query,
    isLoading,
  ];
}

/// Owns the on-disk command log: ingests finished commands from the terminal
/// panes and backs the command log window and the command history picker.
class CommandLogCubit extends Cubit<CommandLogState>
    implements CommandLogSink {
  CommandLogCubit({CommandLogRepository? repository, DateTime Function()? clock})
    : _repository =
          repository ??
          CommandLogRepository(
            fs: AppStorage.fs,
            rootPath: AppStorage.appDataRoot,
            clock: clock,
          ),
      _clock = clock ?? DateTime.now,
      super(const CommandLogState());

  final CommandLogRepository _repository;
  final DateTime Function() _clock;

  /// Serialises appends so two panes finishing at once cannot interleave a
  /// half-written JSONL line.
  Future<void> _writes = Future.value();

  /// Directory shown by "open log folder".
  String get directoryPath => _repository.directoryPath;

  /// Creates [directoryPath] and returns it, so revealing it in the file
  /// manager works before the first command is logged.
  Future<String> prepareDirectory() async {
    await _repository.ensureDirectory();
    return _repository.directoryPath;
  }

  /// Loads the available dates and one day of rows (today by default).
  Future<void> load({DateTime? date}) async {
    emit(state.copyWith(isLoading: true));
    final dates = await _repository.availableDates();
    final wanted = date ?? state.selectedDate ?? _today(dates);
    final day = await _repository.load(wanted);
    emit(
      state.copyWith(
        dates: dates,
        selectedDate: day.date,
        entries: day.entries,
        skippedLines: day.skippedLines,
        isLoading: false,
      ),
    );
  }

  Future<void> selectDate(DateTime date) => load(date: date);

  /// Distinct recent commands for the command history picker, newest first.
  /// Reads straight from disk (not the in-memory day) so it spans every day and
  /// stays correct regardless of which day the log window last loaded.
  Future<List<String>> recentCommands({String? paneId}) =>
      _repository.recentCommands(paneId: paneId);

  void setWorkspaceFilter(String workspaceId) =>
      emit(state.copyWith(workspaceFilter: workspaceId));

  void setSurfaceFilter(String surfaceId) =>
      emit(state.copyWith(surfaceFilter: surfaceId));

  void setPaneFilter(String paneId) => emit(state.copyWith(paneFilter: paneId));

  void setQuery(String query) => emit(state.copyWith(query: query));

  void clearFilters() => emit(
    state.copyWith(
      workspaceFilter: '',
      surfaceFilter: '',
      paneFilter: '',
      query: '',
    ),
  );

  /// [CommandLogSink]: a pane finished a command.
  @override
  void record(CommandLogEntry entry) {
    unawaited(recordAndWait(entry));
  }

  /// Awaitable [record], for tests and for callers that need the row on disk.
  Future<void> recordAndWait(CommandLogEntry entry) {
    final queued = _writes.then((_) => _repository.append(entry));
    _writes = queued.catchError((_) {});
    return queued.then((_) {
      if (isClosed) return;
      final day = state.selectedDate;
      // Only the day currently on screen needs a live row; other days are read
      // from disk when selected.
      if (day == null || !_sameDay(day, entry.startedAt.toLocal())) return;
      emit(state.copyWith(entries: [entry, ...state.entries]));
    });
  }

  /// Drops day files past the retention window. Returns how many were deleted.
  Future<int> applyRetention({int days = commandLogRetentionDays}) async {
    final removed = await _repository.applyRetention(days);
    if (removed.isEmpty || isClosed) return removed.length;
    final kept = [
      for (final date in state.dates)
        if (!removed.any((r) => _sameDay(r, date))) date,
    ];
    emit(state.copyWith(dates: kept));
    return removed.length;
  }

  DateTime _today(List<DateTime> dates) {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    if (dates.any((d) => _sameDay(d, today))) return today;
    return dates.isEmpty ? today : dates.first;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
