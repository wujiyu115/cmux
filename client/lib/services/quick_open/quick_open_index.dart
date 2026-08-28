import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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

  const QuickOpenIndex.empty()
    : files = const [],
      truncated = false;

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
  QuickOpenIndexRegistry({QuickOpenLister? lister, this.maxFiles = 50000})
    : _listerOverride = lister;

  final QuickOpenLister? _listerOverride;
  final int maxFiles;

  final _indexes = <Object, Future<QuickOpenIndex>>{};
  final _settled = <Object>{};
  final _refreshes = <Future<void>>[];

  Future<QuickOpenIndex> load(Filesystem fs, String root, {int? maxFiles}) {
    if (root.isEmpty) return Future.value(const QuickOpenIndex.empty());
    final key = (fs, root);
    final cached = _indexes[key];
    if (cached != null) {
      // Stale-while-revalidate — but only for a settled entry: while the first
      // listing is still in flight, racing dialogs share it instead of piling
      // on duplicate re-lists.
      if (_settled.contains(key)) {
        final refresh = _listIndex(fs, root, maxFiles ?? this.maxFiles).then((
          index,
        ) {
          _indexes[key] = Future.value(index);
        }).catchError((Object _) {});
        _refreshes.add(refresh);
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

  Future<QuickOpenIndex> _listIndex(
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

  /// Test seam: awaits every background refresh kicked so far.
  @visibleForTesting
  Future<void> drainRefreshesForTest() async {
    final pending = List.of(_refreshes);
    _refreshes.clear();
    await Future.wait(pending);
  }
}
