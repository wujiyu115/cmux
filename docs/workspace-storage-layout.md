# Workspace storage layout

Canonical on-disk layout under **`<teampilotRoot>`** (`AppPaths.basePath` / `AppStorage.appDataRoot`). Code: `WorkspaceLayout` (`client/lib/services/storage/workspace_layout.dart`) and `AppPaths` (`client/lib/services/storage/app_storage.dart`).

Typical `<teampilotRoot>` paths:

| Environment | Path |
|-------------|------|
| Linux desktop | `~/.local/share/com.hhoa.teampilot` |
| Windows native | `%APPDATA%\com.hhoa.teampilot` |
| WSL | `$HOME/.local/share/com.hhoa.teampilot` in chosen distro |
| SSH / Android | Remote host (`RemoteSshStoragePathResolver`) |

## Top-level directories

```
<teampilotRoot>/
  workspace/
    workspaces-index.json          # derived startup snapshot (manifest + session dir ids)
    workspaces/{workspaceId}/       # see below
  worktrees/{repoName}/{branch}/    # app-managed git worktrees
  ssh_profiles/                     # saved SSH connection profiles
  targets.json                      # runtime targets registry (local / WSL / SSH), default target
  notifications.json                # notification center history
  ui/                               # home workspace UI prefs
    open-workspace-tabs.json
    workspace-groups.json
    workspace-favorites.json
    worktree-ui-prefs.json
    ...
```

## Workspace directory

Each workspace is self-contained; deleting `workspace/workspaces/{workspaceId}/` removes its manifest, assets, and sessions.

```
workspace/workspaces/{workspaceId}/
  manifest.json                    # Workspace (folders, session ids, icon ref, …)
  assets/icon.*                    # custom workspace icon (optional)
  sessions/{sessionId}/
    session.json                   # AppSession
```

## Session (`session.json`)

An `AppSession` records the session's workspace, its folder(s), a display title, launch
state, and a few denormalized launch-metadata fields (`cli`, `provider`, `model`,
`effort`, `presetId`). Sessions are **plain interactive shells** — there is no per-member
runtime tree, CLI `CONFIG_DIR` materialization, or message bus on disk.

```json
{
  "schemaVersion": 2,
  "sessionId": "...",
  "workspaceId": "...",
  "folders": [{ "path": "/path/to/repo", "targetId": "local" }],
  "display": "My session",
  "cli": "claude",
  "launchState": "started",
  "createdAt": 1710000000000
}
```

## Runtime targets (`targets.json`)

The control-plane runtime targets registry holds the authoritative `defaultTargetId`,
persisted SSH targets, and the chosen WSL distro. `RuntimeContextRegistry` resolves a
`RuntimeContext` (filesystem + roots) per target: `local` (`LocalFilesystem`),
`wsl` (`WslFilesystem`), or `ssh` (`SftpFilesystem`). Workspace folders carry a `targetId`
that selects the machine a session's shell runs on.

## Related docs

- [AGENTS.md](../AGENTS.md) — architecture overview for AI assistants
- [README.md](../README.md) — user-facing feature descriptions
</content>
