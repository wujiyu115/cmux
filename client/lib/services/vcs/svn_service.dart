import 'dart:convert';

import '../../models/git_blame.dart';
import '../../utils/logging/logger.dart';
import '../storage/runtime_context.dart';
import 'svn_command_runner.dart';

/// Thrown when an svn mutation exits non-zero; [message] carries stderr.
class SvnException implements Exception {
  SvnException(this.message);
  final String message;
  @override
  String toString() => 'SvnException: $message';
}

/// How one svn working-copy path changed (`svn status` first column).
enum SvnChangeKind {
  added, // A
  modified, // M
  deleted, // D
  replaced, // R
  conflicted, // C
  missing, // !
  unversioned, // ?
  external, // X
  ignored, // I
}

/// One `svn status` row.
class SvnFileChange {
  const SvnFileChange({
    required this.path,
    required this.kind,
    this.revision,
    this.changelist,
  });

  /// Path relative to the working-copy root (`/` separators as svn prints).
  final String path;

  /// Only conflicts set both columns; kind reflects the wc state.
  final SvnChangeKind kind;

  /// Base revision of the entry (omitted for added/`?`/`!`/`X`/`I` rows).
  final int? revision;

  /// Changelist name when the row is in one.
  final String? changelist;

  bool get isExternalsRow => kind == SvnChangeKind.external;

  /// Single-letter badge shown in the UI (matches `svn status` output).
  String get badge => switch (kind) {
    SvnChangeKind.added => 'A',
    SvnChangeKind.modified => 'M',
    SvnChangeKind.deleted => 'D',
    SvnChangeKind.replaced => 'R',
    SvnChangeKind.conflicted => 'C',
    SvnChangeKind.missing => '!',
    SvnChangeKind.unversioned => '?',
    SvnChangeKind.external => 'X',
    SvnChangeKind.ignored => 'I',
  };
}

/// `svn info` of a working copy — the panel header data.
class SvnInfo {
  const SvnInfo({required this.url, required this.revision});

  final String url;
  final int revision;
}

/// Runs `svn` for the source control panel on the active storage backend
/// (native, WSL, or SSH remote host). Mirrors [GitService]: pure
/// projection over an injected [SvnCommandRunner] so every method is
/// unit-testable without a process.
class SvnService {
  SvnService({SvnCommandRunner? runner})
    : _runner = runner ?? LocalSvnCommandRunner();

  /// Builds a service for [ctx]'s storage backend (local / WSL / SSH).
  factory SvnService.forContext(RuntimeContext ctx) =>
      SvnService(runner: svnCommandRunnerForContext(ctx));

  /// Test seam: when set, the default [SvnCubit] builds this instead of a
  /// real process-backed service, so widget tests never spawn `svn`.
  static SvnService Function()? debugOverrideFactory;

  final SvnCommandRunner _runner;

  /// Resets static availability caches. Tests call this in setUp.
  static void debugResetExecutableCache() {
    LocalSvnCommandRunner.debugResetExecutableCache();
    RemoteSvnCommandRunner.debugResetAvailabilityCache();
    WslSvnCommandRunner.debugResetAvailabilityCache();
  }

  Future<bool> get isAvailable => _runner.isAvailable;

  Future<String> _run(String dir, List<String> args) async {
    final result = await _runner.runInDirectory(dir, args);
    if (result.exitCode != 0) {
      final err = result.stderr.trim();
      final out = result.stdout.trim();
      final detail = err.isEmpty ? out : err;
      appLogger.d('[Svn] ${args.join(' ')} exit ${result.exitCode}: $detail');
      throw SvnException(detail.isEmpty ? 'svn ${args.first} failed' : detail);
    }
    return result.stdout;
  }

  /// Raw run for probing; non-zero exits return null instead of throwing.
  Future<GitCommandResult?> _tryRun(String dir, List<String> args) async {
    if (!await isAvailable) return null;
    final result = await _runner.runInDirectory(dir, args);
    return result.exitCode == 0 ? result : null;
  }

  /// Working-copy info, or null when [dir] is not an svn checkout.
  Future<SvnInfo?> info(String dir) async {
    final result = await _tryRun(dir, ['info', '--xml']);
    if (result == null) return null;
    final url = _xmlFirst(result.stdout, 'url');
    final revision = int.tryParse(
      _xmlAttr(result.stdout, 'entry', 'revision') ?? '',
    );
    if (url == null || revision == null) return null;
    return SvnInfo(url: url, revision: revision);
  }

