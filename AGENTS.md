# AGENTS.md

Guidance for Claude Code and other AI assistants working in this repository.

**TeamPilot** is a Flutter desktop client (`client/`, package `teampilot`, data ID `com.hhoa.teampilot`) that manages **workspaces** and embeds **interactive terminal sessions** inside them. It is a workspace-oriented terminal multiplexer with a built-in IDE (file tree, editor, Git, worktrees) and Claude **agent-status notifications**. The home UI is an Apifox-style workspace shell.

The app opens **plain interactive shells** — a local PTY on desktop, or SSH (always on Android, optional on desktop). It does **not** launch or orchestrate AI-agent CLIs itself; you run whatever CLI you like inside a shell tab.

| Docs | Purpose |
|------|---------|
| [README.md](README.md) (简体中文) | User-facing |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Clone, commands, tests, packaging, CI |
| [docs/CODE_QUALITY.md](docs/CODE_QUALITY.md) | File size, layering, tests |
| [docs/DEBUGGING.md](docs/DEBUGGING.md) | Systematic debugging process |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | Progressive paint / UX jank optimization (`TpDeferred*`) |
| [docs/PERFORMANCE_ANALYSIS.md](docs/PERFORMANCE_ANALYSIS.md) | DevTools performance JSON offline analysis (`tool/analyze_performance_json.dart`) |
| [docs/workspace-storage-layout.md](docs/workspace-storage-layout.md) | On-disk layout under `<teampilotRoot>` |

All app code lives under `client/lib/` (cubits, pages, repositories, services, models). Vendored deps: `client/packages/` (git submodules: xterm, flutter_pty_new, dartssh2, re-editor, flutter_alacritty, **shared_ui**). Cross-route UI primitives live in **`shared_ui`** as the **Tp** design system (`TpButton`, `TpInput`, `TpTheme`, …); see [client/packages/shared_ui/README.md](client/packages/shared_ui/README.md).

## Core concepts

| Concept | Model / cubit | Role |
|---------|---------------|------|
| **Workspace** | `Workspace`, `SessionRepository` | *Where* work happens: one or more repo folders plus that workspace's sessions. |
| **Session** | `AppSession`, `ChatCubit` | One terminal workbench tab bound to a workspace's folder(s); a plain interactive shell (local PTY or SSH). |
| **Runtime target** | `RuntimeTarget`, `RuntimeContextRegistry` | *Which machine* a workspace/session runs on: `local`, a WSL distro, or an SSH profile. |

Each `AppSession` (persisted as `session.json`) carries its `folders`, a `display` title, launch state, and a few denormalized metadata fields. There is no team / member / expert / hub / launch-profile / skills / plugins / MCP / providers model — that machinery has been removed.

## Architecture

### Bootstrap flow

```
main.dart
  → AppPathsBootstrapper.init()              # Application Support → AppPaths
  → TeamPilotBootstrap / buildAppShell()      # client/lib/app/app_shell.dart
      → RuntimeTargetRegistry / RuntimeContextRegistry / AppStorage.bindHome()
      → SessionRepository, SessionLifecycleService
      → AgentStatusGateway.ensureStarted()    # loopback HTTP for agent-status hooks
      → ChatCubit, AgentAttentionCubit, NotificationCubit, EditorCubit,
        WorkbenchCubit, LayoutCubit, ConfigCubit, SshProfileCubit,
        SshConnectionCubit, WorkspaceTerminalRegistry,
        WorkspaceWorktreeRegistry, …
      → TerminalIdleNotificationService, AgentAttentionNotificationService
  → MaterialApp.router (GoRouter)
```

### State, routing, and workbench

