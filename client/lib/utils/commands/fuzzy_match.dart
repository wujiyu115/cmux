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
  if (lowerQuery.isEmpty) {
    return const FuzzyMatch([], 0);
  }
  final lowerTarget = target.toLowerCase();
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
  return FuzzyMatch(indexes, score);
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
