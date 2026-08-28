import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/commands/fuzzy_match.dart';

void main() {
  group('fuzzyMatch', () {
    test('subsequence matches with highlight indexes', () {
      final match = fuzzyMatch('main_file_search.dart', 'mfs');
      expect(match, isNotNull);
      // 'm' at 0, 'f' at 5 (first 'f' in 'file'), 's' at 10 (first 's').
      expect(match!.indexes, [0, 5, 10]);
    });

    test('returns null when not a subsequence', () {
      expect(fuzzyMatch('terminal', 'zzz'), isNull);
    });

    test('word-start beats mid-word: higher score', () {
      final wordStart = fuzzyMatch('file_search', 'fs');
      final midWord = fuzzyMatch('xfile_search', 'fs');
      expect(wordStart!.score, greaterThan(midWord!.score));
    });

    test('contiguous run beats sparse: higher score', () {
      final contiguous = fuzzyMatch('xxbcyy', 'bc');
      final sparse = fuzzyMatch('xbxc', 'bc');
      expect(contiguous!.score, greaterThan(sparse!.score));
    });

    test('case-insensitive', () {
      expect(fuzzyMatch('Terminal', 'trm'), isNotNull);
    });

    test('empty query matches with empty indexes and zero score', () {
      final match = fuzzyMatch('anything', '');
      expect(match!.indexes, isEmpty);
      expect(match.score, 0);
    });
  });
}
