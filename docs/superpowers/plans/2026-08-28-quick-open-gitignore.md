# Quick-open gitignore-aware indexing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quick-open (Ctrl+P) indexes only files git considers openable — `git ls-files --cached --others --exclude-standard` — falling back to today's recursive listing whenever git cannot serve the root; also fixes the `BOTTOM OVERFLOWED BY 14 PIXELS` result-row bug noticed during smoke tests.

**Architecture:** The listing strategy moves into `QuickOpenIndexRegistry`, which gains an optional `GitCommandRunner`. `_listIndex` first tries a git listing (`-z` NUL-separated, paths joined with the backend's own `pathContext`), and on any failure (no runner, exception, non-zero exit, empty output) falls back to the existing recursive listing — byte-for-byte the current behavior. The workbench resolves the runner from the same target slice it already resolves the filesystem from, via the existing `gitCommandRunnerForContext` factory, and threads it through `showQuickOpenDialog`. The shared process-lifetime registry keeps its `(fs, root)` cache; the runner is updated in place per dialog.

**Tech Stack:** Flutter/Dart, flutter_bloc, existing `GitCommandRunner` (local/WSL/SSH), `package:path` contexts.

**Spec:** `docs/superpowers/specs/2026-08-28-quick-open-gitignore-design.md` (approved)

---

### Task 1: `QuickOpenIndexRegistry` — gitignore-aware listing

**Files:**
- Modify: `client/lib/services/quick_open/quick_open_index.dart`
- Test: `client/test/services/quick_open/quick_open_index_test.dart`

- [ ] **Step 1: Write the failing tests**

In `client/test/services/quick_open/quick_open_index_test.dart`, add the import for `path` and the fake runner at file scope (after the existing imports, before `void main()`):

```dart
import 'package:path/path.dart' as p;
import 'package:teampilot/services/git/git_command_runner.dart';
```

```dart
class _FakeGitRunner implements GitCommandRunner {
  _FakeGitRunner({this.result, this.error});

  final GitCommandResult? result;
  final Object? error;
  final List<(String, List<String>)> calls = [];

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args) async {
    calls.add((dir, args));
    if (error != null) throw error!;
    return result!;
  }
}
```

Then append these tests inside `main()` (after the existing `listing failure is not cached` test; they reuse the `fs` built in `setUp`):

```dart
  group('gitignore-aware listing via git ls-files', () {
    test('git listing wins: gitignore-excluded files stay out of the index',
        () async {
      final runner = _FakeGitRunner(
        result: const GitCommandResult(
          exitCode: 0,
          stdout: 'README.md\x00lib/main.dart\x00',
          stderr: '',
        ),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');

      expect(index.files.map((e) => e.relativePath).toList(), [
        'README.md',
        'lib/main.dart',
      ]);
      expect(index.truncated, isFalse);
      expect(runner.calls, hasLength(1));
      expect(runner.calls.single.$1, '/repo');
      expect(runner.calls.single.$2, contains('ls-files'));
      expect(runner.calls.single.$2, contains('--cached'));
      expect(runner.calls.single.$2, contains('--others'));
      expect(runner.calls.single.$2, contains('--exclude-standard'));
      expect(runner.calls.single.$2, contains('-z'));
    });

    test('git entry fields use absolute path and basename', () async {
      final runner = _FakeGitRunner(
        result: const GitCommandResult(
          exitCode: 0,
          stdout: 'lib/main.dart\x00',
          stderr: '',
        ),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');
      final entry = index.files.single;
      expect(entry.path, '/repo/lib/main.dart');
      expect(entry.name, 'main.dart');
      expect(entry.relativePath, 'lib/main.dart');
    });

    test('git non-zero exit falls back to the recursive listing', () async {
      fs.files['/repo/vendor/app.log'] = 'x';
      final runner = _FakeGitRunner(
        result: const GitCommandResult(
          exitCode: 128,
          stdout: '',
          stderr: 'fatal: not a git repository',
        ),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');

      // vendor/ is ignored by git in real life but NOT in the hardcoded list,
      // so its presence proves we took the fallback path.
      expect(
        index.files.map((e) => e.relativePath),
        contains('vendor/app.log'),
      );
      expect(
        index.files.map((e) => e.relativePath),
        contains('README.md'),
      );
      expect(
        index.files.map((e) => e.relativePath),
        isNot(contains('node_modules/pkg/index.js')),
      );
    });

    test('empty git output falls back to the recursive listing', () async {
      final runner = _FakeGitRunner(
        result: const GitCommandResult(exitCode: 0, stdout: '', stderr: ''),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');
      expect(
        index.files.map((e) => e.relativePath),
        contains('README.md'),
      );
    });

    test('git runner throwing falls back to the recursive listing', () async {
      final runner = _FakeGitRunner(error: StateError('ssh down'));
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');
      expect(
        index.files.map((e) => e.relativePath),
        contains('README.md'),
      );
    });

    test('git listing splits filenames with spaces on NUL', () async {
      final runner = _FakeGitRunner(
        result: const GitCommandResult(
          exitCode: 0,
          stdout: 'my file.txt\x00lib/with space.dart\x00',
          stderr: '',
        ),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo');
      expect(index.files.map((e) => e.name).toSet(), {
        'my file.txt',
        'with space.dart',
      });
    });

    test('git listing honors the maxFiles cap', () async {
      final stdout = [for (var i = 0; i < 6; i++) 'file$i.txt\x00'].join();
      final runner = _FakeGitRunner(
        result: GitCommandResult(exitCode: 0, stdout: stdout, stderr: ''),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(fs, '/repo', maxFiles: 5);
      expect(index.files, hasLength(5));
      expect(index.truncated, isTrue);
    });

    test('git POSIX paths join with the backend\'s native separators', () async {
      final windowsFs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.windows),
      );
      final runner = _FakeGitRunner(
        result: const GitCommandResult(
          exitCode: 0,
          stdout: 'lib/main.dart\x00',
          stderr: '',
        ),
      );
      final registry = QuickOpenIndexRegistry(gitRunner: runner);
      final index = await registry.load(windowsFs, r'C:\repo');
      final entry = index.files.single;
      expect(entry.relativePath, r'lib\main.dart');
      expect(entry.path, r'C:\repo\lib\main.dart');
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd D:/git/teampilot/client && flutter test test/services/quick_open/quick_open_index_test.dart`
Expected: FAIL to compile — `QuickOpenIndexRegistry` has no named parameter `gitRunner`.

- [ ] **Step 3: Implement the git listing in the registry**

In `client/lib/services/quick_open/quick_open_index.dart`:

Add imports (after the existing `package:path` import):

```dart
import '../../utils/logging/logger_utils.dart';
import '../git/git_command_runner.dart';
```

Replace the constructor and `_listerOverride` field (lines ~64-67) with:

```dart
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
```

Rename the existing `_listIndex` body to `_listIndexRecursive` (keep its body byte-for-byte) and add a new `_listIndex` dispatcher plus the git path:

```dart
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
    // … existing _listIndex body, unchanged: lister, ignore filter, cap, sort …
  }
```

The hardcoded `_ignoredDirNames` list and `_isIgnored` stay exactly as they are (the spec makes git filtering strictly additive; the fallback keeps using them).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd D:/git/teampilot/client && flutter test test/services/quick_open/quick_open_index_test.dart`
Expected: PASS — all new tests plus the 7 pre-existing tests (they construct the registry without a runner, so they exercise the unchanged fallback).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/quick_open/quick_open_index.dart client/test/services/quick_open/quick_open_index_test.dart
git commit -m "feat(quick-open): gitignore-aware index via git ls-files"
```

---

### Task 2: Thread the work-plane git runner through the dialog and the workbench

**Files:**
- Modify: `client/lib/pages/quick_open/quick_open_overlay.dart:29-61` (`showQuickOpenDialog`)
- Modify: `client/lib/services/workspace/workspace_tools_scope.dart:68-73` (add `runtimeContextForTarget`)
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart:94-112` (`_openQuickOpenNow`)
- Test: `client/test/services/workspace/workspace_tools_scope_test.dart`

- [ ] **Step 1: Write the failing test for `runtimeContextForTarget`**

In `client/test/services/workspace/workspace_tools_scope_test.dart`, add a group after the `filesystemForTarget` group (the file's `_ctx` / `WorkspaceToolsContext` helpers are reused):

```dart
  group('WorkspaceToolsScopeState.runtimeContextForTarget', () {
    test('returns the context of the matching target slice', () {
      final localCtx = _ctx(InMemoryFilesystem());
      final wslCtx = _ctx(InMemoryFilesystem());
      final state = WorkspaceToolsScopeState(
        targetSlices: [
          WorkspaceTargetSlice(
            targetId: 'local',
            tools: WorkspaceToolsContext(targetId: 'local', context: localCtx),
            roots: const [],
          ),
          WorkspaceTargetSlice(
            targetId: 'wsl:Ubuntu',
            tools: WorkspaceToolsContext(
              targetId: 'wsl:Ubuntu',
              context: wslCtx,
            ),
            roots: const [],
          ),
        ],
        resolving: false,
      );

      expect(state.runtimeContextForTarget('local'), same(localCtx));
      expect(state.runtimeContextForTarget('wsl:Ubuntu'), same(wslCtx));
    });

    test('returns null for a target that is not resolved', () {
      final state = WorkspaceToolsScopeState(
        targetSlices: [
          WorkspaceTargetSlice(
            targetId: 'local',
            tools: WorkspaceToolsContext(
              targetId: 'local',
              context: _ctx(InMemoryFilesystem()),
            ),
            roots: const [],
          ),
        ],
        resolving: false,
      );

      expect(state.runtimeContextForTarget('ssh:down'), isNull);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd D:/git/teampilot/client && flutter test test/services/workspace/workspace_tools_scope_test.dart`
Expected: FAIL to compile — `runtimeContextForTarget` is not defined.

- [ ] **Step 3: Implement `runtimeContextForTarget`**

In `client/lib/services/workspace/workspace_tools_scope.dart`, add directly after `filesystemForTarget` (after line 73):

```dart
  /// Runtime context of the machine with [targetId], or null when that target
  /// has not been resolved (still resolving or unreachable).
  RuntimeContext? runtimeContextForTarget(String targetId) {
    for (final slice in targetSlices) {
      if (slice.targetId == targetId) return slice.tools.context;
    }
    return null;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd D:/git/teampilot/client && flutter test test/services/workspace/workspace_tools_scope_test.dart`
Expected: PASS.

- [ ] **Step 5: Thread the runner through `showQuickOpenDialog`**

In `client/lib/pages/quick_open/quick_open_overlay.dart`:

Add the import:

```dart
import '../../services/git/git_command_runner.dart';
```

Extend the doc comment's parameter note (after the `[filesystem]` paragraph) and the signature:

```dart
/// [gitRunner], when provided, is the work-plane git runner for the machine
/// hosting [workspace]'s folders; the index then prefers `git ls-files` so
/// .gitignore rules hold, falling back to the recursive listing otherwise.
Future<void> showQuickOpenDialog(
  BuildContext context, {
  required Workspace workspace,
  Filesystem? filesystem,
  GitCommandRunner? gitRunner,
  QuickOpenIndexRegistry? indexRegistry,
  QuickOpenMruRepository? mruRepository,
}) async {
```

Inside, after `final registry = indexRegistry ?? _sharedIndexRegistry;` add:

```dart
    if (gitRunner != null) {
      // The shared registry keeps its (fs, root) cache across dialogs, so the
      // runner is updated in place instead of replacing the registry.
      registry.gitRunner = gitRunner;
    }
```

- [ ] **Step 6: Wire the runner in the workbench**

In `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart`:

Add the import:

```dart
import '../../../services/git/git_command_runner.dart';
```

Replace `_openQuickOpenNow` (lines 94-112) with:

```dart
  void _openQuickOpenNow() {
    if (!mounted) return;
    final lifecycle = context.read<ChatCubit>().lifecycle;
    final scopeState = context
        .read<WorkspaceToolsScopeRegistry>()
        .cubitFor(tabScopeId: widget.tabScopeId, lifecycle: lifecycle)
        .state;
    final targetId = widget.workspace.folders.isEmpty
        ? WorkspaceFolder.localTargetId
        : widget.workspace.folders.first.targetId;
    final targetContext = scopeState.runtimeContextForTarget(targetId);
    final fs = targetContext?.filesystem ?? AppStorage.fs;
    unawaited(
      showQuickOpenDialog(
        context,
        workspace: widget.workspace,
        filesystem: fs,
        gitRunner: targetContext == null
            ? null
            : gitCommandRunnerForContext(targetContext),
      ),
    );
  }
```

(`scopeState.filesystemForTarget(targetId)` is replaced by `targetContext?.filesystem` — same value, one lookup.)

- [ ] **Step 7: Analyze and run the affected suites**

Run: `cd D:/git/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues (baseline infos only).

Run: `cd D:/git/teampilot/client && flutter test test/pages/quick_open/ test/services/quick_open/ test/services/workspace/workspace_tools_scope_test.dart`
Expected: PASS — the overlay tests construct `QuickOpenOverlay` directly with a runner-less registry, so they keep exercising the fallback.

- [ ] **Step 8: Commit**

```bash
git add client/lib/pages/quick_open/quick_open_overlay.dart client/lib/services/workspace/workspace_tools_scope.dart client/lib/pages/home_workspace/workspace/workspace_split_pane.dart client/test/services/workspace/workspace_tools_scope_test.dart
git commit -m "feat(quick-open): thread work-plane git runner into the dialog"
```

---

### Task 3: Fix the result-row overflow (`BOTTOM OVERFLOWED BY 14 PIXELS`)

Two-line rows (title + relative-path subtitle) don't fit the fixed 48px row extent once the text scale rises — smoke tests on Windows showed overflow stripes. Give the row room: extent 48 → 64, vertical padding 8 → 6.

**Files:**
- Modify: `client/lib/pages/quick_open/quick_open_overlay.dart:105` (`_rowExtent`) and `_ResultRow` padding (line ~481)
- Test: `client/test/pages/quick_open/quick_open_overlay_test.dart`

- [ ] **Step 1: Write the failing test**

In `client/test/pages/quick_open/quick_open_overlay_test.dart`, add inside `main()`:

```dart
  testWidgets('result rows do not overflow at elevated text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final fs = _fs();
    await _pumpDialog(
      tester,
      QuickOpenOverlay(
        workspace: _workspace(),
        filesystem: fs,
        indexRegistry: QuickOpenIndexRegistry(),
        mruRepository: QuickOpenMruRepository(fs: fs, path: '/mru.json'),
      ),
    );

    await tester.enterText(find.byType(TextField), 'read');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd D:/git/teampilot/client && flutter test test/pages/quick_open/quick_open_overlay_test.dart --plain-name 'result rows do not overflow at elevated text scale'`
Expected: FAIL — `tester.takeException()` returns a `FlutterError` ("A RenderFlex overflowed by N pixels on the bottom"); at 1.3× the two text lines (~40px) plus 16px padding exceed the 48px extent.

- [ ] **Step 3: Fix the row geometry**

In `client/lib/pages/quick_open/quick_open_overlay.dart`:

```dart
  static const double _rowExtent = 64;
```

And in `_ResultRow.build`, change the inner padding:

```dart
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
```

- [ ] **Step 4: Run the whole overlay suite**

Run: `cd D:/git/teampilot/client && flutter test test/pages/quick_open/quick_open_overlay_test.dart`
Expected: PASS — all five tests (the existing ones assert `find.text('lib/main.dart')` etc.; the two-line row layout is unchanged, only taller).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/quick_open/quick_open_overlay.dart client/test/pages/quick_open/quick_open_overlay_test.dart
git commit -m "fix(quick-open): result rows overflow at elevated text scale"
```

---

### Task 4: Full verification

- [ ] **Step 1: Analyze**

Run: `cd D:/git/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: exit 0, no new diagnostics.

- [ ] **Step 2: Full test suite**

Run: `cd D:/git/teampilot/client && flutter test --exclude-tags integration`
Expected: all pass.

- [ ] **Step 3: Manual smoke — local workspace (gitignore filter discriminator)**

Run the app (`cd D:/git/teampilot/client && flutter run -d windows`), open the **teampilot** workspace, press Ctrl+P:

1. No yellow/black overflow stripes on result rows.
2. Find a discriminator path — a directory that is *gitignored* but *not* in the hardcoded ignore list and exists on disk. Candidates: `client/google_fonts/` (gitignored per AGENTS.md); confirm with `git check-ignore -v <path>` and `ls` before judging. Query its basename in Ctrl+P: it must return **no** matches after this change (the recursive fallback would have listed it).
3. Query a normal file (e.g. `main.dart`) — matches still appear.
4. Close, Ctrl+P again — results appear instantly (shared-registry cache) and a background refresh runs.

- [ ] **Step 4: Manual smoke — WSL workspace**

Switch to the WSL `web_base` workspace, Ctrl+P, query `json`:

1. Dialog opens, real matches return (WSL `git ls-files` path via `WslGitCommandRunner`).
2. No overflow stripes.
3. Ignored build/dependency dirs that git excludes do not appear.

- [ ] **Step 5: Report**

Summarize verification evidence. Do **not** push — ask the user first.

---

## Self-Review

- **Spec coverage:** git ls-files primary + `-z` parsing + join with backend pathContext (Task 1); registry constructor runner + `load` signature unchanged + `QuickOpenLister` fallback seam intact (Task 1); dialog param + shared-registry threading (Task 2 Step 5); wiring via `gitCommandRunnerForContext` from the target slice (Task 2 Step 6); silent fallback + AppLogger debug + empty-output fallback (Task 1 Step 3, tested); existing tests unchanged and passing (Tasks 1-3); manual WSL smoke (Task 4). The row-overflow fix rides along as approved in-session. No gaps.
- **Placeholder scan:** the `_listIndexRecursive` body is referenced as "existing body, unchanged" because it is a verbatim rename — the executor keeps the original lines in place; no other placeholders.
- **Type consistency:** `GitCommandRunner`/`GitCommandResult` names, `gitRunner` field name used consistently in registry constructor, dialog param, and setter assignment; `runtimeContextForTarget` matches between test and implementation; `_rowExtent` referenced by `_scrollSelectedIntoView` and `_ResultList` unchanged.
