# Workspace agent-status indicator (left nav) — design

Date: 2026-08-27
Status: approved (user confirmed scope: working / waiting / interrupted / done as distinct visuals; workspace rows only, no group-header aggregation)

## Problem

The left workspace nav (`WorkspaceNavSidebar`) only shows a "selected" rail. Agent
lifecycle state (working / waiting / done / interrupted) is visible only at
session level (session tabs + session sidebar tiles). Users switching workspaces
lose the at-a-glance signal that a workspace has an agent running, waiting for
approval, or finished while they were away.

## Source of truth

`AgentAttentionCubit` (seat map `sessionId\0memberId` → `AgentSeatAttention`
working/waiting/done, 30-min TTL, `lastEvent.interrupted` marks an interrupted
Stop). `ChatCubit.state.workingSessionIds` is a legacy remnant that is always
empty in production and is NOT used.

sessionId → workspaceId mapping: `ChatCubit.state.sessions`
(`AppSession.workspaceId`), fully loaded at boot.

## Design

### 1. Status model — `cubits/agent_attention_cubit.dart`

```dart
enum WorkspaceAgentStatus { none, waiting, working, interrupted, done }
```

New pure query on `AgentAttentionState`:

```dart
WorkspaceAgentStatus workspaceAgentStatus(Set<String> sessionIds)
```

Iterates seats; skips stale entries (same TTL as `attentionFor`) and seats whose
sessionId is not in `sessionIds`. `interrupted` = `done && lastEvent.interrupted`.
Multi-session priority (most action needed first):
**waiting > working > interrupted > done > none**.

### 2. Indicator widget — new `client/lib/widgets/workspace_agent_status_indicator.dart`

| Status | Visual | Color |
|---|---|---|
| working | reuse `SessionWorkingSpinner` | `cs.primary` |
| waiting | reuse `SessionWaitingMarker` | `cs.tertiary` |
| interrupted | `Icons.stop_circle_rounded`, static | `cs.error` |
| done | `Icons.check_circle_rounded`, static | `cs.secondary` (app success green, matches toast success variant) |

Size 13 (session-indicator scale). Renders `SizedBox.shrink()` for `none`.
Interrupted/done colors align with the notification service (warning / success
toast variants). Not exported into shared_ui — single consumer, product chrome
belongs in `widgets/`.

### 3. Row integration — `pages/home_workspace/workspace_nav_sidebar.dart`

`_WorkspaceNavRow` gains an internal `context.select`:

- select `ChatCubit` → `List<AppSession>` filtered to this workspace (deep-equal
  list keeps rebuilds scoped; the seat map is small so per-row compute is cheap).
- select `AgentAttentionCubit` → `WorkspaceAgentStatus` via the pure query.

Indicator placed after the workspace name, before the constant-size close slot;
wrapped in a `Tooltip` (l10n strings). Hover/close chrome unchanged.

### 4. l10n

New keys in both ARB files: `workspaceNavAgentWorking`, `workspaceNavAgentWaiting`,
`workspaceNavAgentInterrupted`, `workspaceNavAgentDone`. Re-run
`dart run tool/gen_warmup_glyphs.dart` after ARB edits.

### 5. Tests

- Unit: `workspaceAgentStatus` — priority ordering, interrupted vs done, stale
  pruning, cross-workspace isolation, empty input.
- Widget: sidebar rows render the expected indicator icon per status for the
  right workspace (existing widget-test harness conventions).

## Non-goals

Group-header aggregation, home-pane workspace cards, session-level indicator
changes, removing the dead `workingSessionIds` field.

## Persistence note

done/interrupted persist until the next event or the 30-min TTL (or tab close,
which clears seats) — that is the "something finished while I was away" signal.
