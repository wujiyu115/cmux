import 'dart:io';

import '../../utils/workspace/workspace_path_utils.dart';

bool _isWindowsStylePath(String path) =>
    RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path.trim());

/// Formats an absolute path as an `@` reference for terminal image paste.
///
/// Paths under [workspaceRoot] are expressed relative to that root with forward
/// slashes; other paths keep their normalized spelling.
String formatComposeFileReference(
  String absolutePath, {
  required String workspaceRoot,
}) {
  final normalized = normalizeWorkspacePath(absolutePath);
  final root = normalizeWorkspacePath(workspaceRoot);
  if (root.isNotEmpty && _isUnderRoot(normalized, root)) {
    var rel = _stripRootPrefix(normalized, root);
    rel = rel.replaceAll(r'\', '/');
    return '@$rel';
  }
  return '@${normalized.replaceAll(r'\', '/')}';
}

String _pathKey(String path) {
  if (Platform.isWindows || _isWindowsStylePath(path)) {
    return path.toLowerCase();
  }
  return path;
}

String _separatorForPath(String path) {
  if (_isWindowsStylePath(path)) return r'\';
  // Keep POSIX `/` even when the host is Windows (WSL/SSH/test fixtures).
  return '/';
}

String _stripRootPrefix(String path, String root) {
  if (_pathKey(path) == _pathKey(root)) return '';
  final sep = _separatorForPath(path);
  final rootWithSep = root.endsWith('/') || root.endsWith(r'\')
      ? root
      : '$root$sep';
  if (_pathKey(path).startsWith(_pathKey(rootWithSep))) {
    return path.substring(rootWithSep.length);
  }
  var rel = path.substring(root.length);
  if (rel.startsWith('/') || rel.startsWith(r'\')) {
    rel = rel.substring(1);
  }
  return rel;
}

bool _isUnderRoot(String path, String root) {
  if (_pathKey(path) == _pathKey(root)) return true;
  final sep = _separatorForPath(path);
  final rootWithSep = root.endsWith('/') || root.endsWith(r'\')
      ? root
      : '$root$sep';
  return _pathKey(path).startsWith(_pathKey(rootWithSep));
}
