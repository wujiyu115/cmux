/// Result of [fuzzyMatch]: matched indexes into the target (for highlighting)
/// and a relative score (higher = better). Empty indexes / score 0 for an
/// empty query.
class FuzzyMatch {
  const FuzzyMatch(this.indexes, this.score);
  final List<int> indexes;
  final int score;
}

/// Greedy leftmost subsequence match of [lowerQuery] against [target]
/// (case-insensitive). Returns matched indexes into [target] and a score, or
/// `null` when [lowerQuery] is not a subsequence.
///
/// Scoring: per-char base credit, contiguous-run bonus, word-start bonus
/// (start of string, after a non-alphanumeric, or a lower→Upper camelCase
/// boundary), and an earlier-first-match bonus. Shared by the command palette
/// and quick-open so both rank and highlight identically.
FuzzyMatch? fuzzyMatch(String target, String lowerQuery) {
  if (lowerQuery.isEmpty) return const FuzzyMatch([], 0);
  return fuzzyMatchLowered(target, target.toLowerCase(), lowerQuery);
}

/// Same match as [fuzzyMatch] against a caller-precomputed lowercase
/// [lowerTarget] — lets quick-open cache the lowercase label once per entry
/// instead of re-lowercasing the whole index on every keystroke. [target]
/// keeps its original case for the word-start bonus; [indexes] address it.
FuzzyMatch? fuzzyMatchLowered(
  String target,
  String lowerTarget,
  String lowerQuery,
) {
  if (lowerQuery.isEmpty) return const FuzzyMatch([], 0);
  final indexes = _greedyIndexes(lowerTarget, lowerQuery);
  if (indexes == null) return null;
  return FuzzyMatch(indexes, _scoreIndexes(target, indexes));
}

/// Score-only variant of [fuzzyMatchLowered]: the same greedy alignment and
/// score, with no index-list allocation — for prescreening large candidate
/// sets before spending a full match on the survivors. Null when [lowerQuery]
/// is not a subsequence; `0` for an empty query (mirrors [fuzzyMatch]).
int? fuzzyMatchScoreLowered(
  String target,
  String lowerTarget,
  String lowerQuery,
) {
  if (lowerQuery.isEmpty) return 0;
  var score = 0;
  var previous = -2;
  var first = -1;
  var t = 0;
  for (var q = 0; q < lowerQuery.length; q++) {
    final ch = lowerQuery.codeUnitAt(q);
    var found = -1;
    while (t < lowerTarget.length) {
      if (lowerTarget.codeUnitAt(t) == ch) {
        found = t;
        t++;
        break;
      }
      t++;
    }
    if (found < 0) return null;
    if (first < 0) first = found;
    score += 1;
    if (found == previous + 1) score += 6;
    if (_isWordStart(target, found)) score += 10;
    previous = found;
  }
  return score - first;
}

List<int>? _greedyIndexes(String lowerTarget, String lowerQuery) {
  final indexes = <int>[];
  var t = 0;
  for (var q = 0; q < lowerQuery.length; q++) {
    final ch = lowerQuery.codeUnitAt(q);
    var found = -1;
    while (t < lowerTarget.length) {
      if (lowerTarget.codeUnitAt(t) == ch) {
        found = t;
        t++;
        break;
      }
      t++;
    }
    if (found < 0) return null;
    indexes.add(found);
  }
  return indexes;
}

int _scoreIndexes(String target, List<int> indexes) {
  var score = 0;
  var previous = -2;
  for (final index in indexes) {
    // Base credit per matched char.
    score += 1;
    // Contiguous run bonus.
    if (index == previous + 1) score += 6;
    // Word-start bonus (start of string or preceded by a boundary).
    if (_isWordStart(target, index)) score += 10;
    previous = index;
  }
  // Earlier first match is better (length-independent so long titles are not
  // rewarded merely for being long).
  score -= indexes.first;
  return score;
}

bool _isWordStart(String target, int index) {
  if (index == 0) return true;
  final prev = target.codeUnitAt(index - 1);
  final isPrevAlnum =
      (prev >= 0x30 && prev <= 0x39) ||
      (prev >= 0x41 && prev <= 0x5A) ||
      (prev >= 0x61 && prev <= 0x7A);
  if (!isPrevAlnum) return true;
  // camelCase / lower→Upper boundary.
  final cur = target.codeUnitAt(index);
  final prevIsLower = prev >= 0x61 && prev <= 0x7A;
  final curIsUpper = cur >= 0x41 && cur <= 0x5A;
  return prevIsLower && curIsUpper;
}
