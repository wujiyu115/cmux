import '../../services/commands/command_definition.dart';
import 'fuzzy_match.dart';

/// One ranked command-palette entry produced by [filterCommandPalette].
class CommandPaletteMatch {
  const CommandPaletteMatch({
    required this.command,
    required this.title,
    required this.matchedIndexes,
    required this.score,
  });

  final CommandDefinition command;

  /// The resolved display title the match was computed against.
  final String title;

  /// Indexes into [title] that matched the query, for highlighting. Empty for
  /// an empty query or a category-assisted match.
  final List<int> matchedIndexes;

  /// Relative rank; higher sorts first. `0` for an empty query.
  final int score;
}

/// Filters and ranks [catalog] for the command palette.
///
/// Availability is decided by [isAvailable] (typically `when` satisfied AND a
/// handler registered) — unavailable commands never appear. With an empty
/// [query] the result is every available command ordered MRU-first (in [mru]
/// order) then catalog order. With a non-empty query, commands are kept when
/// the query is a case-insensitive subsequence of their title (or, as a
/// fallback, of `"<category title> <title>"`); the score favours contiguous
/// runs, matches at word starts, and an earlier first match, with MRU position
/// and finally catalog order as deterministic tiebreakers.
List<CommandPaletteMatch> filterCommandPalette({
  required List<CommandDefinition> catalog,
  required String query,
  required String Function(CommandDefinition) titleOf,
  required bool Function(CommandDefinition) isAvailable,
  required List<String> mru,
  String Function(CommandDefinition)? categoryTitleOf,
}) {
  final available = catalog.where(isAvailable).toList(growable: false);

  final catalogIndex = <String, int>{};
  for (var i = 0; i < catalog.length; i++) {
    catalogIndex[catalog[i].id] = i;
  }
  final mruRank = <String, int>{};
  for (var i = 0; i < mru.length; i++) {
    mruRank.putIfAbsent(mru[i], () => i);
  }

  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    final byId = {for (final def in available) def.id: def};
    final ordered = <CommandDefinition>[];
    final placed = <String>{};
    for (final id in mru) {
      final def = byId[id];
      if (def != null && placed.add(id)) ordered.add(def);
    }
    for (final def in available) {
      if (placed.add(def.id)) ordered.add(def);
    }
    return [
      for (final def in ordered)
        CommandPaletteMatch(
          command: def,
          title: titleOf(def),
          matchedIndexes: const [],
          score: 0,
        ),
    ];
  }

  final lowerQuery = trimmed.toLowerCase();
  final results = <CommandPaletteMatch>[];
  for (final def in available) {
    final title = titleOf(def);
    final match = fuzzyMatch(title, lowerQuery);
    if (match != null) {
      results.add(
        CommandPaletteMatch(
          command: def,
          title: title,
          matchedIndexes: match.indexes,
          score: match.score,
        ),
      );
      continue;
    }
    // Fallback: allow the category to satisfy the query, but do not highlight.
    final categoryTitle = categoryTitleOf?.call(def);
    if (categoryTitle != null && categoryTitle.isNotEmpty) {
      final haystack = '$categoryTitle $title';
      final catMatch = fuzzyMatch(haystack, lowerQuery);
      if (catMatch != null) {
        results.add(
          CommandPaletteMatch(
            command: def,
            title: title,
            matchedIndexes: const [],
            // Category-only matches rank below any direct title match.
            score: catMatch.score - 1000,
          ),
        );
      }
    }
  }

  results.sort((a, b) {
    if (a.score != b.score) return b.score.compareTo(a.score);
    final aMru = mruRank[a.command.id] ?? mru.length;
    final bMru = mruRank[b.command.id] ?? mru.length;
    if (aMru != bMru) return aMru.compareTo(bMru);
    return catalogIndex[a.command.id]!.compareTo(catalogIndex[b.command.id]!);
  });
  return results;
}
