import 'dart:convert';

import '../models/command_log_entry.dart';
import '../services/io/filesystem.dart';
import '../services/terminal/command_secret_redactor.dart';

/// One day's worth of command log rows, plus how many lines were unreadable.
class CommandLogDay {
  const CommandLogDay({
    required this.date,
    required this.entries,
    this.skippedLines = 0,
  });

  /// Local calendar date the file covers.
  final DateTime date;

  /// Newest first.
  final List<CommandLogEntry> entries;

  /// Lines that failed to parse. Reported so a corrupt tail is visible in the UI
  /// instead of silently shortening the list.
  final int skippedLines;
}

/// Append-only daily JSONL log of shell commands.
///
/// `<appDataRoot>/logs/commands/{yyyy-MM-dd}.jsonl`, one entry per line, keyed by
/// the *local* date the command started. Bad lines are skipped and counted on
/// read; the file itself is never rewritten or truncated, so a partially written
/// tail can never cost the rest of the day's history. Retention deletes whole
/// day files only.
class CommandLogRepository {
  CommandLogRepository({
    required Filesystem fs,
    required String rootPath,
    DateTime Function()? clock,
  }) : _fs = fs,
       _rootPath = rootPath,
       _clock = clock ?? DateTime.now;

  final Filesystem _fs;
  final String _rootPath;
  final DateTime Function() _clock;

  static const String _extension = '.jsonl';

  /// Rows kept per day file; a runaway loop must not grow one file unbounded.
  static const int maxEntriesPerDay = 20000;

  /// Directory the day files live in (not created until first use).
  String get directoryPath =>
      _fs.pathContext.join(_rootPath, 'logs', 'commands');

  String fileFor(DateTime date) =>
      _fs.pathContext.join(directoryPath, '${formatLogDate(date)}$_extension');

  /// Creates the log directory, so "open log folder" always lands somewhere
  /// even before the first command has been recorded.
  Future<void> ensureDirectory() => _fs.ensureDir(directoryPath);

  /// Appends one finished row. Silently drops entries whose command redacts away.
  Future<void> append(CommandLogEntry entry) async {
    final command = CommandSecretRedactor.sanitize(entry.command);
    if (command == null) return;
    final path = fileFor(entry.startedAt.toLocal());
    await _fs.ensureDir(directoryPath);
    final line = jsonEncode(entry.copyWith(command: command).toJson());
    await _fs.appendString(path, '$line\n');
  }

  /// Local dates that have a log file, newest first.
  Future<List<DateTime>> availableDates() async {
    final stat = await _fs.stat(directoryPath);
    if (!stat.exists) return const [];
    final dates = <DateTime>[];
    for (final entry in await _fs.listDir(directoryPath)) {
      if (entry.isDirectory || !entry.name.endsWith(_extension)) continue;
      final stem = entry.name.substring(
        0,
        entry.name.length - _extension.length,
      );
      final date = parseLogDate(stem);
      if (date != null) dates.add(date);
    }
    dates.sort((a, b) => b.compareTo(a));
    return dates;
  }

  /// Reads one day, newest first. Missing file → empty day, not an error.
  Future<CommandLogDay> load(DateTime date) async {
    final raw = await _fs.readString(fileFor(date));
    if (raw == null) {
      return CommandLogDay(date: _dayOf(date), entries: const []);
    }
    final entries = <CommandLogEntry>[];
    var skipped = 0;
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) continue;
      final entry = _decodeLine(line);
      if (entry == null) {
        skipped++;
        continue;
      }
      entries.add(entry);
    }
    entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return CommandLogDay(
      date: _dayOf(date),
      entries: entries.length > maxEntriesPerDay
          ? entries.sublist(0, maxEntriesPerDay)
          : entries,
      skippedLines: skipped,
    );
  }

  /// Deletes day files older than [retentionDays] (0 or negative keeps
  /// everything). Returns the deleted dates.
  Future<List<DateTime>> applyRetention(int retentionDays) async {
    if (retentionDays <= 0) return const [];
    final today = _dayOf(_clock());
    final cutoff = today.subtract(Duration(days: retentionDays - 1));
    final removed = <DateTime>[];
    for (final date in await availableDates()) {
      if (!date.isBefore(cutoff)) continue;
      await _fs.removeRecursive(fileFor(date));
      removed.add(date);
    }
    return removed;
  }

  CommandLogEntry? _decodeLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return null;
      final entry = CommandLogEntry.fromJson(decoded);
      if (entry == null) return null;
      // Defence in depth: a file written by an older build (or another app) may
      // still hold a secret the current redactor would catch.
      final command = CommandSecretRedactor.sanitize(entry.command);
      if (command == null) return null;
      return entry.copyWith(command: command);
    } catch (_) {
      return null;
    }
  }

  static DateTime _dayOf(DateTime value) {
    final local = value.isUtc ? value.toLocal() : value;
    return DateTime(local.year, local.month, local.day);
  }
}

/// `yyyy-MM-dd`, the day-file stem.
String formatLogDate(DateTime date) {
  final local = date.isUtc ? date.toLocal() : date;
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-$month-$day';
}

/// Inverse of [formatLogDate]; null when [stem] is not a plain date.
DateTime? parseLogDate(String stem) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(stem);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.month != month || date.day != day) return null;
  return date;
}
