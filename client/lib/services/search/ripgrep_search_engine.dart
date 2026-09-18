import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../run/process_run_executor.dart';
import 'search_query.dart';
import 'search_result_models.dart';

/// A running search the caller can await and cancel (kills the process).
class SearchRunHandle {
  SearchRunHandle({required this.results, required void Function() cancel})
    : _cancel = cancel;

  final Future<SearchResults> results;
  final void Function() _cancel;
  bool _cancelled = false;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}

/// Spawns a process on the search plane. Injected so tests can replay
/// canned `rg --json` output; production builds one per plane (local
/// `Process.start`, `wsl.exe`, SSH exec — see [SearchSliceSpawner]).
typedef SearchProcessSpawner =
    Future<ProcessRunHandle> Function({
      required String executable,
      required List<String> arguments,
      required String workingDirectory,
    });

/// Ripgrep-backed search: spawns `rg --json` and streams/parses its output
/// — the same architecture VS Code's built-in search uses (the scan runs in
/// rg's threads, never on the UI isolate; kill = cancel).
///
/// rg locates candidate lines (byte-precise); the caller's compiled
/// [RegExp] re-runs on each reported line to produce code-unit-accurate
/// snippet spans, so non-ASCII paths/lines highlight correctly.
class RipgrepSearchEngine {
  RipgrepSearchEngine({required this.spawner, this.executable = 'rg'});

  final SearchProcessSpawner spawner;
  final String executable;

  /// [pathContext] is the plane's context (windows vs posix) — used for
  /// root-relative display paths only.
  SearchRunHandle search({
    required SearchQuery query,
    required RegExp pattern,
    required String targetId,
    required p.Context pathContext,
    required List<String> roots,
    required String workingDirectory,
    String? primaryTargetId,
  }) {
    final completer = Completer<SearchResults>();
    ProcessRunHandle? process;
    var cancelled = false;

    final args = buildRipgrepArguments(query)..addAll(roots);

    unawaited(() async {
      process = await spawner(
        executable: executable,
        arguments: args,
        workingDirectory: workingDirectory,
      );
      final collector = _RipgrepCollector(
        query: query,
        pattern: pattern,
        targetId: targetId,
        pathContext: pathContext,
        roots: roots,
        primaryTargetId: primaryTargetId,
      );
      // Stream decode: line boundaries may fall between chunks, so pipe
      // through a decoder + line splitter instead of converting per chunk.
      final lines = process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());
      final stdoutSub = lines.listen(
        collector.consumeLine,
        onError: (Object _) {},
      );
      final stderrSub = process!.stderr.listen((_) {});
      try {
        await stdoutSub.asFuture<void>();
      } on Object {
        // Stream errors (process killed) surface here — results so far win.
      }
      await stdoutSub.cancel();
      await stderrSub.cancel();
      if (!completer.isCompleted) {
        completer.complete(collector.finish(cancelled: cancelled));
      }
    }());

    return SearchRunHandle(
      results: completer.future,
      cancel: () {
        cancelled = true;
        process?.kill();
      },
    );
  }

  /// CLI args for one rg invocation (root paths appended by [search]). The
  /// pattern precedes `--` so rg never falls back to reading stdin (it does
  /// when no pattern is given — a missing pattern made rg block forever on
  /// the never-closed stdin pipe of the spawned process).
  List<String> buildRipgrepArguments(SearchQuery query) {
    final args = <String>[
      '--json',
      '--no-messages',
      '--max-filesize',
      '${kSearchMaxFileBytes ~/ (1024 * 1024)}M',
      '-m',
      '$kSearchMaxMatchesPerFile',
    ];
    if (!query.caseSensitive) args.add('-i');
    if (query.wholeWord) args.add('-w');
    if (!query.useRegex) args.add('-F');
    for (final glob in _splitPatterns(query.includeGlobs)) {
      args..add('-g')..add(_rgGlob(glob));
    }
    for (final glob in _splitPatterns(query.excludeGlobs)) {
      args..add('-g')..add('!${_rgGlob(glob)}');
    }
    // The pattern goes before `--`; roots (appended by [search]) stay path-only.
    args
      ..add(query.text)
      ..add('--');
    return args;
  }
}

List<String> _splitPatterns(String raw) => raw
    .split(',')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList(growable: false);

/// Maps our glob semantics onto rg's: a trailing `/` (directory prefix)
/// becomes `dir/**` (rg does not treat a trailing slash as a prefix match).
///
/// No `**/` prefix: rg anchors slash-bearing globs at its cwd, and the
/// caller sets cwd to the search root (`--cd`), so `common/**` means exactly
/// "root's common/ subtree" — matching [SearchGlobSet]'s anchored semantics
/// (and VS Code). A `**/` prefix would instead match same-named dirs at any
/// depth, diverging from the built-in engine.
String _rgGlob(String pattern) {
  if (pattern.length > 1 && pattern.endsWith('/')) {
    return '${pattern.substring(0, pattern.length - 1)}/**';
  }
  return pattern;
}

