import 'dart:io';

import 'package:path/path.dart' as p;

/// Enumerates the local machine's drive roots on Windows (`C:\`, `D:\`, …).
///
/// Off Windows this yields an empty list — the caller simply offers no drive
/// entry, which is correct for POSIX hosts: their filesystem has a single tree
/// reachable by ascending to `/`, and WSL mounts other volumes under `/mnt`.
abstract final class WindowsDriveRoots {
  WindowsDriveRoots._();

  /// Explicit Windows context rather than the ambient one, so a test on any host
  /// gets the same strings.
  static final _windows = p.Context(style: p.Style.windows);

  /// Existing drive roots, in letter order. Each is a root the browser can list
  /// directly (`C:\`), and exactly the form `dirname` returns for its children —
  /// an entry's parent compares equal and the browser stops there.
  ///
  /// A missing drive (`A:\` with no floppy) stats as notFound and is skipped, so
  /// the list holds only volumes the host can actually open.
  static Future<List<String>> list() async {
    if (!Platform.isWindows) return const [];
    final roots = <String>[];
    for (var code = 'A'.codeUnitAt(0); code <= 'Z'.codeUnitAt(0); code++) {
      final root = _windows.normalize('${String.fromCharCode(code)}:/');
      if (await Directory(root).exists()) roots.add(root);
    }
    return roots;
  }
}