- **State:** `flutter_bloc` cubits under `client/lib/cubits/`.
- **Routing:** `client/lib/router/app_router.dart`. **[HomeShell](client/lib/pages/home_workspace/home_workspace_shell.dart)** renders the title bar + open-workspace tabs; **[HomeWorkspaceBodyStack](client/lib/pages/home_workspace/home_workspace_body_stack.dart)** keeps one alive **[WorkspacePage](client/lib/pages/home_workspace/workspace/workspace_page.dart)** per tab. Initial location is `/home-v2` (or the last workspace per `LayoutCubit` / `applyWorkspaceEntryMode`).
- **Workbench:** `WorkspacePage` (route `/home-v2/workspace/:workspaceId`) hosts the session tabs, the built-in IDE, and the workspace manage view. `ChatCubit` owns the tabbed `TerminalSession`s; **[SessionLaunchService](client/lib/cubits/chat/session_launch_service.dart)** drives `requestOpenSession` / `connectWorkspaceSession` → `SessionLifecycleService` (resolves the runtime target) → `TerminalSession.connect`.
- **Workspace manage:** `WorkspaceConfigSection` currently has a single **settings** section (`workspace_config_section.dart`); reached via `/home-v2/workspace/:workspaceId?view=manage`.

### Terminal transport

| Mode | When | Implementation |
|------|------|----------------|
| Local PTY | Desktop default | `flutter_pty_new` → `LocalPtyTransport` |
| SSH | Android always; desktop optional | `dartssh2` → `SshPtyTransport` |

Embedded terminals render with **flutter_alacritty** (Alacritty-based Rust engine). Fullscreen submit uses `TerminalFullscreenInputChannel` / `TerminalFullscreenPtyPort`. See `terminal_transport_factory.dart`, `terminal_session.dart`.

### Agent-status notifications

The one surviving AI-adjacent feature. Shared agent hooks (installed by `AgentHookInstaller`) post CLI lifecycle events to an app-wide loopback HTTP **`AgentStatusGateway`** (`POST /agent-status`); events are normalized and matched back to the originating session, then surfaced as desktop notifications when an agent finishes a turn or needs permission. Covered CLIs: **Claude Code** (`~/.claude/settings.json`), **Qoder** (`~/.qoder/settings.json`), **Codex** (`~/.codex/hooks.json`) — all report Claude-Code-shaped payloads, so one normalizer path serves all three. Installs are additive merges that strip only TeamPilot's own entries; the user's other hook tooling (Orca, rtk, …) is left untouched.

- Code: `client/lib/services/agent_status/` (gateway, HTTP handler, normalizer, seat lookup, hook installer; `remote/` carries the reverse-tunnel delivery for SSH).
- Notifications: `client/lib/services/notification/` (`AgentAttentionNotificationService`, `TerminalIdleNotificationService`, `DesktopSystemNotifier`).
- State: `client/lib/cubits/agent_attention_cubit.dart`, `notification_cubit.dart`.

### Storage and app data

`AppStorage` (`app_storage.dart`) is the control-plane facade; it binds to the home `RuntimeContext` via `RuntimeContextRegistry`. Paths: `AppStorage.paths`, `AppStorage.cwd`, `AppStorage.fs`.

| Backend | Filesystem | `cwd` / data root |
|---------|------------|-------------------|
| `native` | `LocalFilesystem` | App Support; new workspaces use `DefaultWorkspaceDirectory` (Documents), not `Directory.current` |
| `wsl` | `WslFilesystem` | WSL `$HOME`; app data `~/.local/share/com.hhoa.teampilot` in distro |
| `ssh` | `SftpFilesystem` | Remote home + remote TeamPilot app dir |

**`<teampilotRoot>`** = `AppPaths.basePath` / `AppStorage.appDataRoot`. Full tree: [docs/workspace-storage-layout.md](docs/workspace-storage-layout.md); code: `WorkspaceLayout` (`workspace_layout.dart`), `AppPaths` (`app_storage.dart`).

> Note: `AppPaths`, `WorkspaceLayout`, and `RuntimeLayout` still contain a number of **legacy path helpers** (launch-profiles, identities-runtime, cli-defaults, bus/mail, team/member hub, skills/plugins/mcp/providers, automations) left over from the pre-rework app. These have **no live callers** and do not describe the current on-disk tree — do not treat them as ground truth.