/// Shared snippet construction (rg engine and the built-in scanner build
/// [SearchMatch] rows the same way).
SearchMatch buildSearchMatch(
  int lineNo,
  String line,
  List<SearchMatchSpan> spans,
) {
  final first = spans.first;
  var snippet = line;
  var offset = 0;
  if (line.length > kSearchSnippetLength) {
    final windowStart = (first.start - kSearchSnippetLength ~/ 3).clamp(
      0,
      line.length - kSearchSnippetLength,
    );
    snippet = line.substring(
      windowStart,
      (windowStart + kSearchSnippetLength).clamp(0, line.length),
    );
    offset = windowStart;
  }
  return SearchMatch(
    lineNo: lineNo,
    snippet: snippet,
    spans: [
      for (final span in spans)
        SearchMatchSpan(start: span.start - offset, end: span.end - offset),
    ],
    truncatedLine: line.length > kSearchSnippetLength,
  );
}

/// Root-relative display path for [absolutePath] under [roots]: primary
/// (first) root unprefixed, other roots prefixed with the root's basename;
/// non-primary targets get a `targetId:` prefix.
String searchDisplayPathFor(
  String absolutePath,
  List<String> roots,
  p.Context pathContext, {
  required String targetId,
  String? primaryTargetId,
}) {
  for (var i = 0; i < roots.length; i++) {
    final root = roots[i];
    var rel = pathContext.relative(absolutePath, from: root);
    if (rel.startsWith('..') || pathContext.isAbsolute(rel)) continue;
    rel = rel.replaceAll(r'\', '/');
    final rootName = p.basename(root.replaceAll(r'\', '/'));
    final rootPrefixed = i == 0 ? rel : '$rootName/$rel';
    if (primaryTargetId == null || targetId == primaryTargetId) {
      return rootPrefixed;
    }
    return '$targetId:$rootPrefixed';
  }
  return absolutePath;
}


/// Accumulates parsed rg events into [SearchResults].
class _RipgrepCollector {
  _RipgrepCollector({
    required this.query,
    required this.pattern,
    required this.targetId,
    required this.pathContext,
    required this.roots,
    this.primaryTargetId,
  });

  final SearchQuery query;
  final RegExp pattern;
  final String targetId;
  final p.Context pathContext;
  final List<String> roots;
  final String? primaryTargetId;

  final _files = <String, SearchFileResult>{};
  final _fileOrder = <String>[];
  var total = 0;
  var truncated = false;

  void consumeLine(String line) {
    if (line.isEmpty) return;
    final dynamic event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      return; // Tolerate partial/unknown output.
    }
    if (event is! Map<String, Object?>) return;
    if (event['type'] != 'match') return;
    final data = event['data'];
    if (data is! Map<String, Object?>) return;
    _handleMatch(data);
  }

  void _handleMatch(Map<String, Object?> data) {
    if (truncated) return;
    final path = _pathText(data['path']);
    if (path == null) return; // Non-UTF-8 path (rg `bytes`) — skipped in v1.
    final lineNo = data['line_number'];
    if (lineNo is! int) return;
    final lines = data['lines'];
    final text = lines is Map<String, Object?> ? lines['text'] : null;
    if (text is! String) return;
    final line = text.endsWith('\n')
        ? text.substring(0, text.length - 1)
        : text;

    // Re-run the pattern locally: code-unit-accurate spans + immune to
    // rg-side byte-offset drift on non-ASCII lines.
    final spans = <SearchMatchSpan>[];
    for (final match in pattern.allMatches(line)) {
      spans.add(SearchMatchSpan(start: match.start, end: match.end));
    }
    if (spans.isEmpty) return; // Encoding edge — rg saw it, we can't.

    var file = _files[path];
    if (file == null) {
      file = SearchFileResult(
        targetId: targetId,
        absolutePath: path,
        displayPath: searchDisplayPathFor(
          path,
          roots,
          pathContext,
          targetId: targetId,
          primaryTargetId: primaryTargetId,
        ),
        matches: const [],
      );
      _fileOrder.add(path);
    }
    if (file.matches.length >= kSearchMaxMatchesPerFile) return;
    file = file.withMatches([...file.matches, buildSearchMatch(lineNo, line, spans)]);
    _files[path] = file;
    total++;
    if (total >= kSearchMaxMatchesTotal) truncated = true;
  }

  String? _pathText(Object? path) {
    if (path is Map<String, Object?> && path['text'] is String) {
      return path['text'] as String;
    }
    return null;
  }

  SearchResults finish({required bool cancelled}) {
    return SearchResults(
      files: [
        for (final path in _fileOrder)
          if (_files[path] case final file?) file,
      ],
      totalMatches: total,
      truncated: truncated || cancelled,
      engine: SearchEngineKind.ripgrep,
    );
  }
}
