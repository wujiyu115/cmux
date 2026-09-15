import '../../models/workspace_index_dirs.dart';

/// Directory names whose contents are pure noise for quick-open.
const quickOpenIgnoredDirNames = {
  '.git',
  '.hg',
  '.svn',
  'node_modules',
  '.dart_tool',
  'build',
  '.idea',
  '.gradle',
  '.next',
  'dist',
};

/// Resolves a workspace's [WorkspaceIndexDirs] against one relative path:
/// the **deepest** matching user rule wins, so an include carved under an
/// exclude re-enters the index while a deeper exclude wins right back. With
/// no user rule matched, [allows] falls back to the built-in ignore set
/// (dot-segments plus [quickOpenIgnoredDirNames]); a matching include rule
/// overrides the built-in ignores too.
class QuickOpenDirRules {
  const QuickOpenDirRules(this.dirs);

  const QuickOpenDirRules.none() : dirs = const WorkspaceIndexDirs.empty();

  final WorkspaceIndexDirs dirs;

  bool get isEmpty => dirs.isEmpty;

  /// User rules only (no built-in ignore set) — for the `git ls-files` source,
  /// which already honors .gitignore; files it still reports under dot- or
  /// build dirs are tracked (or untracked-but-visible) and left as-is.
  bool allowsUser(String relative) =>
      _deepestMatch(relative) != _RuleMatch.exclude;

  /// User rules with the built-in ignore fallback — for the recursive and
  /// symlink-following listings.
  bool allows(String relative) => switch (_deepestMatch(relative)) {
    _RuleMatch.include => true,
    _RuleMatch.exclude => false,
    _RuleMatch.none => !isBuiltInIgnored(relative),
  };

  /// Built-in noise filter: any dot-segment or [quickOpenIgnoredDirNames]
  /// segment in [relative] (native separators tolerated).
  static bool isBuiltInIgnored(String relative) {
    final posix = _toPosix(relative);
    for (final segment in posix.split('/')) {
      if (segment.isEmpty) continue;
      if (segment.startsWith('.')) return true;
      if (quickOpenIgnoredDirNames.contains(segment)) return true;
    }
    return false;
  }

  /// UI validation: an include rule that sits under no exclude rule cannot
  /// carve anything out — the path is searchable by default anyway.
  bool isOrphanInclude(String includePath) =>
      !dirs.excluded.any((excluded) => _isAtOrUnder(includePath, excluded));

  _RuleMatch _deepestMatch(String relative) {
    final posix = _toPosix(relative);
    var best = _RuleMatch.none;
    var bestDepth = -1;
    for (final rule in dirs.excluded) {
      final depth = _matchDepth(posix, rule);
      if (depth > bestDepth) {
        best = _RuleMatch.exclude;
        bestDepth = depth;
      }
    }
    // Strictly deeper: an include at the same depth as an exclude is a
    // contradictory duplicate — exclude wins (the UI warns about it).
    for (final rule in dirs.included) {
      final depth = _matchDepth(posix, rule);
      if (depth > bestDepth) {
        best = _RuleMatch.include;
        bestDepth = depth;
      }
    }
    return best;
  }

  static int _matchDepth(String posixPath, String rule) {
    if (rule.isEmpty) return -1;
    if (posixPath == rule) return rule.split('/').length;
    if (posixPath.startsWith('$rule/')) return rule.split('/').length;
    return -1;
  }

  static bool _isAtOrUnder(String path, String ancestor) =>
      path == ancestor || path.startsWith('$ancestor/');

  static String _toPosix(String path) =>
      path.contains(r'\') ? path.replaceAll(r'\', '/') : path;
}

enum _RuleMatch { none, include, exclude }
