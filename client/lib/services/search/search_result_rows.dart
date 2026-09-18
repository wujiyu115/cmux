import 'package:equatable/equatable.dart';

import 'search_result_models.dart';

/// Flat visible rows for the search results list (mirrors the
/// `GitChangesVisibleRow` pattern: precomputed, equatable, widget only
/// renders).
sealed class SearchRow extends Equatable {
  const SearchRow();
}

/// File group header: display path + match count.
class SearchFileHeaderRow extends SearchRow {
  const SearchFileHeaderRow({
    required this.displayPath,
    required this.matchCount,
    required this.fileIndex,
  });

  final String displayPath;
  final int matchCount;

  /// Index into [SearchResults.files] — opening the header opens the file.
  final int fileIndex;

  @override
  List<Object?> get props => [displayPath, matchCount, fileIndex];
}

/// One match row under its file header.
class SearchMatchRow extends SearchRow {
  const SearchMatchRow({required this.fileIndex, required this.match});

  final int fileIndex;
  final SearchMatch match;

  @override
  List<Object?> get props => [fileIndex, match];
}

/// Builds the flat row list: one header per file followed by its match rows —
/// except for files in [collapsedFiles], whose match rows are omitted
/// (VS Code-style per-file collapse). Headers always stay visible.
List<SearchRow> buildSearchRows(
  SearchResults results, {
  Set<String> collapsedFiles = const {},
}) {
  final rows = <SearchRow>[];
  for (var i = 0; i < results.files.length; i++) {
    final file = results.files[i];
    rows.add(
      SearchFileHeaderRow(
        displayPath: file.displayPath,
        matchCount: file.matchCount,
        fileIndex: i,
      ),
    );
    if (collapsedFiles.contains(file.absolutePath)) continue;
    for (final match in file.matches) {
      rows.add(SearchMatchRow(fileIndex: i, match: match));
    }
  }
  return rows;
}
