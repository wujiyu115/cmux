// Parsed `git blame --incremental` output (see GitService.blameFile).
//
// Mirrors VS Code's `BlameInformation`: one entry per commit with the line
// ranges it owns; uncommitted lines carry the all-zeros hash with
// [isUncommitted] true.

/// Blame of one commit's contribution to a file, at HEAD content.
class GitBlameEntry {
  const GitBlameEntry({
    required this.hash,
    required this.ranges,
    this.authorName,
    this.authorEmail,
    this.authorTime,
    this.subject,
  });

  /// Full commit hash; all zeros for lines not yet committed.
  final String hash;

  /// 1-based, inclusive, ascending line ranges owned by this commit.
  final List<GitBlameLineRange> ranges;

  final String? authorName;
  final String? authorEmail;

  /// Author time in seconds since the Unix epoch (git `author-time`).
  final int? authorTime;

  /// Commit subject (git `summary`).
  final String? subject;

  bool get isUncommitted => hash == GitBlameEntry.uncommittedHash;

  static const String uncommittedHash =
      '0000000000000000000000000000000000000000';

  /// Entry owning [line] (1-based), or null when outside every range.
  GitBlameEntry? forLine(int line) {
    for (final range in ranges) {
      if (line >= range.start && line <= range.end) return this;
    }
    return null;
  }
}

/// 1-based inclusive line range owned by one blame commit.
class GitBlameLineRange {
  const GitBlameLineRange({required this.start, required this.end});

  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is GitBlameLineRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
