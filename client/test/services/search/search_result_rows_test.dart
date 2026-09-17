import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/search/search_result_models.dart';
import 'package:teampilot/services/search/search_result_rows.dart';

void main() {
  test('buildSearchRows groups headers and match rows in order', () {
    const results = SearchResults(
      totalMatches: 3,
      truncated: false,
      engine: SearchEngineKind.ripgrep,
      files: [
        SearchFileResult(
          targetId: 'local',
          absolutePath: '/repo/a.dart',
          displayPath: 'lib/a.dart',
          matches: [
            SearchMatch(
              lineNo: 1,
              snippet: 'foo',
              spans: [SearchMatchSpan(start: 0, end: 3)],
            ),
            SearchMatch(
              lineNo: 5,
              snippet: 'foo again',
              spans: [SearchMatchSpan(start: 0, end: 3)],
            ),
          ],
        ),
        SearchFileResult(
          targetId: 'local',
          absolutePath: '/repo/b.dart',
          displayPath: 'lib/b.dart',
          matches: [
            SearchMatch(
              lineNo: 2,
              snippet: 'foo',
              spans: [SearchMatchSpan(start: 0, end: 3)],
            ),
          ],
        ),
      ],
    );

    final rows = buildSearchRows(results);

    expect(rows, hasLength(5));
    expect(rows[0], isA<SearchFileHeaderRow>());
    final header = rows[0] as SearchFileHeaderRow;
    expect(header.displayPath, 'lib/a.dart');
    expect(header.matchCount, 2);
    expect(header.fileIndex, 0);
    expect((rows[1] as SearchMatchRow).match.lineNo, 1);
    expect((rows[2] as SearchMatchRow).match.lineNo, 5);
    final secondHeader = rows[3] as SearchFileHeaderRow;
    expect(secondHeader.fileIndex, 1);
    expect((rows[4] as SearchMatchRow).fileIndex, 1);
  });

  test('empty results build no rows', () {
    expect(buildSearchRows(const SearchResults.empty()), isEmpty);
  });
}
