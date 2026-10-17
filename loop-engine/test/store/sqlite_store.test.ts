import { describe, expect, it } from "vitest";

import type { Ticket } from "../../src/domain/ticket";
import type { WorkRecord } from "../../src/domain/work";
import { SqliteWorkStore } from "../../src/store/sqlite_store";

function makeTicket(): Ticket {
  return {
    id: { connectorId: "github", externalId: "owner/repo#1" },
    project: "owner/repo",
    title: "Fix login bug",
    body: "Login fails.",
    author: "alice",
    labels: ["bug"],
    url: "https://github.com/owner/repo/issues/1",
    createdAt: "2026-01-01T00:00:00.000Z",
  };
}

function makeRecord(id: string, overrides: Partial<WorkRecord> = {}): WorkRecord {
  return {
    id,
    ticket: makeTicket(),
    status: "claimed",
    attempt: 0,
    todos: [{ text: "a", status: "pending" }],
    runnerId: "claude",
    usage: { inputTokens: 5, outputTokens: 7 },
    branch: `loop/${id}`,
    worktreeDir: `/tmp/wt/${id}`,
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    ...overrides,
  };
}

describe("SqliteWorkStore", () => {
  it("round-trips records", async () => {
    const store = new SqliteWorkStore(":memory:");
    const record = makeRecord("r1", { agentSummary: "summary", prUrl: "pr-url", lastError: "boom" });
    await store.create(record);
    expect(await store.get("r1")).toEqual(record);
    expect(await store.get("missing")).toBeUndefined();
  });

  it("persists updates to mutable fields", async () => {
    const store = new SqliteWorkStore(":memory:");
    const record = makeRecord("r1");
    await store.create(record);

    record.status = "awaiting_review";
    record.attempt = 2;
    record.usage = { inputTokens: 12, outputTokens: 34 };
    record.prUrl = "https://github.com/owner/repo/pull/9";
    record.lastError = undefined;
    await store.update(record);

    const loaded = await store.get("r1");
    expect(loaded).toMatchObject({
      status: "awaiting_review",
      attempt: 2,
      usage: { inputTokens: 12, outputTokens: 34 },
      prUrl: "https://github.com/owner/repo/pull/9",
    });
    expect(loaded!.lastError).toBeUndefined();
  });

  it("finds active records for a ticket only", async () => {
    const store = new SqliteWorkStore(":memory:");
    const record = makeRecord("r1");
    await store.create(record);
    expect(await store.findActiveByTicket(record.ticket.id)).toBeDefined();

    record.status = "done";
    await store.update(record);
    expect(await store.findActiveByTicket(record.ticket.id)).toBeUndefined();

    record.status = "failed";
    await store.update(record);
    expect(await store.findActiveByTicket(record.ticket.id)).toBeUndefined();
  });

  it("serves the oldest actionable record first", async () => {
    const store = new SqliteWorkStore(":memory:");
    await store.create(makeRecord("r1", { createdAt: "2026-01-01T00:00:01.000Z" }));
    await store.create(makeRecord("r2", { createdAt: "2026-01-01T00:00:00.000Z" }));
    expect((await store.nextActionable())!.id).toBe("r2");

    const done = makeRecord("r2", { createdAt: "2026-01-01T00:00:00.000Z", status: "done" });
    await store.update(done);
    expect((await store.nextActionable())!.id).toBe("r1");
  });

  it("dedups events", async () => {
    const store = new SqliteWorkStore(":memory:");
    expect(await store.hasEvent("e1")).toBe(false);
    await store.markEvent("e1");
    expect(await store.hasEvent("e1")).toBe(true);
    await store.markEvent("e1"); // insert-or-ignore, must not throw
    expect(await store.hasEvent("e1")).toBe(true);
  });

  it("round-trips poll cursors per connector", async () => {
    const store = new SqliteWorkStore(":memory:");
    expect(await store.getPollCursor("github")).toBeNull();
    await store.savePollCursor("github", { at: "2026-01-01T00:00:00Z" });
    expect(await store.getPollCursor("github")).toEqual({ at: "2026-01-01T00:00:00Z" });
    await store.savePollCursor("github", { at: "2026-01-02T00:00:00Z" });
    expect(await store.getPollCursor("github")).toEqual({ at: "2026-01-02T00:00:00Z" });
    expect(await store.getPollCursor("jira")).toBeNull();
  });
});
