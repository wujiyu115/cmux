# Quick Open (Ctrl+P) — Design

Date: 2026-08-28
Status: Approved (user: "直接执行吧")

## Summary

Bind **Ctrl+P** to a VS Code-style quick-open file dialog for the active
workspace: fuzzy filename search over an in-memory index, jump to the file in
the workbench editor. Separate dialog from the command palette; reuses the
command palette's just-restyled visual language.

## Decisions (user-confirmed)

- **Scope**: active workspace's `firstFolderPath` (same root as Ctrl+F file
  search and the file tree).
- **Matching**: subsequence fuzzy match (same algorithm family as the command
  palette — `mfs` matches `main_file_search.dart`).
- **Empty input**: show recently opened files (persistent MRU); hint text when
  empty.
- **Performance model**: stale-while-revalidate. **No file watcher** — the
  dialog lives for seconds, correctness comes from re-listing on open.

## Architecture

```
Ctrl+P (CommandIds.quickOpen, terminalPassthrough)
  → QuickOpenHost.open()          (bound by active workspace pane, like WorkspaceSearchHost)
  → showQuickOpenDialog(context, workspace)
      ├─ QuickOpenIndexRegistry   (per-root cache, 60s revalidate window)
      │    └─ Filesystem.listDirRecursive(root) → filtered flat file list (cap 50k)
      ├─ QuickOpenMruRepository   (persistent JSON, last 50 files, per workspace root)
      ├─ fuzzy match over index   (shared util extracted from command_palette_filter)
      └─ WorkbenchEditorOpener.openFile(workspaceId, path, preview: true)
```

## Components

### 1. Command registration — `command_catalog.dart`, `command_ids.dart`

- `CommandIds.quickOpen = 'workbench.quickOpen'`
- Default chord `KeyChord(key: 'p', mods: [KeyChordMod.mod])`, `when:
  ShortcutWhen.hasWorkspace`, `terminalPassthrough: true`, category
  `navigation`, title key `shortcutsQuickOpen` (new l10n keys, both ARB files).

### 2. Host binding — `services/commands/quick_open_command_registrar.dart`

Clone of `WorkspaceSearchHost` pattern:

- `QuickOpenHost` with bind/unbind/open.
- `registerQuickOpenCommands(bus, host)` registers `CommandIds.quickOpen`.
- Wired in `app_shell.dart` next to `registerWorkspaceSearchCommands`; provided
  via `RepositoryProvider` in `main.dart`.
- `WorkspaceSplitPane` binds on init / unbinds on dispose (same places the
  workspace-search host binds).

### 3. Index with stale-while-revalidate — `services/quick_open/quick_open_index.dart`

```dart
class QuickOpenFileEntry { final String path; final String name; final String relativePath; }
class QuickOpenIndex { final List<QuickOpenFileEntry> files; final bool truncated; }

class QuickOpenIndexRegistry {
  Future<QuickOpenIndex> load(Filesystem fs, String root);  // cached per root
}
```

- On first open: `fs.listDirRecursive(root)`, filter hidden entries (any
  segment starting with `.`), ignore dirs (`node_modules`, `build`, `dist`,
  `.dart_tool`, … — same set as `workspace_file_search`), keep files only.
- Cache keyed by `(Filesystem instance, root)`; registry holds a
  `Future<QuickOpenIndex>` (not the index) so concurrent opens share one
  listing. **Cache never expires within the app run**; the *revalidate* policy
  is per-open:
  - Cache hit: return cached index immediately, kick off a background
    re-listing that replaces the cache entry.
  - Cache miss: caller awaits the (single shared) listing future.
- Entry cap 50,000 files, `truncated` flag surfaced in the UI footer when hit.
- Cache is invalidated when a workspace re-binds with a different root or
  filesystem instance.

### 4. Fuzzy match — `utils/commands/fuzzy_match.dart`

Extract `_subsequenceMatch` + `_isWordStart` from
`utils/commands/command_palette_filter.dart` into a shared
`FuzzyMatch`/`fuzzyMatch(target, query)` utility (same scoring: per-char base,
contiguous-run bonus, word-start bonus, earlier-first-match bonus). Command
palette and quick-open both call it. No behavior change for the palette — pure
move.

Quick-open ranks by: match score, then shorter relative path, then
alphabetical. Display top 50.

### 5. MRU — `services/quick_open/quick_open_mru_repository.dart`

Clone of `CommandMruRepository` shape: JSON file under the app-data area,
`load()` / `touch(path)` capped at 50 entries per workspace root (keyed by
root path so switching roots doesn't cross-contaminate). Touched on file open
from quick-open only.

### 6. Dialog — `pages/quick_open/quick_open_overlay.dart`

Clone of `command_palette_overlay.dart` structure (recently restyled):

- `showQuickOpenDialog(context, workspace, …)` — `showDialog` re-entry guard,
  like workspace search.
- `TpDialog(maxWidth: 640, maxHeight: 560)` + boxed search field (identical
  decoration to palette/Ctrl+F) + `ListView.builder` rows (height 48, file
  icon, name + relative-path subtitle, matched-character highlight).
- Keyboard: ↑/↓ select, Enter open, Esc close — same `FocusNode.onKeyEvent`
  interception pattern.
- While indexing (first open, big tree): search field usable immediately, list
  shows a subtle "正在索引文件…" status row (`quickOpenIndexing` l10n key);
  results appear when ready.
- Empty query → MRU entries (labelled via `quickOpenRecent` l10n section
  header); empty MRU → hint row.
- Truncated index → footer row `quickOpenTruncated`.
- Selecting a file pops the route, then `WorkbenchEditorOpener.openFile(
  workspaceId, path, preview: true)` against the still-mounted context (same
  ordering contract as workspace search).

## Performance notes

- WSL: one `find -printf` subprocess lists tens of thousands of files in
  ~100-300 ms; local/SFTP are single batched calls too. Only one listing per
  open (subsequent opens within the run hit the cache + one background
  re-list).
- Scoring runs in memory: ~ms for 20k files per keystroke; input additionally
  debounced 100 ms.
- No watcher is attached: the dialog lives seconds; the existing file-tree
  refresh chain (native watch on local, 15 s poll + agent-turn-end poke on
  WSL/SFTP) keeps the tree fresh independently.

## Error handling

- Listing failure (dropped connection, missing root): show the empty state
  with `quickOpenNoResults`; the shared future means a failed listing doesn't
  poison the cache — a failure clears the cache entry so the next open retries.
- MRU load failure: treated as empty (fresh store).
- Opening a file that vanished between listing and Enter: `openFile`'s
  existing error path handles it (editor surfaces read failure).

## Testing

- Unit: index filtering/ignore/cap/truncation; registry cache-hit + background
  revalidate replacing entries; fuzzy rank ordering (word-start > contiguous >
  sparse; shorter path wins ties); MRU cap + per-root isolation.
- Widget: dialog renders MRU on empty query; typing filters and highlights;
  ↑/↓/Enter/Esc keyboard contract; selection calls `openFile` with the right
  path; indexing status row appears while the listing future is pending.
- Command-palette regression: `filterCommandPalette` behavior unchanged after
  the shared-fuzzy extraction (existing tests must pass untouched).
- l10n: all new strings in both ARB files; `dart run tool/gen_warmup_glyphs.dart`
  after ARB changes.

## Out of scope

- Watching the index with `WorkspaceFsWatcher` (revalidate covers it).
- Multi-folder workspaces (first folder only, same as Ctrl+F).
- `>`-mode command/file unified palette.
- Recent-folders / MRU sharing with the file tree.
