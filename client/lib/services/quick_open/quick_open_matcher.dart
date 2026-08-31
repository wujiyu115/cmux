import 'package:flutter/foundation.dart';

import '../../utils/commands/fuzzy_match.dart';
import 'quick_open_index.dart';

/// Which part of a [QuickOpenFileEntry] the query matched — drives the line
/// of the result row that gets highlighted.
enum QuickOpenMatchTarget { name, relativePath }

/// A successful quick-open match: [score] for ranking (higher = better) and
/// [indexes] into the matched target string for highlighting.
@immutable
class QuickOpenMatch {
  const QuickOpenMatch({
    required this.score,
    required this.target,
    required this.indexes,
  });

  final int score;
  final QuickOpenMatchTarget target;
  final List<int> indexes;
}

/// Path matches rank below basename matches of comparable quality, mirroring
/// VS Code's basename-first ranking. Queries containing a separator can never
/// match a basename, so this only affects mixed result lists.
const int _pathMatchPenalty = 10;

/// Fuzzy-matches [lowerQuery] (already lowercased, as for [fuzzyMatch])
/// against the entry's basename first, falling back to its workspace-relative
/// path so queries like `docs/main` can pick between same-named files.
///
/// Both sides are separator-normalized (`\` → `/`) for the path comparison —
/// the replacement is one-to-one, so [QuickOpenMatch.indexes] stay valid
/// against the unnormalized path. Returns `null` when neither matches.
QuickOpenMatch? quickOpenMatch(QuickOpenFileEntry entry, String lowerQuery) {
  if (lowerQuery.isEmpty) return null;
  final nameMatch = fuzzyMatch(entry.name, lowerQuery);
  if (nameMatch != null) {
    return QuickOpenMatch(
      score: nameMatch.score,
      target: QuickOpenMatchTarget.name,
      indexes: nameMatch.indexes,
    );
  }
  final pathMatch = fuzzyMatch(
    _normalizeSeparators(entry.relativePath),
    _normalizeSeparators(lowerQuery),
  );
  if (pathMatch == null) return null;
  return QuickOpenMatch(
    score: pathMatch.score - _pathMatchPenalty,
    target: QuickOpenMatchTarget.relativePath,
    indexes: pathMatch.indexes,
  );
}

String _normalizeSeparators(String value) => value.replaceAll(r'\', '/');
