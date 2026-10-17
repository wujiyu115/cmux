import { describe, expect, it } from "vitest";

import { mapJiraWebhook, mapPollIssue } from "../../../plugins/jira/mapper";
import type { JiraIssue } from "../../../plugins/jira/client";

const browse = (key: string): string => `https://x.atlassian.net/browse/${key}`;

function issueFields(overrides: Record<string, unknown> = {}) {
  return {
    project: { key: "PROJ" },
    summary: "Fix login",
    description: {
      type: "doc",
      content: [{ type: "paragraph", content: [{ type: "text", text: "steps to repro" }] }],
    },
    labels: ["bug"],
    assignee: { accountId: "acc-assignee" },
    creator: { accountId: "acc-creator" },
    created: "2026-01-01T00:00:00Z",
    updated: "2026-01-02T00:00:00Z",
    ...overrides,
  };
}

function updatePayload(changelog?: unknown, overrides: Record<string, unknown> = {}): unknown {
  return {
    webhookEvent: "jira:issue_updated",
    timestamp: 1700000000,
    user: { accountId: "acc-actor" },
    issue: { key: "PROJ-1", fields: issueFields() },
    ...(changelog !== undefined ? { changelog } : {}),
    ...overrides,
  };
}

function expectedTicket() {
  return {
    id: { connectorId: "jira", externalId: "PROJ-1" },
    project: "PROJ",
    title: "Fix login",
    body: "steps to repro\n",
    author: "acc-creator",
    labels: ["bug"],
    url: "https://x.atlassian.net/browse/PROJ-1",
    createdAt: "2026-01-01T00:00:00Z",
  };
}

describe("mapJiraWebhook", () => {
  it("maps assignee changelog items to ticket.assigned", () => {
    const payload = updatePayload({
      id: "cl-1",
      items: [{ field: "assignee", fromString: "Old User", toString: "New User" }],
    });
    expect(mapJiraWebhook(payload, browse)).toEqual([
      {
        eventId: "jira:PROJ-1:cl-1:assigned:acc-assignee",
        actor: "acc-actor",
        kind: "ticket.assigned",
        ticket: expectedTicket(),
        assignee: "acc-assignee",
      },
    ]);
  });

  it("maps only newly added labels from label changelog items", () => {
    const payload = updatePayload({
      id: "cl-2",
      items: [{ field: "labels", fromString: "bug, other", toString: "bug, loop, other" }],
    });
    const events = mapJiraWebhook(payload, browse);
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ kind: "ticket.labeled", label: "loop" });
    expect(events[0]!.eventId).toBe("jira:PROJ-1:cl-2:labeled:loop");
  });

  it("treats a missing fromString as an empty before-set", () => {
    const payload = updatePayload({
      id: "cl-3",
      items: [{ field: "labels", toString: "bug loop" }],
    });
    const labels = mapJiraWebhook(payload, browse).map((e) => (e as { label: string }).label);
    expect(labels).toEqual(["bug", "loop"]);
  });

  it("emits nothing for unassignment", () => {
    const payload = updatePayload(
      { id: "cl-4", items: [{ field: "assignee", fromString: "New User", toString: null }] },
      { issue: { key: "PROJ-1", fields: issueFields({ assignee: null }) } },
    );
    expect(mapJiraWebhook(payload, browse)).toEqual([]);
  });

  it("emits nothing for unrelated changelog items", () => {
    const payload = updatePayload({
      id: "cl-5",
      items: [{ field: "summary", fromString: "old", toString: "new" }],
    });
    expect(mapJiraWebhook(payload, browse)).toEqual([]);
  });

  it("maps comment_created payloads with ADF bodies", () => {
    const payload = {
      webhookEvent: "comment_created",
      user: { accountId: "acc-actor" },
      issue: { key: "PROJ-1", fields: issueFields() },
      comment: {
        id: "c-1",
        body: { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "any update?" }] }] },
        created: "2026-01-03T00:00:00Z",
        author: { accountId: "acc-commenter" },
      },
    };
    expect(mapJiraWebhook(payload, browse)).toEqual([
      {
        eventId: "jira:PROJ-1:comment:c-1",
        actor: "acc-actor",
        kind: "comment.created",
        comment: {
          ticketId: { connectorId: "jira", externalId: "PROJ-1" },
          externalId: "c-1",
          author: "acc-commenter",
          body: "any update?\n",
          createdAt: "2026-01-03T00:00:00Z",
        },
      },
    ]);
  });

  it("ignores other webhook events and malformed payloads", () => {
    expect(mapJiraWebhook({ webhookEvent: "jira:issue_created" }, browse)).toEqual([]);
    expect(mapJiraWebhook({ webhookEvent: "worklog_created" }, browse)).toEqual([]);
    expect(mapJiraWebhook("garbage", browse)).toEqual([]);
    expect(mapJiraWebhook({ webhookEvent: "jira:issue_updated", issue: {} }, browse)).toEqual([]);
  });
});

function makeIssue(overrides: Partial<JiraIssue> = {}): JiraIssue {
  return {
    key: "PROJ-1",
    projectKey: "PROJ",
    summary: "Fix login",
    descriptionText: "steps",
    creatorAccountId: "acc-creator",
    labels: ["bug", "loop"],
    assigneeAccountId: "acc-bot",
    url: "https://x.atlassian.net/browse/PROJ-1",
    created: "2026-01-01T00:00:00Z",
    updated: "2026-01-02T00:00:00Z",
    ...overrides,
  };
}

describe("mapPollIssue (jira)", () => {
  const target = { project: "PROJ", assignees: ["acc-bot"], labels: ["loop"] };

  it("emits assigned and labeled events for matching snapshots", () => {
    const events = mapPollIssue(makeIssue(), target);
    expect(events.map((e) => e.kind)).toEqual(["ticket.assigned", "ticket.labeled"]);
    expect(events[0]).toMatchObject({
      eventId: "poll:jira:PROJ-1:2026-01-02T00:00:00Z:assigned:acc-bot",
      actor: "acc-creator",
      assignee: "acc-bot",
    });
    expect(events[1]).toMatchObject({ label: "loop" });
  });

  it("emits nothing when no trigger matches", () => {
    expect(mapPollIssue(makeIssue({ assigneeAccountId: "acc-other", labels: ["bug"] }), target)).toEqual([]);
    expect(mapPollIssue(makeIssue({ assigneeAccountId: undefined }), target)).toHaveLength(1);
  });
});