  /// Changed paths for the wc rooted at [dir].
  ///
  /// `--ignore-externals` keeps externals from recursing into their own
  /// repos; `X` rows still surface (externals directories themselves), and
  /// externals' own status is refreshed only when the user updates.
  Future<List<SvnFileChange>> status(String dir) async {
    final out = await _run(dir, const [
      'status',
      '--ignore-externals',
    ]);
    return parseSvnStatus(out);
  }

  /// Unified diff of one path's local modifications.
  Future<String> diff(String dir, String relativePath) =>
      _run(dir, ['diff', '--', relativePath]);

  /// Per-line blame of [relativePath] at the wc content, mapped onto the
  /// shared [GitBlameEntry] model so the editor blame bar renders both
  /// VCSes identically.
  Future<List<GitBlameEntry>?> blameFile(String dir, String relativePath) async {
    if (!await isAvailable) return null;
    // `svn blame` exits non-zero for unversioned/binary paths — same
    // "no blame" contract as git's blameFile.
    final result = await _runner.runInDirectory(dir, [
      'blame',
      '--verbose',
      '--',
      relativePath,
    ]);
    if (result.exitCode != 0) return null;
    final entries = parseSvnBlame(result.stdout);
    return entries.isEmpty ? null : entries;
  }

  /// `svn update` of the wc. Returns the summary tail line(s).
  Future<String> update(String dir) async =>
      _run(dir, const ['update', '--accept', 'postpone']);

  /// Commits [paths]; empty list means everything changed in the wc.
  Future<String> commit(String dir, String message, List<String> paths) async {
    final args = ['commit', '-m', message];
    if (paths.isNotEmpty) args.addAll(['--', ...paths]);
    return _run(dir, args);
  }

  /// Reverts local modifications of [paths].
  Future<void> revert(String dir, List<String> paths) async {
    if (paths.isEmpty) return;
    await _run(dir, ['revert', '--', ...paths]);
  }

  /// Adds unversioned paths to version control.
  Future<void> add(String dir, List<String> paths) async {
    if (paths.isEmpty) return;
    await _run(dir, ['add', '--', ...paths]);
  }
}

/// Parses `svn status` output: one row per line, first column is the wc
/// status letter, columns 2-7 carry repo/props/lock info, revision shows
/// after a space for some rows, changelist trails a `---` separator.
///
/// Skips blank lines and `Performing status on external item…` notices.
List<SvnFileChange> parseSvnStatus(String stdout) {
  final rows = <SvnFileChange>[];
  for (final rawLine in const LineSplitter().convert(stdout)) {
    if (rawLine.isEmpty) continue;
    if (rawLine.startsWith('Performing status')) continue;
    if (rawLine.startsWith('Status against')) continue;
    if (!rawLine.startsWith(RegExp(r'^[AMDR C!X I?]'))) {
      // svn prints some rows with a leading space (prop-only changes); the
      // wc column may be blank there — treat as modified.
      if (!rawLine.startsWith(' ')) continue;
    }

    final wcLetter = rawLine[0] == ' ' ? 'M' : rawLine[0];
    final kind = _kindForLetter(wcLetter);
    if (kind == null) continue;

    var rest = rawLine.substring(1);
    // Trim remaining status columns (7 columns + spaces before the path).
    // Layout: XYYYYYY <path> [revision-or-changelist]
    var pathPart = rest.trimLeft();
    // Revision: a trailing bare integer after the path (from `svn status
    // -v`); changelist: after `---`. Neither is in default output, but
    // tolerate both.
    String? changelist;
    final sep = pathPart.indexOf(' --- ');
    if (sep >= 0) {
      changelist = pathPart.substring(sep + 5).trim();
      if (changelist.isEmpty) changelist = null;
      pathPart = pathPart.substring(0, sep);
    }
    int? revision;
    final lastSpace = pathPart.lastIndexOf(' ');
    if (lastSpace > 0) {
      revision = int.tryParse(pathPart.substring(lastSpace + 1).trim());
      if (revision != null) {
        pathPart = pathPart.substring(0, lastSpace);
      }
    }
    final path = pathPart.trim();
    if (path.isEmpty) continue;
    rows.add(
      SvnFileChange(
        path: path,
        kind: kind,
        revision: revision,
        changelist: changelist,
      ),
    );
  }
  return rows;
}

