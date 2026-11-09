/// Agent CLI families with a session store on the runtime target that a
/// terminal pane can resume.
enum AgentCliFamily {
  claude,
  qoder,
  codex,
  opencode,
  ohMyPi,
  pi;

  /// Shell command that resumes [sessionId] in a pane running this family's
  /// CLI.
  String resumeCommand(String sessionId) => switch (this) {
    AgentCliFamily.claude => 'claude --resume $sessionId',
    AgentCliFamily.qoder => 'qodercli --resume $sessionId',
    AgentCliFamily.codex => 'codex resume $sessionId',
    AgentCliFamily.opencode => 'opencode --session $sessionId',
    AgentCliFamily.ohMyPi => 'omp --resume $sessionId',
    // `--resume` is a bare picker in pi; an exact session is `--session-id`.
    AgentCliFamily.pi => 'pi --session-id $sessionId',
  };
}

/// One resumable CLI session found on a runtime target.
class AgentCliSessionRecord {
  const AgentCliSessionRecord({
    required this.family,
    required this.sessionId,
    this.title,
    this.updatedAt,
    this.filePath,
  });

  final AgentCliFamily family;
  final String sessionId;
  final String? title;
  final DateTime? updatedAt;

  /// Absolute path of the store file holding this session, on the runtime
  /// target's own filesystem. Null when the adapter could not name it (e.g. an
  /// opencode session whose messages live in a sibling directory).
  final String? filePath;
}

/// Claude/Qoder project-directory rule: every non-alphanumeric char of the
/// cwd becomes `-` (`D:\git\mo_token` → `D--git-mo-token`).
String mungeDirectory(String cwd) =>
    cwd.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-');

/// Extracts the POSIX directory named by a raw OSC 7 payload
/// (`file://host/path`), or null when it is empty, unparseable, or a
/// drive-letter Windows path.
///
/// Unlike `TerminalSessionLinkProviders.parseOsc7Cwd` this never rewrites the
/// path through Windows `toFilePath` semantics, so WSL/SSH panes keep their
/// real `/home/…` form on a Windows host.
String? posixDirectoryFromOsc7(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'file') return null;
  final segments = uri.pathSegments;
  final path = '/${segments.join('/')}';
  if (path == '/' || path == '//') return null;
  // A local Windows pane reports `file:///D:/git/x`; that is not a POSIX
  // directory — let the caller fall back to its Windows-native cwd.
  if (RegExp(r'^/[A-Za-z]:([/$])').hasMatch(path)) return null;
  return path;
}

/// Case- and separator-insensitive directory equality. Session stores record
/// the same directory with varying drive-letter casing and separators.
bool sameCliDirectory(String a, String b) {
  String normalize(String value) => value
      .trim()
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+$'), '')
      .toLowerCase();
  final na = normalize(a);
  return na.isNotEmpty && na == normalize(b);
}
