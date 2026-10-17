import { describe, expect, it } from "vitest";

import { GitHubIntake } from "../../../src/connectors/github/intake";
import type { SearchIssueItem } from "../../../src/connectors/github/client";
import { mapPollIssue } from "../../../src/connectors/github/mapper";
import { FakeGitHubClient } from "../../support/fake_github_client";

const target = { repo: "owner/repo", assignees: ["loop-agent"], labels: ["loop"] };

function makeItem(overrides: Partial<SearchIssueItem> = {}): SearchIssueItem {
  return {
    number: 42,
    title: "Fix login",
    body: "steps",
    htmlUrl: "https://github.com/owner/repo/issues/42",
    createdAt: "2026-01-01T00:00:00Z",
    updatedAt: "2026-01-02T00:00:00Z",
    authorLogin: "Alice",
    labels: ["bug"],
    ...overrides,
  };
}

describe("mapPollIssue", () => {
  it("emits an assigned event when the assignee matches a trigger", () => {
    const events = mapPollIssue(makeItem({ assigneeLogin: "Loop-Agent" }), target);
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({
      eventId: "poll:owner/repo#42:2026-01-02T00:00:00Z:assigned:loop-agent",
      actor: "alice",
      kind: "ticket.assigned",
      assignee: "loop-agent",
    });
  });

  it("emits labeled events only for trigger labels", () => {
    const events = mapPollIssue(makeItem({ labels: ["bug", "loop", "other"] }), target);
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ kind: "ticket.labeled", label: "loop" });
  });

  it("emits both assigned and labeled when both match", () => {
    const events = mapPollIssue(makeItem({ assigneeLogin: "loop-agent", labels: ["loop"] }), target);
    expect(events.map((e) => e.kind)).toEqual(["ticket.assigned", "ticket.labeled"]);
  });

  it("emits nothing when no trigger matches", () => {
    expect(mapPollIssue(makeItem({ assigneeLogin: "someone" }), target)).toEqual([]);
    expect(mapPollIssue(makeItem(), target)).toEqual([]);
  });

  it("ignores malformed items", () => {
    expect(mapPollIssue({ number: "nope" } as unknown as SearchIssueItem, target)).toEqual([]);
  });
});

describe("GitHubIntake.poll", () => {
  it("establishes a cursor on the first call without emitting events", async () => {
    const client = new FakeGitHubClient();
    const intake = new GitHubIntake({ client, pollTargets: [target] });
    const result = await intake.poll(null);
    expect(result.events).toEqual([]);
    expect(result.cursor.at).toBeTruthy();
    expect(client.searchQueries).toEqual([]);
  });

  it("searches each target repo and maps matching issues", async () => {
    const client = new FakeGitHubClient();
    client.searchResults = [makeItem({ assigneeLogin: "loop-agent", labels: ["loop"] })];
    const intake = new GitHubIntake({ client, pollTargets: [target] });
    const result = await intake.poll({ at: "2026-01-03T00:00:00Z" });
    expect(client.searchQueries).toEqual(["repo:owner/repo is:issue is:open updated:>=2026-01-02"]);
    expect(result.events.map((e) => e.kind)).toEqual(["ticket.assigned", "ticket.labeled"]);
  });

  it("produces stable event ids across polls of the same issue state", async () => {
    const client = new FakeGitHubClient();
    client.searchResults = [makeItem({ assigneeLogin: "loop-agent" })];
    const intake = new GitHubIntake({ client, pollTargets: [target] });
    const first = await intake.poll({ at: "2026-01-03T00:00:00Z" });
    const second = await intake.poll({ at: "2026-01-04T00:00:00Z" });
    expect(second.events.map((e) => e.eventId)).toEqual(first.events.map((e) => e.eventId));
  });

  it("returns no events when there are no poll targets", async () => {
    const client = new FakeGitHubClient();
    const intake = new GitHubIntake({ client });
    const result = await intake.poll({ at: "2026-01-03T00:00:00Z" });
    expect(result.events).toEqual([]);
  });
});
