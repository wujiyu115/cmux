import 'package:equatable/equatable.dart';

/// Glob matching for the search panel's include/exclude fields (VS Code
/// semantics, matched against the workspace-relative posix path):
///
/// - `*` matches within one segment (not `/`), `?` one non-`/` character,
///   `**` any span including `/`;
/// - a pattern containing `/` anchors at the path start; otherwise it
///   matches the basename (any directory);
/// - a trailing `/` makes the pattern a directory prefix (all descendants);
/// - comma-separated patterns in one field; any-match semantics.
///
/// Brace expansion (`{a,b}`) is not supported in v1 — braces are matched
/// literally.
class SearchGlobSet extends Equatable {
  SearchGlobSet(String rawPatterns)
    : _regexes = _compileAll(rawPatterns);

  const SearchGlobSet.empty() : _regexes = const <RegExp>[];

  final List<RegExp> _regexes;

  /// True when no usable pattern was given — include sets treat this as
  /// "match everything".
  bool get isEmpty => _regexes.isEmpty;

  bool matches(String posixRelativePath) {
    for (final regex in _regexes) {
      if (regex.hasMatch(posixRelativePath)) return true;
    }
    return false;
  }

  static List<RegExp> _compileAll(String rawPatterns) {
    final patterns = rawPatterns
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    return [
      for (final pattern in patterns)
        if (_compileGlob(pattern) case final regex?) regex,
    ];
  }

  static RegExp? _compileGlob(String pattern) {
    final isDirPrefix = pattern.length > 1 && pattern.endsWith('/');
    var body = isDirPrefix ? pattern.substring(0, pattern.length - 1) : pattern;
    if (body.isEmpty) return null;

    // A leading `**/` matches the pattern at any depth *including the top
    // level* — compiled as an optional directory prefix, not `.*​/`.
    final source = StringBuffer();
    if (body.startsWith('**/')) {
      source.write('(?:.*/)?');
      body = body.substring(3);
    }
    var i = 0;
    while (i < body.length) {
      final c = body[i];
      if (c == '*') {
        if (i + 1 < body.length && body[i + 1] == '*') {
          source.write('.*');
          i += 2;
        } else {
          source.write('[^/]*');
          i += 1;
        }
      } else if (c == '?') {
        source.write('[^/]');
        i += 1;
      } else {
        source.write(RegExp.escape(c));
        i += 1;
      }
    }

    // No slash → basename match from any directory; with slash → anchored.
    final anchored = body.contains('/');
    final prefix = anchored ? '^' : '^(?:.*/)?';
    final suffix = isDirPrefix ? '/.*\$' : '\$';
    try {
      return RegExp('$prefix$source$suffix');
    } on FormatException {
      return null;
    }
  }

  @override
  List<Object?> get props => [_regexes.map((r) => r.pattern).join('\n')];
}
