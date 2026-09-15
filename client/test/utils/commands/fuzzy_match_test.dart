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

  group('lowered and score-only variants', () {
    final targets = [
      'main_file_search.dart',
      'Terminal',
      'xfile_search',
      'xxbcyy',
      r'lib\main.dart',
      'readME',
    ];
    final queries = ['mfs', 'trm', 'fs', 'bc', 'lib/main', 'readme', 'zzz', ''];

    test('fuzzyMatchLowered reproduces fuzzyMatch (score and indexes)', () {
      for (final target in targets) {
        for (final query in queries) {
          final base = fuzzyMatch(target, query);
          final lowered = fuzzyMatchLowered(
            target,
            target.toLowerCase(),
            query,
          );
          expect(lowered?.score, base?.score, reason: '$target vs "$query"');
          expect(lowered?.indexes, base?.indexes, reason: '$target vs "$query"');
        }
      }
    });

    test('fuzzyMatchScoreLowered reproduces the fuzzyMatch score', () {
      for (final target in targets) {
        for (final query in queries) {
          final base = fuzzyMatch(target, query);
          expect(
            fuzzyMatchScoreLowered(target, target.toLowerCase(), query),
            base?.score,
            reason: '$target vs "$query"',
          );
        }
      }
    });

    test('a caller-supplied lowerTarget may be pre-normalized', () {
      // Path matching normalizes separators before matching; the lowered
      // variants must not care where that normalization happened.
      final target = r'lib\main.dart';
      expect(
        fuzzyMatchLowered(target, 'lib/main.dart', 'lib/main')?.indexes,
        [0, 1, 2, 3, 4, 5, 6, 7],
      );
      expect(
        fuzzyMatchScoreLowered(target, 'lib/main.dart', 'lib/main'),
        fuzzyMatchLowered(target, 'lib/main.dart', 'lib/main')?.score,
      );
    });
  });
}
