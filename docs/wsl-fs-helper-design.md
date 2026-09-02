# WSL resident fs-helper (design, not yet implemented)

Status: **design only** — nothing in this doc is in the codebase yet. It is the
follow-up to the 2026-09 quick-open latency work.

## Problem

Every `WslFilesystem` operation spawns a `wsl.exe` process. Measured on the
dev machine (WSL 2.7.12, Ubuntu 20.04): each spawn costs a fixed **~350 ms**
regardless of the command — even `wsl.exe --exec true` pays it. The cost is
process creation plus the Windows→Linux boundary crossing, not the work the
command does.

Consequences (all measured end-to-end, before the 2026-09 fixes):

| Path | Spawn count | Latency |
|------|-------------|---------|
| Ctrl+P → Enter → editor has content | 14 serial spawns | ~6.0 s |
| `VersionedJsonStore.write` (sessions, layout, config, MRU all use it) | 12 round trips | ~4.2 s |
| File tree: expand one directory | 1+ | ~350 ms |
| Git panel: every operation | 1+ | ~350 ms + git itself |

The 2026-09 fixes (batched stat+read, batched MRU existence check, fire-and-forget
MRU touch) cut the critical path to ~390 ms and made the rest background noise,
but every operation still pays the fixed spawn tax.

## Goal

Replace the per-operation `wsl.exe` spawn with a round trip over a long-lived
stdio pipe to one resident helper process in the distro:

- Small operations: ~2–5 ms instead of ~350 ms.
- Fallback to the current per-spawn path must be always available; worst case
  equals today's behavior.
- Zero new attack surface: stdio only, no network listener, no new host ports.

## Architecture

```
Flutter (Windows)                          WSL distro
┌──────────────────────┐    stdin  (request line)   ┌─────────────────────────────┐
│ WslFilesystem        │ ─────────────────────────▶ │ python3 fs-helper-v1.py     │
│  ├ helper available? │                            │  read line → dispatch →     │
│  │  └ WslFsHelperClient (per-distro singleton)   │  print line + flush         │
│  └ no / died → existing per-spawn path (kept)     │  idle 60 s → self-exit      │
└──────────────────────┘ ◀───────────────────────── └─────────────────────────────┘
                           stdout (response line)
```

- **Helper process**: `wsl.exe -d <distro> --exec python3
  ~/.local/share/com.hhoa.teampilot/bin/fs-helper-v1.py`. Stdio only.
- **Dart side**: `WslFsHelperClient`, one instance per distro in a static
  registry. `RuntimeContextRegistry` caches one `WslFilesystem` per target id
  and has no dispose hook, so the helper's lifetime must be self-managed
  (see Lifecycle).
- **Fallback**: the entire existing per-spawn implementation stays. The helper
  is a fast path in front of it, never a replacement. Tests that inject a
  `processRunner` never start the helper, so the existing suite is unaffected.

## Why python3

The helper must parse a framed protocol, execute arbitrary fs operations, and
move binary safely — shell cannot do this reliably (no arrays, no exceptions,
quoting hell; see the historical `stat` format-string bug noted in
`wsl_filesystem.dart`). Mainstream distro images ship python3 in the base
system (dev machine: 3.8.10); `os`/`shutil`/`base64` cover the whole
operation set in ~200 lines, compatible with python ≥3.6 syntax.

It is **not a hard dependency**: no python3 / failed handshake → helper
disabled for the session, everything runs the fallback path.

The protocol is the seam for a future static binary (Go/Rust shipped in the
Windows package): swapping the payload only touches script delivery, not the
client or protocol.

## Protocol

Line-oriented, FIFO, all fields base64 (path-safety, binary-safety, no quoting):

```
request:  <id> <op> <b64 field> <b64 field>...
response: <id> <rc> <b64 field>...
startup:  helper prints READY <protoVersion>
```

One request in flight at a time (Dart-side serialized queue). That is plenty:
hundreds of ops/sec, and a file-tree burst of 20 stats costs ~40 ms.

Large payloads (a 2 MB file → ~2.7 MB base64 on one line) are equivalent in
memory to today's `Process.run` full-collection behavior.

### Operations

