import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../utils/logging/logger_utils.dart';
import '../git/git_command_runner.dart';
import '../io/filesystem.dart';

/// One indexed file: absolute [path], display basename [name], and
/// [relativePath] from the workspace root (result subtitle).
@immutable
class QuickOpenFileEntry {
  const QuickOpenFileEntry({
    required this.path,
    required this.name,
    required this.relativePath,
  });

  final String path;
  final String name;
  final String relativePath;
}

/// A snapshot of the workspace's openable files.
@immutable
class QuickOpenIndex {
  const QuickOpenIndex({required this.files, required this.truncated});

  const QuickOpenIndex.empty() : files = const [], truncated = false;

  final List<QuickOpenFileEntry> files;

  /// True when the tree had more than the configured cap; surfaced in the UI.
  final bool truncated;
}

/// Directory names whose contents are pure noise for quick-open.
const _ignoredDirNames = {
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

typedef QuickOpenLister = Future<List<FsDirEntry>> Function(String path);

/// Per-(Filesystem, root) index cache with stale-while-revalidate semantics.
///
/// `load` returns the cached index immediately when one exists and kicks a
/// background re-list that replaces the cache entry; a cold root awaits a
/// single shared listing future. The registry deliberately holds *futures*
/// (not indexes) so two dialogs racing the first open share one listing.
///
/// A failed listing is never cached: the entry is removed on error so the
/// next open retries.
class QuickOpenIndexRegistry {
  QuickOpenIndexRegistry({
    QuickOpenLister? lister,
    this.gitRunner,
    this.maxFiles = 50000,
  }) : _listerOverride = lister;

  final QuickOpenLister? _listerOverride;

  /// Work-plane git runner; when set, listings prefer `git ls-files` so
  /// .gitignore rules are honored (nested ignore files, global excludes).
  /// The dialog host updates it as the workspace target resolves; null keeps
  /// the recursive fallback.
  GitCommandRunner? gitRunner;
  final int maxFiles;

  final _indexes = <Object, Future<QuickOpenIndex>>{};
  final _settled = <Object>{};
  final _pendingRefreshes = <Object, Future<QuickOpenIndex?>>{};

  Future<QuickOpenIndex> load(Filesystem fs, String root, {int? maxFiles}) {
    if (root.isEmpty) return Future.value(const QuickOpenIndex.empty());
    final key = (fs, root);
    final cached = _indexes[key];
    if (cached != null) {
      // Stale-while-revalidate — but only for a settled entry: while the first
      // listing is still in flight, racing dialogs share it instead of piling
      // on duplicate re-lists.
      if (_settled.contains(key)) {
        _kickRefresh(fs, root, maxFiles ?? this.maxFiles, key);
      }
      return cached;
    }
    final fresh = _listIndex(fs, root, maxFiles ?? this.maxFiles);
    _indexes[key] = fresh;
    // A failed listing must not poison the cache for the app's lifetime.
    unawaited(
      fresh.then((_) {
        _settled.add(key);
      }, onError: (Object _) {}),
    );
    return fresh.then(
      (index) => index,
      onError: (Object error) {
        _indexes.remove(key);
        _settled.remove(key);
        throw error;
      },
    );
  }

  /// Freshest listing for (fs, root): waits for a revalidation kicked by
  /// [load] when one is still in flight (null when it fails), otherwise
  /// completes with the current cached listing. Lets a long-lived dialog swap
  /// its stale view for the revalidated one without reopening.
  Future<QuickOpenIndex?> latestIndex(Filesystem fs, String root) {
    final pending = _pendingRefreshes[(fs, root)];
    if (pending != null) return pending;
    return _indexes[(fs, root)] ?? Future.value(null);
  }

  /// Kicks a background re-list that replaces the cache entry on success.
  /// A refresh already in flight is reused, so rapid reopens share one
  /// listing instead of stacking duplicates.
  void _kickRefresh(Filesystem fs, String root, int maxFiles, Object key) {
    if (_pendingRefreshes.containsKey(key)) return;
    final refresh = _listIndex(fs, root, maxFiles)
        .then<QuickOpenIndex?>((index) {
          _indexes[key] = Future.value(index);
          return index;
        })
        .catchError((Object _) => null);
    _pendingRefreshes[key] = refresh;
    unawaited(refresh.whenComplete(() => _pendingRefreshes.remove(key)));
  }

  static const List<String> _gitListFilesArgs = [
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
    '-z',
  ];

  Future<QuickOpenIndex> _listIndex(
    Filesystem fs,
    String root,
    int maxFiles,
  ) async {
    final gitIndex = await _listIndexViaGit(fs, root, maxFiles);
    if (gitIndex != null) return gitIndex;
    return _listIndexRecursive(fs, root, maxFiles);
  }

  /// Gitignore-aware source: `git ls-files` over tracked plus untracked,
  /// not-ignored files. Returns null — caller falls back to the recursive
  /// listing — when git cannot serve the root (no repo, git missing on the
  /// target, transport error, or empty output).
  Future<QuickOpenIndex?> _listIndexViaGit(
    Filesystem fs,
    String root,
    int maxFiles,
  ) async {
    final runner = gitRunner;
    if (runner == null) return null;
    final GitCommandResult result;
    try {
      result = await runner.runInDirectory(root, _gitListFilesArgs);
    } on Object catch (e) {
      AppLogger.instance.d('quick-open git ls-files failed: $e');
      return null;
    }
    if (result.exitCode != 0) {
      AppLogger.instance.d(
        'quick-open git ls-files exited ${result.exitCode}: ${result.stderr}',
      );
      return null;
    }
    if (result.stdout.isEmpty) return null;
    final ctx = fs.pathContext;
    final files = <QuickOpenFileEntry>[];
    var truncated = false;
    for (final raw in result.stdout.split('\x00')) {
      if (raw.isEmpty) continue;
      // git always prints POSIX separators; the recursive fallback yields the
      // backend's native ones — normalize so both sources feed identical paths.
      final relative = ctx.joinAll(raw.split('/'));
      files.add(
        QuickOpenFileEntry(
          path: ctx.join(root, relative),
          name: ctx.basename(relative),
          relativePath: relative,
        ),
      );
      if (files.length >= maxFiles) {
        truncated = true;
        break;
      }
    }
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return QuickOpenIndex(files: files, truncated: truncated);
  }

  Future<QuickOpenIndex> _listIndexRecursive(
    Filesystem fs,
    String root,
    int maxFiles,
  ) async {
    final lister = _listerOverride ?? fs.listDirRecursive;
    final entries = await lister(root);
    final ctx = fs.pathContext;
    final files = <QuickOpenFileEntry>[];
    var truncated = false;
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final relative = entry.name;
      if (_isIgnored(relative, ctx)) continue;
      files.add(
        QuickOpenFileEntry(
          path: ctx.join(root, relative),
          name: ctx.basename(relative),
          relativePath: relative,
        ),
      );
      if (files.length >= maxFiles) {
        truncated = true;
        break;
      }
    }
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return QuickOpenIndex(files: files, truncated: truncated);
  }

  /// Drops any path segment that starts with `.` or sits under an ignored
  /// directory. [relative] uses the backend's own separators.
  bool _isIgnored(String relative, p.Context ctx) {
    final segments = ctx.split(relative);
    for (final segment in segments) {
      if (segment.startsWith('.')) return true;
      if (_ignoredDirNames.contains(segment)) return true;
    }
    return false;
  }

  /// Test seam: awaits every background refresh still in flight.
  @visibleForTesting
  Future<void> drainRefreshesForTest() async {
    await Future.wait(List.of(_pendingRefreshes.values));
  }
}

