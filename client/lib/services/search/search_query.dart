import 'package:equatable/equatable.dart';

/// Files larger than this are skipped by the built-in engine (rg gets
/// `--max-filesize` with the same value).
const int kSearchMaxFileBytes = 2 * 1024 * 1024;

/// Cap on matches kept per file (extras dropped; count kept for the header).
const int kSearchMaxMatchesPerFile = 200;

/// Cap on total matches kept across the workspace; beyond this the search
/// stops and results are marked truncated.
const int kSearchMaxMatchesTotal = 2000;

/// Visible snippet window per match line (characters around the first hit).
const int kSearchSnippetLength = 240;

/// Everything the search engines need to run, in an equatable value so the
/// cubit can diff queries (debounce triggers only on change).
class SearchQuery extends Equatable {
  const SearchQuery({
    this.text = '',
    this.pathFilter = '',
    this.caseSensitive = false,
    this.wholeWord = false,
    this.useRegex = false,
    this.includeGlobs = '',
    this.excludeGlobs = '',
  });

  final String text;
  final String pathFilter;
  final bool caseSensitive;
  final bool wholeWord;
  final bool useRegex;
  final String includeGlobs;
  final String excludeGlobs;

  bool get isEmpty => text.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  SearchQuery copyWith({
    String? text,
    String? pathFilter,
    bool? caseSensitive,
    bool? wholeWord,
    bool? useRegex,
    String? includeGlobs,
    String? excludeGlobs,
  }) => SearchQuery(
    text: text ?? this.text,
    pathFilter: pathFilter ?? this.pathFilter,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    wholeWord: wholeWord ?? this.wholeWord,
    useRegex: useRegex ?? this.useRegex,
    includeGlobs: includeGlobs ?? this.includeGlobs,
    excludeGlobs: excludeGlobs ?? this.excludeGlobs,
  );

  /// Compiles [text] into the match pattern. Returns the regex, or an error
  /// message when the pattern is invalid (regex mode only) — the caller
  /// shows it instead of running.
  ({RegExp? pattern, String? patternError}) compilePattern() {
    final raw = text;
    if (raw.isEmpty) return (pattern: null, patternError: null);
    if (!useRegex) {
      var source = RegExp.escape(raw);
      if (wholeWord && _hasWordBoundaries(raw)) {
        source = '\\b$source\\b';
      }
      return (pattern: RegExp(source, caseSensitive: caseSensitive), patternError: null);
    }
    var source = raw;
    if (wholeWord && _hasWordBoundaries(raw)) {
      source = '\\b(?:$raw)\\b';
    }
    try {
      return (pattern: RegExp(source, caseSensitive: caseSensitive), patternError: null);
    } on FormatException {
      return (pattern: null, patternError: raw);
    }
  }

  /// Whole-word `\b` anchors only make sense when the pattern starts/ends
  /// with word characters.
  static bool _hasWordBoundaries(String raw) {
    if (raw.isEmpty) return false;
    final start = raw.codeUnitAt(0);
    final end = raw.codeUnitAt(raw.length - 1);
    return _isWordChar(start) && _isWordChar(end);
  }

  static bool _isWordChar(int codeUnit) {
    return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
        codeUnit == 0x5F;
  }

  @override
  List<Object?> get props => [
    text,
    pathFilter,
    caseSensitive,
    wholeWord,
    useRegex,
    includeGlobs,
    excludeGlobs,
  ];
}