| Op | Python | Notes |
|----|--------|-------|
| `stat` | `os.stat`/`os.lstat` | kind/size/mtime like `stat -c %F|%s|%Y` |
| `read` | open+read | `max` bytes cap |
| `write`/`append` | open+write | |
| `rename` | mkdirs + rmtree target + `os.rename` | replaces today's 3 spawns |
| `exists` / `existsmany` | `os.path.exists` | one flag per path |
| `listdir` | `os.scandir` | |
| `listdirrecursive` | `os.walk(followlinks=False)` | matches current `find` behavior |
| `readlink` / `realpath` / `symlink` | `os.readlink`/`os.path.realpath`/`os.symlink` | |
| `copytree` / `copyfile` | `shutil` | |
| `ensuredir` / `rmrf` / `readrange` / `mkdtemp` | `os`/`tempfile` | |
| `exec` | `subprocess.run` | for the git runner: argv + cwd, returns exit + b64 stdout/stderr |

Script lives as a Dart string constant (`wsl_fs_helper_script.dart`), filename
carries the version, app upgrade replaces it automatically.

## Lifecycle

`RuntimeContextRegistry` never disposes the filesystems it caches, and the
helper must not outlive its usefulness — so the design avoids needing any
dispose wiring:

| Event | Behavior |
|-------|----------|
| First operation | Lazy start: write script once via existing `writeString` (~350 ms, once per session), `Process.start`, await `READY` |
| Idle | Helper self-exits after 60 s with no request (WSL VM can then idle-shutdown normally); Dart side sees EOF, clears the registry slot, next op restarts it |
| App exit / crash | Flutter process dies → OS closes stdin → wsl.exe forwards EOF → python exits. Orphans self-reap; no app-side cleanup code |
| Mid-flight death (`wsl --shutdown`) | In-flight request fails as transport error (distinct from "file not found") → kill process, restart helper, retry that op once, then surface |
| No python3 / handshake fail / protocol mismatch | Disable helper for the session (with backoff), always fall back, log once |

## Change plan

| File | Change |
|------|--------|
| `services/io/wsl_fs_helper_script.dart` (new) | Embedded python script + protocol version |
| `services/io/wsl_fs_helper.dart` (new) | `WslFsHelperClient`: start/handshake/queue/EOF/retry/registry; constructor injection for tests |
| `services/io/wsl_filesystem.dart` | Helper fast path per method (~3 lines each), fallback preserved; `FsBatchOps` methods become single round trips |
| `services/git/git_command_runner.dart` | `WslGitCommandRunner.runInDirectory` → helper `exec`, fallback to `WslHostOneShotRunner` |
| tests | Protocol/queue/handshake/EOF/retry unit tests with fake transport; helper-vs-fallback selection tests; `@Tags(['integration'])` real-wsl round trips |

Unchanged: `Filesystem` interface, `RuntimeContextRegistry`, all callers,
SFTP/local backends.

## Expected results

Based on the measured 350 ms/spawn and typical 2–5 ms pipe round trips:

| Path | Today (post 2026-09 fixes) | With helper |
|------|------------------------------|-------------|
| Ctrl+P Enter → editor content | ~390 ms | ~5–10 ms |
| MRU touch (background) | ~4.2 s | ~20 ms |
| File tree expand | ~350 ms+ | ~2–5 ms |
| Git panel op | ~350 ms + git | git + ~3 ms |
| `VersionedJsonStore.write` | 12 round trips | 2 round trips (backup + primary) |

## Alternatives considered (rejected)

- **Localhost HTTP daemon in the distro** — depends on WSL2 port forwarding
  (mirrored networking / firewall differences) and adds a listening surface.
  stdio avoids both.
- **Resident raw `sh` speaking commands** — quoting hell, no framing, no way
  to distinguish transport failure from file-not-found.
- **Operation merging only** (atomicWrite 4→1 etc.) — does not help the file
  tree's per-node stats or the git panel; both become free once the helper
  exists.

## Risks

1. **wsl.exe stdin relay** — `_pipeBase64ToFile` already proves
   `Process.start` + stdin piping works; the only difference is keeping the
   pipe open.
2. **python3 dependency** — Ubuntu-family default; exotic images (Alpine
   minimal) fall back to today's behavior. Disabled state is logged once,
   not spammed.
3. **Helper keep-alive delays VM idle-shutdown** — bounded by the 60 s
   self-exit; resident python3 costs ~15–20 MB (machine is configured with
   25 GB).

## Suggested implementation order

1. Helper client + script + handshake/fallback skeleton + fake-transport unit
   tests.
2. `WslFilesystem` hot paths first (stat, read, write, list, batch ops,
   rename, atomicWrite), then the remaining ops.
3. Git runner `exec`.
4. Integration tests + manual verification (Ctrl+P, file tree, git panel,
   MRU) + before/after timing.
