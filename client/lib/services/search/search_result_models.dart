import 'package:equatable/equatable.dart';

/// Which engine produced the results (shown in the status line: ripgrep vs
/// the slower built-in scanner).
enum SearchEngineKind { ripgrep, builtin }

/// One highlighted span inside a match snippet (character offsets into
/// [SearchMatch.snippet]).
class SearchMatchSpan extends Equatable {
  const SearchMatchSpan({required this.start, required this.end});

  final int start;
  final int end;

  @override
  List<Object?> get props => [start, end];
}

/// One matched line (VS Code groups all hits on the same line into one row).
class SearchMatch extends Equatable {
  const SearchMatch({
    required this.lineNo,
    required this.snippet,
    required this.spans,
    this.truncatedLine = false,
  });

  /// 1-based line number in the file.
  final int lineNo;

  /// Line content windowed to [kSearchSnippetLength] characters around the
  /// first hit.
  final String snippet;

  /// Matched spans (snippet-relative character offsets).
  final List<SearchMatchSpan> spans;

  /// True when the line was longer than the snippet window.
  final bool truncatedLine;

  @override
  List<Object?> get props => [lineNo, snippet, spans, truncatedLine];
}

/// All matches in one file. The opener resolves the filesystem at open time
/// from [targetId] via the workspace tools scope — avoids carrying a
/// non-equatable fs object through result diffing.
class SearchFileResult extends Equatable {
  const SearchFileResult({
    required this.targetId,
    required this.absolutePath,
    required this.displayPath,
    required this.matches,
  });

  /// Work-plane target the file lives on (`local`, `wsl:<distro>`, `ssh:…`).
  final String targetId;

  /// Plane-native absolute path (what the editor opens).
  final String absolutePath;

  /// Display path: root-relative, with non-primary roots prefixed by their
  /// basename (same convention as the quick-open index); non-primary targets
  /// get a `targetId:` prefix.
  final String displayPath;

  /// Total matches in this file (can exceed [matches].length when the
  /// per-file cap truncated the kept rows).
  final List<SearchMatch> matches;

  int get matchCount => matches.length;

  SearchFileResult withMatches(List<SearchMatch> matches) => SearchFileResult(
    targetId: targetId,
    absolutePath: absolutePath,
    displayPath: displayPath,
    matches: List.unmodifiable(matches),
  );

  @override
  List<Object?> get props => [targetId, absolutePath, displayPath, matches];
}

/// A complete search outcome.
class SearchResults extends Equatable {
  const SearchResults({
    required this.files,
    required this.totalMatches,
    required this.truncated,
    required this.engine,
  });

  const SearchResults.empty({this.engine = SearchEngineKind.builtin})
    : files = const [],
      totalMatches = 0,
      truncated = false;

  final List<SearchFileResult> files;
  final int totalMatches;
  final bool truncated;
  final SearchEngineKind engine;

  @override
  List<Object?> get props => [files, totalMatches, truncated, engine];
}