SvnChangeKind? _kindForLetter(String letter) {
  return switch (letter) {
    'A' => SvnChangeKind.added,
    'M' => SvnChangeKind.modified,
    'D' => SvnChangeKind.deleted,
    'R' => SvnChangeKind.replaced,
    'C' => SvnChangeKind.conflicted,
    '!' => SvnChangeKind.missing,
    '?' => SvnChangeKind.unversioned,
    'X' => SvnChangeKind.external,
    'I' => SvnChangeKind.ignored,
    _ => null,
  };
}

/// Parses `svn blame --verbose`: one line per source line,
/// `  revision   author   date  content…` with the content tab-separated.
/// Consecutive identical (revision, author) rows merge into one range —
/// the same shape git blame's incremental output folds into.
List<GitBlameEntry> parseSvnBlame(String stdout) {
  final lines = const LineSplitter().convert(stdout);
  final entries = <GitBlameEntry>[];
  var lineNo = 0;
  final rangesByRev = <int, List<GitBlameLineRange>>{};
  final propsByRev = <int, Map<String, String>>{};

  // Real `svn blame --verbose` rows (verified against svn 1.10 via od -c):
  // ` 368522 author 2020-04-22 21:39:20 +0800 (Wed, 22 Apr 2020) -- content`
  // — space-separated; after the parenthesized date comes `--` (or `---`
  // when the content itself starts with `-`), then the line content.
  final lineRegex = RegExp(
    r'^\s*(\d+)\s+(\S+)\s+'
    r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4} \([^)]*\))'
    r'\s+--[-\s]?(.*)$',
  );

  for (final raw in lines) {
    lineNo++;
    final m = lineRegex.firstMatch(raw);
    if (m == null) {
      // Skipped-binary notices etc.
      continue;
    }
    final revision = int.tryParse(m.group(1) ?? '');
    if (revision == null) continue;
    final author = m.group(2) ?? '';
    final dateStr = (m.group(3) ?? '').trim();

    rangesByRev.putIfAbsent(revision, () => []).add(
      GitBlameLineRange(start: lineNo, end: lineNo),
    );
    propsByRev.putIfAbsent(revision, () => {})['author'] = author;
    if (dateStr.isNotEmpty) {
      propsByRev[revision]!['date'] = dateStr;
    }
  }
  if (rangesByRev.isEmpty) return entries;

  // Coalesce consecutive single-line ranges of the same revision into one.
  for (final rev in rangesByRev.keys) {
    final ranges = rangesByRev[rev]!..sort((a, b) => a.start.compareTo(b.start));
    final coalesced = <GitBlameLineRange>[];
    for (final range in ranges) {
      final last = coalesced.isEmpty ? null : coalesced.last;
      if (last != null && range.start == last.end + 1) {
        coalesced[coalesced.length - 1] = GitBlameLineRange(
          start: last.start,
          end: range.end,
        );
      } else {
        coalesced.add(range);
      }
    }
    rangesByRev[rev] = coalesced;
  }

  final authorTimeOf = <int, int?>{};
  for (final rev in rangesByRev.keys) {
    final dateStr = propsByRev[rev]?['date'];
    authorTimeOf[rev] = dateStr == null ? null : _parseSvnDate(dateStr);
    entries.add(
      GitBlameEntry(
        // svn revisions are decimal; left-padded to keep the 40-char-ish
        // shape consumers expect (hash is display-only here).
        hash: rev.toString().padLeft(8, 'r'),
        ranges: List.unmodifiable(rangesByRev[rev]!),
        authorName: propsByRev[rev]?['author'],
        authorTime: authorTimeOf[rev],
        subject: 'r$rev',
      ),
    );
  }
  entries.sort((a, b) => a.ranges.first.start.compareTo(b.ranges.first.start));
  return entries;
}

/// `svn blame --verbose` dates look like `2026-09-22 12:34:56 +0800 (Mon,
/// 22 Sep 2026)`. Parse the leading timestamp (local-of-utc-offset).
int? _parseSvnDate(String dateStr) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2}) ([+-]\d{4})',
  ).firstMatch(dateStr);
  if (match == null) return null;
  final offset = match.group(7)!;
  final offsetMinutes =
      (int.parse(offset.substring(1, 3)) * 60 +
          int.parse(offset.substring(3, 5))) *
      (offset.startsWith('-') ? -1 : 1);
  final utc = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
  final epoch = utc.millisecondsSinceEpoch ~/ 1000;
  return epoch - offsetMinutes * 60;
}

String? _xmlFirst(String xml, String tag) {
  final match = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
  return match?.group(1)?.trim();
}

String? _xmlAttr(String xml, String tag, String attr) {
  final match = RegExp('<$tag[^>]*$attr="([^"]*)"').firstMatch(xml);
  return match?.group(1);
}
