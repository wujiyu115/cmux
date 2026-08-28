# Quick Open (Ctrl+P) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind Ctrl+P to a VS Code-style fuzzy filename quick-open dialog for the active workspace, with a stale-while-revalidate in-memory index and a persistent recently-opened list.

**Architecture:** A `QuickOpenHost` (clone of `WorkspaceSearchHost`) binds the active workspace pane; Ctrl+P invokes it on the CommandBus. The dialog indexes the workspace root once per open via the existing batched `Filesystem.listDirRecursive`, caches the shared listing future per (fs, root) and revalidates in the background on cache hits. Fuzzy scoring is extracted from the command palette into a shared util. Selecting a file opens it through `WorkbenchEditorOpener.openFile` in preview mode.

**Tech Stack:** Flutter (package `teampilot` under `client/`), flutter_bloc, shared_ui `Tp*` components, `VersionedJsonStore` persistence. Tests via `flutter_test` with `InMemoryFilesystem`.

**Spec:** `docs/superpowers/specs/2026-08-28-quick-open-design.md`

**Conventions:** All flutter commands run from `D:\git\teampilot\client`. All user-facing strings MUST be added to both `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb` before use; after ARB changes run `dart run tool/gen_warmup_glyphs.dart`. Tests mock the filesystem via constructor injection — never touch real disk. Verification gate per task: the task's own tests green; final gate: `flutter analyze --no-fatal-infos --no-fatal-warnings` (baseline: 49 pre-existing infos) and `flutter test --exclude-tags integration` (baseline: 2809 passing).

---

### Task 1: Shared fuzzy-match util (extract from command palette)

**Files:**
- Create: `client/lib/utils/commands/fuzzy_match.dart`
- Modify: `client/lib/utils/commands/command_palette_filter.dart`
- Test: `client/test/utils/commands/fuzzy_match_test.dart`
- Test (regression, no edits): `client/test/utils/commands/command_palette_filter_test.dart` must stay green untouched.

- [ ] **Step 1: Write the failing test**

Create `client/test/utils/commands/fuzzy_match_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/commands/fuzzy_match.dart';

void main() {
  group('fuzzyMatch', () {
    test('subsequence matches with highlight indexes', () {
      final match = fuzzyMatch('main_file_search.dart', 'mfs');
      expect(match, isNotNull);
      // 'm' at 0, 'f' at 5 (first 'f' in 'file'), 's' at 10 (first 's').
      expect(match!.indexes, [0, 5, 10]);
    });

    test('returns null when not a subsequence', () {
      expect(fuzzyMatch('terminal', 'zzz'), isNull);
    });

    test('word-start beats mid-word: higher score', () {
      final wordStart = fuzzyMatch('file_search', 'fs');
      final midWord = fuzzyMatch('xfile_search', 'fs');
      expect(wordStart!.score, greaterThan(midWord!.score));
    });

    test('contiguous run beats sparse: higher score', () {
      final contiguous = fuzzyMatch('abc', 'bc');
      final sparse = fuzzyMatch('a_b_c', 'bc');
      expect(contiguous!.score, greaterThan(sparse!.score));
    });

    test('case-insensitive', () {
      expect(fuzzyMatch('Terminal', 'trm'), isNotNull);
    });

    test('empty query matches with empty indexes and zero score', () {
      final match = fuzzyMatch('anything', '');
      expect(match!.indexes, isEmpty);
      expect(match.score, 0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/utils/commands/fuzzy_match_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'teampilot/utils/commands/fuzzy_match.dart'` (file does not exist).

- [ ] **Step 3: Create the shared util**

Create `client/lib/utils/commands/fuzzy_match.dart` — move `_SubsequenceMatch`, `_subsequenceMatch`, `_isWordStart` from `command_palette_filter.dart` verbatim, renaming only for public visibility:

```dart
/// Result of [fuzzyMatch]: matched indexes into the target (for highlighting)
/// and a relative score (higher = better). Empty indexes / score 0 for an
/// empty query.
class FuzzyMatch {
  const FuzzyMatch(this.indexes, this.score);
  final List<int> indexes;
  final int score;
}

/// Greedy leftmost subsequence match of [lowerQuery] against [target]
/// (case-insensitive). Returns matched indexes into [target] and a score, or
/// `null` when [lowerQuery] is not a subsequence.
///
/// Scoring: per-char base credit, contiguous-run bonus, word-start bonus
/// (start of string, after a non-alphanumeric, or a lower→Upper camelCase
/// boundary), and an earlier-first-match bonus. Shared by the command palette
/// and quick-open so both rank and highlight identically.
FuzzyMatch? fuzzyMatch(String target, String lowerQuery) {
  if (lowerQuery.isEmpty) {
    return const FuzzyMatch([], 0);
  }
  final lowerTarget = target.toLowerCase();
  final indexes = <int>[];
  var t = 0;
  for (var q = 0; q < lowerQuery.length; q++) {
    final ch = lowerQuery.codeUnitAt(q);
    var found = -1;
    while (t < lowerTarget.length) {
      if (lowerTarget.codeUnitAt(t) == ch) {
        found = t;
        t++;
        break;
      }
      t++;
    }
    if (found < 0) return null;
    indexes.add(found);
  }

  var score = 0;
  var previous = -2;
  for (final index in indexes) {
    score += 1;
    if (index == previous + 1) score += 6;
    if (_isWordStart(target, index)) score += 10;
    previous = index;
  }
  score -= indexes.first;
  return FuzzyMatch(indexes, score);
}

bool _isWordStart(String target, int index) {
  if (index == 0) return true;
  final prev = target.codeUnitAt(index - 1);
  final isPrevAlnum =
      (prev >= 0x30 && prev <= 0x39) ||
      (prev >= 0x41 && prev <= 0x5A) ||
      (prev >= 0x61 && prev <= 0x7A);
  if (!isPrevAlnum) return true;
  final cur = target.codeUnitAt(index);
  final prevIsLower = prev >= 0x61 && prev <= 0x7A;
  final curIsUpper = cur >= 0x41 && cur <= 0x5A;
  return prevIsLower && curIsUpper;
}
```