/// Normalizes candidate quick-open roots: drops empty entries and duplicates,
/// then drops any root nested inside another kept root so a session cwd inside
/// a workspace folder does not double-list its files. Order is preserved —
/// the first root is the primary one (its entries render unprefixed).
List<String> normalizeQuickOpenRoots(List<String> roots, p.Context ctx) {
  final kept = <String>[];
  for (final raw in roots) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    final path = ctx.normalize(trimmed);
    if (kept.contains(path)) continue;
    if (kept.any((k) => ctx.isWithin(k, path))) continue;
    kept.removeWhere((k) => ctx.isWithin(path, k));
    kept.add(path);
  }
  return kept;
}

/// Merges per-root indexes into one launcher index. Entries under the primary
/// root (first of [roots]) keep their root-relative path; entries from other
/// roots are prefixed with the root's basename so same-named files stay
/// distinguishable (VS Code multi-root style). [indexesByRoot] is keyed by the
/// normalized root path.
QuickOpenIndex mergeQuickOpenIndexes({
  required List<String> roots,
  required Map<String, QuickOpenIndex> indexesByRoot,
  required p.Context ctx,
}) {
  if (roots.isEmpty) return const QuickOpenIndex.empty();
  final files = <QuickOpenFileEntry>[];
  var truncated = false;
  for (var i = 0; i < roots.length; i++) {
    final root = roots[i];
    final index = indexesByRoot[root];
    if (index == null) continue;
    truncated = truncated || index.truncated;
    if (i == 0) {
      files.addAll(index.files);
      continue;
    }
    final prefix = ctx.basename(root);
    files.addAll([
      for (final entry in index.files)
        QuickOpenFileEntry(
          path: entry.path,
          name: entry.name,
          relativePath: ctx.join(prefix, entry.relativePath),
        ),
    ]);
  }
  files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  return QuickOpenIndex(files: files, truncated: truncated);
}