### CLI tool identity

`CliTool` enum in `client/lib/models/cli_tool.dart` (`claude`, `codex`, `flashskyai`, `opencode`, `cursor`). It is now only lightweight metadata for per-session labels / locate helpers under `client/lib/services/cli/` (`cli_tool_locator.dart`, `cli_executable_validator.dart`) and the Claude agent-status hook — the app does not spawn or manage these CLIs.

### Built-in IDE and worktrees

| Feature | Key paths |
|---------|-----------|
| **File tree / editor / Git** | `FileTreeCubit`, `EditorCubit`, `GitCubit` + `services/git/`, `services/file_tree/`, `services/editor/`; `pages/home_workspace/workspace/` panels |
| **Git worktrees** | `WorkspaceWorktreeRegistry` / `WorkspaceWorktreeStore` (`services/workspace/`), `WorktreeCubit`; disk under `<teampilotRoot>/worktrees/{repo}/{branch}`; sidebar groups sessions by worktree |
| **Workspace shell terminal** | `WorkspaceTerminalRegistry` — workspace-scoped terminal sessions |

## Where to change code

| Area | Path |
|------|------|
| Entry | `client/lib/main.dart` |
| Bootstrap / DI | `client/lib/app/app_shell.dart`, `client/lib/app/app_data_bootstrap.dart` |
| Router | `client/lib/router/app_router.dart` |
| Workspace shell / tabs | `client/lib/pages/home_workspace/` (`home_workspace_shell.dart`, `home_workspace_body_stack.dart`, `workspace/workspace_page.dart`) |
| Sessions / terminal tabs | `client/lib/cubits/chat_cubit.dart`, `client/lib/cubits/chat/session_launch_service.dart` |
| Sessions persistence | `client/lib/repositories/session_repository.dart` |
| Session launch pipeline | `client/lib/services/launch/`, `client/lib/services/session/session_lifecycle_service.dart` |
| PTY + terminal | `client/lib/services/terminal/terminal_session.dart`, `terminal_transport_factory.dart` |
| Launch args / WSL paths | `client/lib/services/session/launch_command_builder.dart` |
| Agent-status notifications | `client/lib/services/agent_status/`, `client/lib/services/notification/`, `client/lib/cubits/agent_attention_cubit.dart` |
| CLI locate / validate | `client/lib/services/cli/` (`cli_tool_locator.dart`, `cli_executable_validator.dart`), `client/lib/models/cli_tool.dart` |
| File tree / editor / Git | `client/lib/cubits/file_tree_cubit.dart`, `editor_cubit.dart`, `git_cubit.dart`; `client/lib/services/git/`, `services/file_tree/`, `services/editor/` |
| Worktrees | `client/lib/services/workspace/workspace_worktree_registry.dart`, `client/lib/cubits/worktree_cubit.dart` |
| Paths / Documents default | `client/lib/services/storage/app_storage.dart` |
| Storage backend / contexts | `client/lib/services/storage/runtime_context_registry.dart`, `runtime_context_resolver.dart`, `runtime_target_registry.dart` |
| Storage layout | `client/lib/services/storage/workspace_layout.dart` |
| SSH profiles | `client/lib/repositories/ssh_profile_repository.dart`, `client/lib/cubits/ssh_profile_cubit.dart`, `ssh_connection_cubit.dart` |
| App settings / config | `client/lib/pages/config/`, `client/lib/cubits/config_cubit.dart`, `layout_cubit.dart` |
| Shared UI / Tp design system | `client/packages/shared_ui` — cross-route `Tp*` primitives + `TpTheme` / `TpTextStyles` / `TpFontTheme`; progressive mount helpers (`TpDeferredMountShell`, `TpDeferredForegroundMount`, `TpKeepAliveLayer`); wrap `MaterialApp` with `TpTheme` (see package README) |
| Product / domain chrome | `client/lib/widgets/` — app-specific layout reused across routes (not new generic controls) |
| Performance snapshot CLI | `client/tool/analyze_performance_json.dart` — [docs/PERFORMANCE_ANALYSIS.md](docs/PERFORMANCE_ANALYSIS.md) |

