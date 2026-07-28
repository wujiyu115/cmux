/// Strips credentials out of command lines before they reach the command log.
///
/// The log is written to disk and shown in a searchable window, so anything that
/// looks like a secret has to be neutralised at the boundary. Ported from cmux's
/// `CommandLogService` sanitizer, plus a `LooksLikeSecretInput` net for the case
/// where a password prompt echoes the typed value as a lone token.
abstract final class CommandSecretRedactor {
  /// Marker left in place of the removed value.
  static const String redacted = '[REDACTED]';

  /// Commands longer than this are truncated; a log row is not a transcript.
  static const int maxCommandChars = 4096;

  /// `MY_API_KEY=hunter2`, `PASSWORD="x y"`.
  static final RegExp _envAssignment = RegExp(
    r'(\b[A-Za-z0-9_]*(?:PASSWORD|PASSWD|TOKEN|SECRET|API_KEY|ACCESS_KEY)[A-Za-z0-9_]*\s*=\s*)'
    '''("[^"\\r\\n]*"|'[^'\\r\\n]*'|[^\\s\\r\\n]+)''',
    caseSensitive: false,
  );

  /// `--password hunter2`, `--api-key=hunter2`, `-token hunter2`.
  static final RegExp _secretFlag = RegExp(
    r'(--(?:password|passwd|pwd|token|secret|api[-_]?key|access[-_]?key)(?:\s+|=)'
    r'|-(?:password|passwd|pwd|token|secret)(?:\s+|=))'
    '''("[^"\\r\\n]*"|'[^'\\r\\n]*'|[^\\s\\r\\n]+)''',
    caseSensitive: false,
  );

  /// `https://user:hunter2@host`.
  static final RegExp _uriCredentials = RegExp(
    r'([a-z][a-z0-9+\-.]*://[^\s/@:]+:)([^@\s]+)(@)',
    caseSensitive: false,
  );

  /// Well-known bare commands that must never be mistaken for a secret token.
  static const Set<String> _safeBareCommands = {
    'ls', 'cd', 'pwd', 'git', 'npm', 'pnpm', 'yarn', 'dotnet', 'python',
    'python3', 'node', 'bash', 'zsh', 'fish', 'nu', 'vi', 'vim', 'nvim',
    'nano', 'code', 'cargo', 'go', 'java', 'kubectl', 'docker', 'flutter',
    'dart', 'make', 'cmake', 'top', 'htop', 'clear', 'exit', 'history',
  };

  /// Redacted command, or null when the whole line looks like a typed secret and
  /// must not be logged at all.
  static String? sanitize(String? command) {
    final trimmed = command?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (looksLikeSecretInput(trimmed)) return null;

    var out = trimmed
        .replaceAllMapped(_envAssignment, (m) => '${m[1]}$redacted')
        .replaceAllMapped(_secretFlag, (m) => '${m[1]}$redacted')
        .replaceAllMapped(_uriCredentials, (m) => '${m[1]}$redacted${m[3]}');
    if (out.length > maxCommandChars) {
      out = out.substring(0, maxCommandChars);
    }
    return out;
  }

  /// Heuristic for "this is not a command, it is the password someone typed".
  /// A single opaque token with mixed classes and no path-ish shape.
  static bool looksLikeSecretInput(String value) {
    if (value.isEmpty) return false;
    if (value.contains(' ')) return false;
    if (value.contains('/') || value.contains(r'\') || value.startsWith('.')) {
      return false;
    }
    final lower = value.toLowerCase();
    if (_safeBareCommands.contains(lower)) return false;
    if (lower.contains('password') ||
        lower.contains('passwd') ||
        lower.contains('token') ||
        lower.contains('secret')) {
      return true;
    }
    final hasLetter = value.contains(RegExp('[A-Za-z]'));
    final hasDigit = value.contains(RegExp('[0-9]'));
    final hasSpecial = value.contains(RegExp(r'[^A-Za-z0-9]'));
    return value.length >= 6 && hasLetter && (hasDigit || hasSpecial);
  }
}
