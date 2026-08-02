/// Characters a POSIX shell leaves alone in a bare word.
///
/// Deliberately ASCII-only and deliberately small: anything outside it gets
/// quoted, so we never have to reason about locale-dependent word splitting or
/// about which shell treats which byte specially.
final _safe = RegExp(r'^[A-Za-z0-9._/-]+$');

/// Renders [path] so a POSIX shell receives it as exactly one argument.
///
/// A path with a space in it is the reason this exists: pasted bare into a
/// terminal, `/Users/me/My Project/photo.jpg` becomes two arguments and the
/// command fails, which makes the whole upload useless on any machine whose
/// paths contain spaces.
///
/// Single quotes are the strong form — inside them nothing is special except
/// the quote itself, which is closed, backslash-escaped, and reopened.
String shellQuotePath(String path) {
  if (path.isNotEmpty && _safe.hasMatch(path)) return path;
  return "'${path.replaceAll("'", r"'\''")}'";
}