- [ ] **Step 4: Point the command palette at it**

In `client/lib/utils/commands/command_palette_filter.dart`:
1. Add import: `import 'fuzzy_match.dart';`
2. Delete the `class _SubsequenceMatch`, `_subsequenceMatch`, and `_isWordStart` definitions (lines ~122-180).
3. In `filterCommandPalette`, replace both `_subsequenceMatch(...)` call sites:

```dart
    final match = fuzzyMatch(title, lowerQuery);
    if (match != null) {
      results.add(
        CommandPaletteMatch(
          command: def,
          title: title,
          matchedIndexes: match.indexes,
          score: match.score,
        ),
      );
      continue;
    }
```

and in the category fallback:

```dart
      final catMatch = fuzzyMatch(haystack, lowerQuery);
      if (catMatch != null) {
        results.add(
          CommandPaletteMatch(
            command: def,
            title: title,
            matchedIndexes: const [],
            score: catMatch.score - 1000,
          ),
        );
      }
```

Also delete the now-dead `if (trimmed.isEmpty)` early-return's duplication if any references remain — there are none; the empty-query branch already returns before matching.

- [ ] **Step 5: Run both test files**

Run: `cd client && flutter test test/utils/commands/fuzzy_match_test.dart test/utils/commands/command_palette_filter_test.dart`
Expected: PASS (all fuzzy tests + every pre-existing palette-filter test untouched).

- [ ] **Step 6: Commit**

```bash
git add client/lib/utils/commands/fuzzy_match.dart client/lib/utils/commands/command_palette_filter.dart client/test/utils/commands/fuzzy_match_test.dart
git commit -m "refactor(commands): extract shared subsequence fuzzy matcher from the command palette"
```

---

### Task 2: Quick-open index with stale-while-revalidate registry

