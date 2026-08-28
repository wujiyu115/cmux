# Quick-open .gitignore-aware indexing — Design

Date: 2026-08-28
Status: Approved (interactive session)

## Problem

Quick-open (Ctrl+P) indexes the workspace by recursively listing the root and
filtering against a hardcoded ignore list (`node_modules`, dot-prefixed
segments, etc.). Build artifacts and dependency trees that are *not* in that
list (e.g. `vendor/`, `target/`, custom output dirs) flood the index even
though `.gitignore` already excludes them.

## Decision

Use `git ls-files --cached --others --exclude-standard` as the primary file
source. Git evaluates the full ignore semantics (nested `.gitignore` files,
global gitignore, negation rules) natively, and the app already ships
`GitCommandRunner` implementations for local, WSL, and SSH work planes.

Fallback on any failure — not a git repo, git unavailable on the target,
empty output, non-zero exit — is the existing recursive listing with the
existing hardcoded ignore rules. The hardcoded list is **not** removed;
git-aware filtering is strictly additive.

## Architecture

```
WorkspaceSplitPane._openQuickOpenNow
  → QuickOpenHost → showQuickOpenDialog(context, workspace, filesystem, gitRunner)
      → QuickOpenIndexRegistry.load(fs, root, gitRunner)
          → _listIndex:
              1. gitRunner.runInDirectory(root, ['ls-files',
                   '--cached', '--others', '--exclude-standard', '-z'])
                 exit 0 + non-empty → build entries from relative paths
              2. otherwise → fs.listDirRecursive(root) + existing filters
```

### Components

1. **`QuickOpenIndexRegistry`** (`services/quick_open/quick_open_index.dart`)
   - Constructor gains an optional `GitCommandRunner? gitRunner`.
   - `load(fs, root)` signature unchanged; registry holds the runner.
   - `_listIndex` tries git first; fallback path is byte-for-byte the current
     behavior.
   - `-z` (NUL-separated) output so filenames with spaces/newlines parse
     safely; paths come back POSIX-relative for WSL/SSH and native-relative
     for Windows local roots — join with the backend's own `pathContext`.
   - `QuickOpenLister` typedef stays as the fallback seam for tests.

2. **`showQuickOpenDialog`** (`pages/quick_open/quick_open_overlay.dart`)
   - New optional `GitCommandRunner? gitRunner` parameter, threaded to the
     shared registry on dialog construction (registry is created per dialog
     with the runner; the process-lifetime cache remains keyed by
     `(fs, root)`).

3. **Wiring** (`workspace_split_pane.dart`)
   - `_openQuickOpenNow` resolves the runner the same way it already resolves
     the filesystem: from `WorkspaceToolsScopeRegistry.cubitFor(...).state`,
     via `gitCommandRunnerForContext(slice.tools.context)` for the first
     folder's target. Null when the target slice is unresolved.

### Error handling

- Git failure is silent: log via `AppLogger` (debug level), fall back.
- A repo where everything is ignored (`ls-files` prints nothing) also falls
  back — empty index from git is indistinguishable from misuse and the
  recursive listing still yields dot-filtered results.
- No new user-facing strings; no l10n changes.

## Testing

- Unit tests with a fake `GitCommandRunner`:
  - git success → index built from git paths (ignores honored, e.g. a
    `node_modules/x.js` path never appears because git never returns it).
  - git failure/non-zero → recursive fallback with existing ignore rules.
  - git success but empty stdout → fallback.
  - filenames with spaces (via `-z` splitting).
- Existing registry tests keep passing (they construct without a runner →
  fallback path, unchanged).
- Manual smoke: Ctrl+P in the WSL `web_base` workspace; `json` query must
  not return `node_modules` or `.venv` files (it already doesn't via the
  hardcoded list — now also correct for custom ignore dirs like `vendor`).
