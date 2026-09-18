import 'dart:async';
import 'dart:convert';

import '../editor/file_editor_theme.dart';
import '../io/filesystem.dart';
import '../quick_open/quick_open_index.dart';
import 'search_glob.dart';
import 'search_query.dart';
import 'search_result_models.dart';
import 'ripgrep_search_engine.dart'
    show
        SearchRunHandle,
        buildSearchMatch,
        searchDisplayPathFor;

/// Built-in scanner used when ripgrep is unavailable on a plane: enumerates
/// candidates via the (gitignore-aware) quick-open index, reads files in
/// batches, and scans them on the main isolate. Batches await between
/// chunks so the UI stays responsive; [SearchRunHandle.cancel] stops early.
class BuiltinSearchEngine {
  BuiltinSearchEngine({required this.indexRegistry});

  final QuickOpenIndexRegistry indexRegistry;

  /// Read-batch size for `FsBatchOps.statAndReadBytesMany` (WSL/SFTP round
  /// trips amortize at this granularity).
  static const int _batchSize = 64;

  /// Per-file read parallelism for planes without batch ops.
  static const int _readParallelism = 4;

  SearchRunHandle search({
    required SearchQuery query,
    required RegExp pattern,
    required String targetId,
    required Filesystem fs,
    required List<String> roots,
    String? primaryTargetId,
  }) {
    final completer = Completer<SearchResults>();
    var cancelled = false;

    unawaited(() async {
      final state = _ScanState();

      // Candidates from the shared index — one entry point per root.
      final candidates = <_Candidate>[];
      try {
        for (final root in roots) {
          if (cancelled) break;
          final index = await indexRegistry.load(fs, root);
          if (cancelled) break;
          for (final entry in index.files) {
            if (_accepts(query, entry)) {
              candidates.add(_Candidate(entry: entry));
            }
          }
        }
      } on Object {
        // Enumeration failure — search what we have (possibly nothing).
      }

      final FsBatchOps? batchFs = fs is FsBatchOps ? fs as FsBatchOps : null;
      for (var i = 0;
          i < candidates.length && !cancelled && !state.reachedTotalCap;
          i += _batchSize) {
        final batch = candidates.skip(i).take(_batchSize).toList();
        Map<String, FsStatAndBytes?>? stats;
        if (batchFs != null) {
          try {
            stats = await batchFs.statAndReadBytesMany(
              [for (final c in batch) c.entry.path],
              maxBytesPerFile: kSearchMaxFileBytes,
            );
          } on Object {
            stats = null; // Fall through to per-file reads below.
          }
        }
        if (cancelled) break;
        if (stats != null) {
          for (final candidate in batch) {
            if (state.stopped) break;
            state.scan(
              _scanBytes(
                pattern,
                targetId,
                fs,
                roots,
                candidate,
                stats[candidate.entry.path]?.bytes,
                primaryTargetId: primaryTargetId,
              ),
            );
          }
          continue;
        }
        // No batch ops (or the batch round trip failed) — per-file reads
        // with bounded parallelism.
        for (var j = 0; j < batch.length && !state.stopped; j += _readParallelism) {
          final group = batch.skip(j).take(_readParallelism).toList();
          final reads = await Future.wait(
            group.map((candidate) async {
              List<int>? bytes;
              try {
                bytes = await fs.readBytes(candidate.entry.path);
              } on Object {
                bytes = null;
              }
              if (bytes != null && bytes.length > kSearchMaxFileBytes) {
                return null; // Oversize.
              }
              return _scanBytes(
                pattern,
                targetId,
                fs,
                roots,
                candidate,
                bytes,
                primaryTargetId: primaryTargetId,
              );
            }),
          );
          for (final hit in reads) {
            if (state.stopped) break;
            state.scan(hit);
          }
        }
      }

      if (completer.isCompleted) return;
      completer.complete(
        SearchResults(
          files: state.files,
          totalMatches: state.total,
          truncated: state.truncated || cancelled,
          engine: SearchEngineKind.builtin,
        ),
      );
    }());

    return SearchRunHandle(
      results: completer.future,
      cancel: () => cancelled = true,
    );
  }

  /// Scans one file's bytes into a [SearchFileResult], or null when the file
  /// yields no match / was skipped (missing, oversize, binary).
  SearchFileResult? _scanBytes(
    RegExp pattern,
    String targetId,
    Filesystem fs,
    List<String> roots,
    _Candidate candidate,
    List<int>? bytes, {
    String? primaryTargetId,
  }) {
    if (bytes == null) return null; // Deleted since listing, or read failed.
    if (isKnownBinaryFilePath(candidate.entry.path) || bytesSeemBinary(bytes)) {
      return null;
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    var file = SearchFileResult(
      targetId: targetId,
      absolutePath: candidate.entry.path,
      displayPath: searchDisplayPathFor(
        candidate.entry.path,
        roots,
        fs.pathContext,
        targetId: targetId,
        primaryTargetId: primaryTargetId,
      ),
      matches: const [],
    );
    var lineNo = 0;
    var start = 0;
    while (start <= text.length) {
      var end = text.indexOf('\n', start);
      if (end < 0) end = text.length;
      lineNo++;
      final line = text.substring(start, end).replaceAll('\r', '');
      final spans = <SearchMatchSpan>[];
      for (final match in pattern.allMatches(line)) {
        spans.add(SearchMatchSpan(start: match.start, end: match.end));
      }
      if (spans.isNotEmpty && file.matches.length < kSearchMaxMatchesPerFile) {
        file = file.withMatches([
          ...file.matches,
          buildSearchMatch(lineNo, line, spans),
        ]);
      }
      if (end >= text.length) break;
      start = end + 1;
    }
    if (file.matches.isEmpty) return null;
    return file;
  }
}

class _Candidate {
  const _Candidate({required this.entry});

  final QuickOpenFileEntry entry;
}

/// Mutable scan accumulator (files, totals, caps).
class _ScanState {
  final files = <SearchFileResult>[];
  var total = 0;
  var truncated = false;

  bool get reachedTotalCap => total >= kSearchMaxMatchesTotal;
  bool get stopped => reachedTotalCap;

  void scan(SearchFileResult? hit) {
    if (hit == null) return;
    files.add(hit);
    total += hit.matchCount;
    if (reachedTotalCap) truncated = true;
  }
}

/// Candidate filter: path filter + include/exclude globs (binary/size checks
/// happen at read time).
bool _accepts(SearchQuery query, QuickOpenFileEntry entry) {
  final include = SearchGlobSet(query.includeGlobs);
  if (!include.isEmpty && !include.matches(entry.relativePath)) {
    return false;
  }
  final exclude = SearchGlobSet(query.excludeGlobs);
  if (!exclude.isEmpty && exclude.matches(entry.relativePath)) return false;
  return true;
}