**Files:**
- Create: `client/lib/services/quick_open/quick_open_index.dart`
- Test: `client/test/services/quick_open/quick_open_index_test.dart`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/quick_open/quick_open_index_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/quick_open/quick_open_index.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
    for (final dir in [
      '/repo',
      '/repo/lib',
      '/repo/lib/src',
      '/repo/.git',
      '/repo/node_modules/pkg',
      '/repo/build',
    ]) {
      fs.ensureDir(dir);
    }
    for (final file in [
      '/repo/README.md',
      '/repo/lib/main.dart',
      '/repo/lib/src/terminal_session.dart',
      '/repo/.git/config',
      '/repo/node_modules/pkg/index.js',
      '/repo/build/app.exe',
      '/repo/.hidden.txt',
      '/repo/lib/.secret.dart',
    ]) {
      fs.files[file] = 'x';
    }
  });

  test('lists files, skipping ignored dirs and hidden entries', () async {
    final registry = QuickOpenIndexRegistry();
    final index = await registry.load(fs, '/repo');
    expect(
      index.files.map((e) => e.relativePath).toList(),
      allOf([
        contains('README.md'),
        contains('lib/main.dart'),
        contains('lib/src/terminal_session.dart'),
      ]),
    );
    for (final path in index.files.map((e) => e.relativePath)) {
      expect(path.startsWith('.'), isFalse);
      expect(path.contains('/.'), isFalse);
      expect(path.startsWith('node_modules/'), isFalse);
      expect(path.startsWith('build/'), isFalse);
    }
  });

  test('entry fields: absolute path, basename, relative path', () async {
    final registry = QuickOpenIndexRegistry();
    final index = await registry.load(fs, '/repo');
    final entry = index.files.firstWhere(
      (e) => e.relativePath == 'lib/main.dart',
    );
    expect(entry.path, '/repo/lib/main.dart');
    expect(entry.name, 'main.dart');
  });

  test('cap: index truncated beyond maxFiles', () async {
    for (var i = 0; i < 10; i++) {
      fs.files['/repo/file$i.txt'] = 'x';
    }
    final registry = QuickOpenIndexRegistry();
    final index = await registry.load(fs, '/repo', maxFiles: 5);
    expect(index.files.length, 5);
    expect(index.truncated, isTrue);
  });

  test('same (fs, root) shares one listing future', () async {
    var listings = 0;
    final registry = QuickOpenIndexRegistry(
      lister: (path) {
        listings++;
        return fs.listDirRecursive(path);
      },
    );
    final a = registry.load(fs, '/repo');
    final b = registry.load(fs, '/repo');
    await Future.wait([a, b]);
    expect(listings, 1);
  });

  test('cache hit returns immediately; background refresh replaces entry',
      () async {
    final registry = QuickOpenIndexRegistry();
    final first = await registry.load(fs, '/repo');
    expect(first.files.map((e) => e.name), contains('main.dart'));

    fs.files['/repo/new_file.md'] = 'x';
    final second = await registry.load(fs, '/repo');
    // Cache hit: stale view (no new_file yet)…
    expect(
      second.files.map((e) => e.name),
      isNot(contains('new_file.md')),
    );
    // …but a refresh was kicked; after it drains the next load sees the file.
    await registry.drainRefreshesForTest();
    final third = await registry.load(fs, '/repo');
    expect(third.files.map((e) => e.name), contains('new_file.md'));
  });

  test('different root loads separately', () async {
    fs.ensureDir('/other');
    fs.files['/other/x.txt'] = 'x';
    final registry = QuickOpenIndexRegistry();
    final repo = await registry.load(fs, '/repo');
    final other = await registry.load(fs, '/other');
    expect(repo.files.map((e) => e.relativePath), contains('README.md'));
    expect(other.files.map((e) => e.relativePath), ['x.txt']);
  });

  test('listing failure is not cached: next load retries', () async {
    var fail = true;
    final registry = QuickOpenIndexRegistry(
      lister: (path) {
        if (fail) throw StateError('boom');
        return fs.listDirRecursive(path);
      },
    );
    await expectLater(registry.load(fs, '/repo'), throwsStateError);
    fail = false;
    final index = await registry.load(fs, '/repo');
    expect(index.files, isNotEmpty);
  });
}
```

The registry takes an injectable `QuickOpenLister` function (defaulting to `fs.listDirRecursive`) so these tests use plain closures — no filesystem doubles needed.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/quick_open/quick_open_index_test.dart`
Expected: FAIL — cannot resolve `package:teampilot/services/quick_open/quick_open_index.dart`.

- [ ] **Step 3: Implement the index and registry**

Create `client/lib/services/quick_open/quick_open_index.dart`:

```dart
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
  QuickOpenIndexRegistry({
    QuickOpenLister? lister,
    this.maxFiles = 50000,
  }) : _listerOverride = lister;

  static const int defaultMaxFiles = 50000;

  final QuickOpenLister? _listerOverride;
  final int maxFiles;

  final _indexes = <Object, Future<QuickOpenIndex>>{};
  final _refreshes = <Future<void>>[];

  Future<QuickOpenIndex> load(Filesystem fs, String root) {
    if (root.isEmpty) return Future.value(const QuickOpenIndex.empty());
    final key = (fs, root);
    final cached = _indexes[key];
    if (cached != null) {
      // Stale-while-revalidate: serve the cache, replace it in the background.
      final refresh = _listIndex(fs, root).then((index) {
        _indexes[key] = Future.value(index);
      }).catchError((Object _) {});
      _refreshes.add(refresh);
      return cached;
    }
    final fresh = _listIndex(fs, root);
    _indexes[key] = fresh;
    // A failed listing must not poison the cache for the app's lifetime.
    unawaited(fresh.then((_) {}, onError: (Object _) {}));
    return fresh.then(
      (index) => index,
      onError: (Object error) {
        _indexes.remove(key);
        throw error;
      },
    );
  }

  Future<QuickOpenIndex> _listIndex(Filesystem fs, String root) async {
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
```

- [ ] **Step 4: Run the tests**