**Routes** (`app_router.dart`):

- `/home-v2` — workspace home (title bar + open-workspace tabs)
- `/home-v2/workspace/:workspaceId` — workspace workbench (`?view=manage&section=…` for the manage view; `/…/manage` redirects here)
- `/config/{layout,session,ssh-profiles,shortcuts,about,logs}` — app settings
- `/ssh-profiles` — redirects to `/config/ssh-profiles`

## Debugging

See [docs/DEBUGGING.md](docs/DEBUGGING.md) for the systematic debugging process (search-first, root cause over workarounds, etc.).

**UI jank / slow frames:** see [docs/PERFORMANCE.md](docs/PERFORMANCE.md) for progressive paint rules. Export a recording from DevTools Performance, then run `dart run tool/analyze_performance_json.dart <snapshot.json> --format summary` from `client/`. Full options: [docs/PERFORMANCE_ANALYSIS.md](docs/PERFORMANCE_ANALYSIS.md).

## Conventions

Full guidelines: **[docs/CODE_QUALITY.md](docs/CODE_QUALITY.md)**. Summary:

- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` (full setup: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)).
- **Touched a native dependency in `pubspec.yaml`? Also run `flutter build macos --debug`.** Analyze and the test suite cannot see a `pod install` failure, and neither can an iOS build — deployment targets differ per platform. Adding `speech_to_text` (which needs macOS 11.0 against a project targeting 10.15) broke the desktop build for an entire subproject before anyone compiled it. The same applies to `windows`/`linux` if you touch a plugin that ships native code for them.
- **Layering:** Route shells in `pages/`; **route-only** UI sections in `pages/<domain>/`; **cross-route design primitives** in `packages/shared_ui` as `Tp*`; **product/domain chrome** in `widgets/`; logic in `cubits/` + `services/` + `repositories/`; no `Process.run` or raw paths in UI; state is **`flutter_bloc` only** (not `provider`).
- **Shared UI:** New buttons, inputs, selects, dialogs, forms, deferred-mount helpers, etc. go in `client/packages/shared_ui` (`Tp*` + `TpTheme`). Do not add generic controls under `client/lib/widgets/`. Progressive open timeline: [docs/PERFORMANCE.md](docs/PERFORMANCE.md).
- **File size (soft):** page shells ~400, cubits ~500, services ~600 lines — split oversized screens into `pages/<domain>/` section files; keep `build()` free of IO.
- **Logging:** user errors → l10n; diagnostics → `AppLogger`; no `print`.
- Paths: `AppStorage` / `RuntimeContextRegistry` — never `Directory.current` for the default workspace directory.
- **Tests:** mock subprocess/filesystem via constructor injection; cubit tests that touch `AppStorage` use `setUpTestAppStorage()` / `tearDownTestAppStorage()` in `client/test/support/post_frame_test_harness.dart`.
- **All user-facing UI text MUST be internationalized** — never hardcode display strings (labels, titles, subtitles, tooltips, hints, snackbars, error text) in widgets. Add a key to both ARB files and reference it via `context.l10n.<key>`. Widget tests that render localized UI must wrap `MaterialApp` with `AppLocalizations.localizationsDelegates` + `supportedLocales` (+ `locale: const Locale('en')` to assert English literals).
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only; after ARB changes, re-run `dart run tool/gen_warmup_glyphs.dart` for `warmup_glyphs.g.dart`.
- Terminal input hooks: filter ANSI CSI sequences (`FirstUserLineCapture`).
- Do not commit `client/google_fonts/` (gitignored); run `dart run tool/sync_bundled_google_fonts.dart` when touching zh UI fonts.
- New integration tests: `@Tags(['integration'])` from `package:test` (see DEVELOPMENT.md).
</content>
</invoke>