Run: `cd client && flutter test test/services/quick_open/quick_open_index_test.dart`
Expected: PASS (all 7 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/quick_open/quick_open_index.dart client/test/services/quick_open/quick_open_index_test.dart
git commit -m "feat(quick-open): workspace file index with stale-while-revalidate cache"
```

---

### Task 3: Quick-open MRU repository

**Files:**
- Create: `client/lib/services/quick_open/quick_open_mru_repository.dart`
- Test: `client/test/services/quick_open/quick_open_mru_repository_test.dart`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/quick_open/quick_open_mru_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/quick_open/quick_open_mru_repository.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late QuickOpenMruRepository repo;

  setUp(() {
    fs = InMemoryFilesystem();
    repo = QuickOpenMruRepository(fs: fs, path: '/quick-open-mru.json');
  });

  test('empty store loads empty list', () async {
    expect(await repo.load('/repo'), isEmpty);
  });

  test('touch moves to front and persists', () async {
    await repo.touch('/repo', '/repo/a.dart');
    await repo.touch('/repo', '/repo/b.dart');
    await repo.touch('/repo', '/repo/a.dart');
    expect(await repo.load('/repo'), ['/repo/a.dart', '/repo/b.dart']);
  });

  test('cap: oldest entries fall off', () async {
    for (var i = 0; i < QuickOpenMruRepository.cap + 5; i++) {
      await repo.touch('/repo', '/repo/file$i.dart');
    }
    final loaded = await repo.load('/repo');
    expect(loaded.length, QuickOpenMruRepository.cap);
    // Most recent touched is first.
    expect(loaded.first, '/repo/file${QuickOpenMruRepository.cap + 4}.dart');
  });

  test('roots are isolated from each other', () async {
    await repo.touch('/repo-a', '/repo-a/x.dart');
    await repo.touch('/repo-b', '/repo-b/y.dart');
    expect(await repo.load('/repo-a'), ['/repo-a/x.dart']);
    expect(await repo.load('/repo-b'), ['/repo-b/y.dart']);
  });

  test('missing files are dropped on load', () async {
    fs.files['/quick-open-mru.json'] = '''
{"version":1,"data":{"roots":{"/repo":["/repo/gone.dart","/repo/here.dart"]}}}
''';
    fs.ensureDir('/repo');
    fs.files['/repo/here.dart'] = 'x';
    expect(await repo.load('/repo'), ['/repo/here.dart']);
  });

  test('corrupt file yields empty list, never throws', () async {
    fs.files['/quick-open-mru.json'] = 'not json at all';
    expect(await repo.load('/repo'), isEmpty);
  });
}
```

Note: "missing files are dropped on load" requires an existence check against the filesystem. Stat each path via `fs.stat` and keep only existing files — matches the spec's "empty MRU → hint row" freshness guarantee.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/quick_open/quick_open_mru_repository_test.dart`
Expected: FAIL — cannot resolve `quick_open_mru_repository.dart`.

- [ ] **Step 3: Implement the repository**

Create `client/lib/services/quick_open/quick_open_mru_repository.dart`, modeled on `CommandMruRepository` (`client/lib/repositories/command_mru_repository.dart`):

```dart
import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import '../io/versioned_json_store.dart';
import '../storage/app_storage.dart';
import '../../utils/logging/logger.dart';

/// Persists per-root recently-opened file paths at
/// `{appDataRoot}/quick-open-mru.json` through a [VersionedJsonStore].
///
/// On-disk envelope: `{"version":1,"data":{"roots":{"<root>":[<path>...]}}}`,
/// most-recent first. [load] drops files that no longer exist on disk so the
/// empty-query list never offers dead entries. Never throws.
class QuickOpenMruRepository {
  QuickOpenMruRepository({Filesystem? fs, String? path})
    : _fsOverride = fs,
      _pathOverride = path;

  static const int cap = 50;
  static const int _version = 1;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? p.join(AppStorage.appDataRoot, 'quick-open-mru.json');

  VersionedJsonStore<Map<String, List<String>>> _store() {
    return VersionedJsonStore<Map<String, List<String>>>(
      fs: _fs,
      path: _path,
      currentVersion: _version,
      decode: (data) {
        final roots = data['roots'];
        if (roots is! Map) return {};
        return {
          for (final entry in roots.entries)
            if (entry.key is String && entry.value is List)
              entry.key as String: (entry.value as List)
                  .whereType<String>()
                  .toList(growable: false),
        };
      },
      encode: (value) => {
        'roots': {for (final e in value.entries) e.key: e.value},
      },
    );
  }

  Future<Map<String, List<String>>> _loadRaw() async {
    try {
      final result = await _store().read();
      return result.data ?? {};
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[quick-open-mru] load failed, resetting',
        error: error,
        stackTrace: stackTrace,
      );
      return {};
    }
  }

  /// Most-recent-first existing files for [root]; dead paths dropped.
  Future<List<String>> load(String root) async {
    final raw = await _loadRaw();
    final paths = raw[root];
    if (paths == null || paths.isEmpty) return const [];
    final fs = _fs;
    final existing = <String>[];
    for (final path in paths) {
      if (existing.length >= cap) break;
      final stat = await fs.stat(path);
      if (!stat.exists) continue;
      if (existing.contains(path)) continue;
      existing.add(path);
    }
    return existing;
  }

  /// Records [path] as most-recent for [root], clamped to [cap].
  Future<void> touch(String root, String path) async {
    try {
      final raw = await _loadRaw();
      final current = raw[root] ?? const <String>[];
      final next = <String>[
        path,
        for (final existing in current)
          if (existing != path) existing,
      ];
      final clamped = next.length > cap ? next.sublist(0, cap) : next;
      await _store().write({...raw, root: clamped});
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[quick-open-mru] touch failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd client && flutter test test/services/quick_open/quick_open_mru_repository_test.dart`
Expected: PASS (6 tests). The corrupt-file test needs the store's quarantine path (it renames the bad file) — `InMemoryFilesystem.rename` must support it; it does.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/quick_open/quick_open_mru_repository.dart client/test/services/quick_open/quick_open_mru_repository_test.dart
git commit -m "feat(quick-open): per-root recently-opened MRU store"
```

---

### Task 4: l10n strings + command registration (Ctrl+P)

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/l10n/app_localizations_en.dart` / `app_localizations_zh.dart` / `app_localizations.dart` (generated — run `flutter gen-l10n` via build or the tool below)
- Modify: `client/lib/services/commands/command_ids.dart`
- Modify: `client/lib/services/commands/command_catalog.dart`
- Modify: `client/lib/services/commands/command_l10n.dart`
- Test: `client/test/services/commands/command_catalog_test.dart` (extend if a catalog-completeness test exists; otherwise verify via compile)

- [ ] **Step 1: Add ARB keys**

In `client/lib/l10n/app_en.arb`, near the other `shortcuts*` keys:

```json
  "shortcutsQuickOpen": "Quick Open File",
  "quickOpenSearchHint": "Type a file name…",
  "quickOpenIndexing": "Indexing files…",
  "quickOpenRecent": "Recently opened",
  "quickOpenEmptyRecent": "Start typing to search files",
  "quickOpenNoResults": "No matching files",
  "quickOpenTruncated": "Large workspace — showing the first {count} files",
  "@quickOpenTruncated": {
    "placeholders": {
      "count": {}
    }
  },
```

In `client/lib/l10n/app_zh.arb` (same keys, Chinese, same `@quickOpenTruncated` placeholder metadata):

```json
  "shortcutsQuickOpen": "快速打开文件",
  "quickOpenSearchHint": "输入文件名…",
  "quickOpenIndexing": "正在索引文件…",
  "quickOpenRecent": "最近打开",
  "quickOpenEmptyRecent": "输入文件名开始搜索",
  "quickOpenNoResults": "没有匹配的文件",
  "quickOpenTruncated": "工作区较大 — 仅显示前 {count} 个文件",
  "@quickOpenTruncated": {
    "placeholders": {
      "count": {}
    }
  },
```

- [ ] **Step 2: Regenerate localizations and glyph warmup**

Run: `cd client && flutter gen-l10n && dart run tool/gen_warmup_glyphs.dart`
Expected: `app_localizations*.dart` regenerated with the new getters (check `String get shortcutsQuickOpen;` and `String quickOpenTruncated(int count);` appear in `app_localizations.dart`).

- [ ] **Step 3: Write the failing catalog assertion**

Add to `client/test/services/commands/command_catalog_test.dart` (create the file if absent):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/command_definition.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/key_chord.dart';

void main() {
  test('quickOpen command is registered with Mod+P', () {
    final def = CommandCatalog.v1.firstWhere(
      (d) => d.id == CommandIds.quickOpen,
    );
    expect(def.defaultChords, [
      const KeyChord(key: 'p', mods: [KeyChordMod.mod]),
    ]);
    expect(def.when, ShortcutWhen.hasWorkspace);
    expect(def.terminalPassthrough, isTrue);
    expect(def.titleL10nKey, 'shortcutsQuickOpen');
  });
}
```

Match the real `CommandDefinition` field names — read `client/lib/services/commands/command_definition.dart` first and adjust assertions to actual API (`when` may be typed as a function/enum; keep the assertions to fields that exist).

- [ ] **Step 4: Run to verify it fails**

Run: `cd client && flutter test test/services/commands/command_catalog_test.dart`
Expected: FAIL — `CommandIds.quickOpen` unresolved.

- [ ] **Step 5: Register the command**

In `client/lib/services/commands/command_ids.dart`, after `workspaceSearch`:

```dart
  static const String quickOpen = 'workbench.quickOpen';
```

In `client/lib/services/commands/command_catalog.dart`, right after the `workspaceSearch` definition (line ~71):

```dart
    CommandDefinition(
      id: CommandIds.quickOpen,
      category: CommandCategory.navigation,
      defaultChords: [
        KeyChord(key: 'p', mods: [KeyChordMod.mod]),
      ],
      when: ShortcutWhen.hasWorkspace,
      terminalPassthrough: true,
      titleL10nKey: 'shortcutsQuickOpen',
    ),
```

In `client/lib/services/commands/command_l10n.dart`, in `_titleForKey`:

```dart
    'shortcutsQuickOpen' => l10n.shortcutsQuickOpen,
```

- [ ] **Step 6: Run the catalog test**

Run: `cd client && flutter test test/services/commands/command_catalog_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/l10n client/lib/services/commands client/test/services/commands/command_catalog_test.dart
git commit -m "feat(quick-open): register Ctrl+P quick-open command with l10n"
```

---

### Task 5: QuickOpenHost + command wiring

**Files:**
- Create: `client/lib/services/commands/quick_open_command_registrar.dart`
- Modify: `client/lib/app/app_shell.dart` (~line 455, beside `workspaceSearchHost`)
- Modify: `client/lib/main.dart` (~line 766, beside `WorkspaceSearchHost` provider)
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` (bind/unbind)
- Test: `client/test/services/commands/quick_open_command_registrar_test.dart`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/commands/quick_open_command_registrar_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/quick_open_command_registrar.dart';

void main() {
  test('open invokes the bound opener', () {
    final bus = CommandBus();
    final host = QuickOpenHost();
    registerQuickOpenCommands(bus, host);

    var opened = 0;
    host.bind(() => opened++);
    bus.invoke(CommandIds.quickOpen);
    expect(opened, 1);
  });

  test('unbind stops invocation', () {
    final bus = CommandBus();
    final host = QuickOpenHost();
    registerQuickOpenCommands(bus, host);

    var opened = 0;
    void opener() => opened++;
    host.bind(opener);
    host.unbind(opener);
    bus.invoke(CommandIds.quickOpen);
    expect(opened, 0);
  });

  test('no opener bound is a silent no-op', () {
    final bus = CommandBus();
    final host = QuickOpenHost();
    registerQuickOpenCommands(bus, host);
    bus.invoke(CommandIds.quickOpen); // must not throw
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/commands/quick_open_command_registrar_test.dart`
Expected: FAIL — package unresolved.

- [ ] **Step 3: Implement the registrar**

Create `client/lib/services/commands/quick_open_command_registrar.dart` (mirror of `workspace_search_command_registrar.dart`):

```dart
import 'command_bus.dart';
import 'command_ids.dart';

/// Holds the foreground quick-open opener for the Ctrl+P shortcut.
///
/// Kept-alive workspace tabs bind/unbind when their route becomes
/// active/inactive (see [WorkspaceSplitPane]).
class QuickOpenHost {
  void Function()? _openQuickOpen;

  void bind(void Function() openQuickOpen) => _openQuickOpen = openQuickOpen;

  void unbind(void Function() openQuickOpen) {
    if (identical(_openQuickOpen, openQuickOpen)) _openQuickOpen = null;
  }

  void clear() => _openQuickOpen = null;

  void open() => _openQuickOpen?.call();
}

/// Wires [CommandIds.quickOpen] onto [bus] against [host].
///
/// Call once during app bootstrap (see `buildAppShell`).
void registerQuickOpenCommands(CommandBus bus, QuickOpenHost host) {
  bus.register(CommandIds.quickOpen, () => host.open());
}
```

- [ ] **Step 4: Run the test**

Run: `cd client && flutter test test/services/commands/quick_open_command_registrar_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Wire into app_shell.dart**

In `client/lib/app/app_shell.dart`:
1. Import: `import '../services/commands/quick_open_command_registrar.dart';` (match the existing import style for `workspace_search_command_registrar.dart`).
2. Field on the shell class (~line 182, beside `workspaceSearchHost`): add `required this.quickOpenHost,` to the constructor params and `final QuickOpenHost quickOpenHost;` beside `final WorkspaceSearchHost workspaceSearchHost;`.
3. Instance (~line 455): `final quickOpenHost = QuickOpenHost();`
4. Registration (~line 460, beside `registerWorkspaceSearchCommands`): `registerQuickOpenCommands(commandBus, quickOpenHost);`
5. Pass-through at the `buildAppShell` return (~line 1266, beside `workspaceSearchHost: workspaceSearchHost`): `quickOpenHost: quickOpenHost,`

- [ ] **Step 6: Provide in main.dart**

In `client/lib/main.dart` (~line 766), add beside the `WorkspaceSearchHost` provider:

```dart
                RepositoryProvider<QuickOpenHost>.value(
                  value: shell.quickOpenHost,
                ),
```

and the matching import `import 'services/commands/quick_open_command_registrar.dart';` (match existing import grouping).

- [ ] **Step 7: WorkspaceSplitPane binding — deferred to Task 6**

The `WorkspaceSplitPane` bind/unbind plumbing (host field, `_syncQuickOpenHost`, `_openQuickOpenNow` calling `showQuickOpenDialog`) is implemented in **Task 6 Step 4** together with the dialog it opens — wiring an opener before `showQuickOpenDialog` exists would require a forbidden placeholder. This task wires only the registrar + app_shell + main.dart.

- [ ] **Step 8: Verify compile**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/app/app_shell.dart lib/main.dart`
Expected: No new issues (49-info baseline applies to the whole repo; per-file output should show none beyond pre-existing).

- [ ] **Step 9: Commit**

```bash
git add client/lib/services/commands/quick_open_command_registrar.dart client/lib/app/app_shell.dart client/lib/main.dart client/test/services/commands/quick_open_command_registrar_test.dart
git commit -m "feat(quick-open): QuickOpenHost bound to the Ctrl+P command"
```

---

### Task 6: Quick-open dialog UI

**Files:**
- Create: `client/lib/pages/quick_open/quick_open_overlay.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` (bind + opener)
- Test: `client/test/pages/quick_open/quick_open_overlay_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `client/test/pages/quick_open/quick_open_overlay_test.dart`. Model the harness on `client/test/pages/command_palette/command_palette_overlay_test.dart` (TpTheme + localized MaterialApp), with an `InMemoryFilesystem` seeded workspace and injected registry/MRU:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/quick_open/quick_open_overlay.dart';
import 'package:teampilot/services/quick_open/quick_open_index.dart';
import 'package:teampilot/services/quick_open/quick_open_mru_repository.dart';

import '../../support/in_memory_filesystem.dart';

Widget _wrap(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return TpTheme(
    data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: theme,
      home: Scaffold(body: child),
    ),
  );
}

Workspace _workspace() => Workspace(
  workspaceId: 'w1',
  folders: [WorkspaceFolder(path: '/repo')],
  createdAt: 0,
);

// WorkspaceFolder import — check client/lib/models/workspace_folder.dart for
// the exact constructor (it may take a named `path` only).

InMemoryFilesystem _fs() {
  final fs = InMemoryFilesystem();
  fs.ensureDir('/repo/lib');
  fs.files['/repo/lib/main.dart'] = 'x';
  fs.files['/repo/lib/terminal_session.dart'] = 'x';
  fs.files['/repo/README.md'] = 'x';
  return fs;
}

void main() {
  testWidgets('empty query shows recent files', (tester) async {
    final fs = _fs();
    final mru = QuickOpenMruRepository(fs: fs, path: '/mru.json');
    await mru.touch('/repo', '/repo/lib/main.dart');

    await tester.pumpWidget(
      _wrap(
        QuickOpenOverlay(
          workspace: _workspace(),
          filesystem: fs,
          indexRegistry: QuickOpenIndexRegistry(),
          mruRepository: mru,
          onOpenFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recently opened'), findsOneWidget);
    expect(find.text('main.dart'), findsWidgets);
  });

  testWidgets('typing filters by fuzzy match and Enter opens the file', (
    tester,
  ) async {
    final fs = _fs();
    var openedPath = '';
    await tester.pumpWidget(
      _wrap(
        QuickOpenOverlay(
          workspace: _workspace(),
          filesystem: fs,
          indexRegistry: QuickOpenIndexRegistry(),
          mruRepository: QuickOpenMruRepository(fs: fs, path: '/mru.json'),
          onOpenFile: (path) => openedPath = path,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'md');
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('README.md'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(openedPath, '/repo/lib/main.dart');
  });

  testWidgets('Esc closes without opening', (tester) async {
    final fs = _fs();
    var opened = 0;
    await tester.pumpWidget(
      _wrap(
        QuickOpenOverlay(
          workspace: _workspace(),
          filesystem: fs,
          indexRegistry: QuickOpenIndexRegistry(),
          mruRepository: QuickOpenMruRepository(fs: fs, path: '/mru.json'),
          onOpenFile: (_) => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(opened, 0);
  });
}
```

Adjust the `WorkspaceFolder` construction to the real constructor (read `client/lib/models/workspace_folder.dart` first). The overlay takes `filesystem`, `indexRegistry`, `mruRepository`, and `onOpenFile` as constructor-injected dependencies so tests never touch `AppStorage` (per repo test conventions).

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/pages/quick_open/quick_open_overlay_test.dart`
Expected: FAIL — package unresolved.

- [ ] **Step 3: Implement the overlay**

Create `client/lib/pages/quick_open/quick_open_overlay.dart`, structured on `command_palette_overlay.dart` (same TpDialog frame, boxed search field copied from the palette's `_SearchField`, same FocusNode.onKeyEvent keyboard interception, `_rowExtent = 48`):

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../services/io/filesystem.dart';
import '../../services/quick_open/quick_open_index.dart';
import '../../services/quick_open/quick_open_mru_repository.dart';
import '../../services/storage/app_storage.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../utils/commands/fuzzy_match.dart';

/// Opens the quick-open dialog (Ctrl+P). Re-entry-guarded like the workspace
/// search dialog.
Future<void> showQuickOpenDialog(
  BuildContext context, {
  required Workspace workspace,
  Filesystem? filesystem,
  QuickOpenIndexRegistry? indexRegistry,
  QuickOpenMruRepository? mruRepository,
}) async {
  if (_quickOpenDialogOpen) return;
  _quickOpenDialogOpen = true;
  try {
    final opener = context.read<WorkbenchEditorOpener>(); // via provider
    final root = workspace.firstFolderPath;
    final fs = filesystem ?? AppStorage.fs;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => QuickOpenOverlay(
        workspace: workspace,
        filesystem: fs,
        indexRegistry: indexRegistry ?? QuickOpenIndexRegistry(),
        mruRepository: mruRepository ?? QuickOpenMruRepository(fs: fs),
        onOpenFile: (path) {
          Navigator.of(dialogContext).pop();
          unawaited(
            opener.openFile(workspace.workspaceId, path, fs: fs, preview: true),
          );
        },
      ),
    );
  } finally {
    _quickOpenDialogOpen = false;
  }
}

var _quickOpenDialogOpen = false;
```

The `QuickOpenOverlay` stateful widget: fields `workspace`, `filesystem`, `indexRegistry`, `mruRepository`, `onOpenFile`. State:
- `loadIndex()` on init: `indexRegistry.load(filesystem, root)` → setState with index (or error → empty).
- Query filtering: empty query → MRU entries (from `mruRepository.load(root)`, loaded once on init and re-touched after open); non-empty → `fuzzyMatch(entry.name, query.toLowerCase())` over index files (the shared util expects a lowercased query, like the palette), rank by score desc → relativePath length asc → relativePath asc, top 50, highlight via `match.indexes` on the basename (same `_HighlightedTitle` rendering as the palette).
- Keyboard: ↑/↓ move selection, Enter opens (pop + `onOpenFile` + `mruRepository.touch(root, path)`), Esc pops — copy the palette's `_handleKey` / `_scrollSelectedIntoView` / `_rowExtent` machinery verbatim.
- Rows: file icon `Icons.insert_drive_file_outlined`, name (highlighted) + relativePath subtitle (small, muted) stacked like `_FileResultTile` in the workspace search dialog; selected-row highlight `cs.primary.withValues(alpha: 0.14)`.
- Status rows: while the index future is pending → `l10n.quickOpenIndexing`; empty query + empty MRU → `l10n.quickOpenEmptyRecent`; no matches → `l10n.quickOpenNoResults`; `index.truncated` → footer `l10n.quickOpenTruncated(index.files.length)`.
- Input debounce: 100 ms `Timer` on query change before recomputing matches (matches only; index load is not debounced).

Because the dialog is 640×560 with standard TpDialog padding, copy the palette's exact frame:

```dart
    return Align(
      alignment: const Alignment(0, -0.6),
      child: TpDialog(
        maxWidth: 640,
        maxHeight: 560,
        child: ShortcutFocus(
          kind: ShortcutFocusKind.text,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SearchField(...), // copied from the command palette verbatim
              const SizedBox(height: 12),
              Flexible(child: /* list or status */),
            ],
          ),
        ),
      ),
    );
```

Import `ShortcutFocus` from `services/commands/shortcut_focus.dart` (check the palette's import list and mirror it).

- [ ] **Step 4: Wire WorkspaceSplitPane**

Apply Task 5 Step 7's planned changes to `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` now that `showQuickOpenDialog` exists:

```dart
  QuickOpenHost? _quickOpenHost;
  late final void Function() _openQuickOpen = _openQuickOpenNow;
```

in `didChangeDependencies` (after `_workspaceSearchHost = context.read<WorkspaceSearchHost>();`):

```dart
    _quickOpenHost = context.read<QuickOpenHost>();
    _syncWorkspaceSearchHost();
    _syncQuickOpenHost();
```

in `dispose` (after `_workspaceSearchHost?.unbind(_openWorkspaceSearch);`):

```dart
    _quickOpenHost?.unbind(_openQuickOpen);
```

the methods (beside `_syncWorkspaceSearchHost`):

```dart
  void _syncQuickOpenHost() {
    final host = _quickOpenHost;
    if (host == null) return;
    final routeActive = WorkspaceRouteActiveScope.routeActiveOf(context);
    if (routeActive) {
      host.bind(_openQuickOpen);
    } else {
      host.unbind(_openQuickOpen);
    }
  }

  void _openQuickOpenNow() {
    if (!mounted) return;
    unawaited(showQuickOpenDialog(context, workspace: widget.workspace));
  }
```

plus imports:

```dart
import '../../../services/commands/quick_open_command_registrar.dart';
import '../../quick_open/quick_open_overlay.dart';
```

- [ ] **Step 5: Run the widget tests**

Run: `cd client && flutter test test/pages/quick_open/quick_open_overlay_test.dart`
Expected: PASS (3 tests). If `pumpAndSettle` times out on the 100 ms debounce, pump explicit durations: `await tester.pump(const Duration(milliseconds: 150));`.

- [ ] **Step 6: Run neighboring regression suites**

Run: `cd client && flutter test test/pages/command_palette test/services/commands test/utils/commands test/services/quick_open`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/quick_open client/lib/pages/home_workspace/workspace/workspace_split_pane.dart client/test/pages/quick_open
git commit -m "feat(quick-open): Ctrl+P dialog — fuzzy file list, MRU, keyboard navigation"
```

---

### Task 7: Full verification + docs

**Files:**
- Verify only; modify `docs/` only if the agent-status README table needs the new command (it does not — but `docs/DEVELOPMENT.md` mentions nothing about commands; skip docs).

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: `49 issues found` — exactly the pre-existing baseline; no new warnings/errors.

- [ ] **Step 2: Full test suite**

Run: `cd client && flutter test --exclude-tags integration`
Expected: `All tests passed!` (2809 + ~20 new ≈ 2829).

- [ ] **Step 3: Manual smoke (run skill)**

Launch the app (`flutter run -d windows`), open a workspace with a large-ish repo, press Ctrl+P, verify: dialog opens with the palette's visual style, typing filters with highlights, Enter opens the file as a preview tab, Esc closes, empty input shows recents after opening a file once. Screenshot for the record.

- [ ] **Step 4: Commit any fixups + final push decision**

Commit message for fixups (if any):

```bash
git add -A
git commit -m "fix(quick-open): polish from manual smoke"
```

Do NOT push without asking the user (their pattern is to request pushes explicitly).
