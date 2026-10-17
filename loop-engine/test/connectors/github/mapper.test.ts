import { describe, expect, it } from "vitest";

import type { IntakeEvent } from "../../../src/domain/events";
import type { Ticket } from "../../../src/domain/ticket";
import { mapGitHubWebhook, parseIssueRef } from "../../../src/connectors/github/mapper";

const baseIssue = {
  number: 42,
  title: "Fix login",
  body: "steps to repro",
  html_url: "https://github.com/owner/repo/issues/42",
  created_at: "2026-01-01T00:00:00Z",
  user: { login: "Alice" },
  labels: [{ name: "bug" }, { name: "loop" }],
};

function issuesPayload(action: string, extra: Record<string, unknown> = {}): unknown {
  return {
    action,
    issue: baseIssue,
    repository: { full_name: "owner/repo" },
    sender: { login: "Bob" },
    ...extra,
  };
}

function assignedEvent(payload: unknown): IntakeEvent | null {
  return mapGitHubWebhook("delivery-1", "issues", payload);
}

describe("mapGitHubWebhook", () => {
  it("maps issues.assigned with lowercased logins", () => {
    const event = assignedEvent(issuesPayload("assigned", { assignee: { login: "Loop-Agent" } }));
    expect(event).toEqual({
      eventId: "delivery-1",
      actor: "bob",
      kind: "ticket.assigned",
      ticket: expectedTicket(),
      assignee: "loop-agent",
    });
  });

  it("maps issues.labeled", () => {
    const event = assignedEvent(issuesPayload("labeled", { label: { name: "loop" } }));
    expect(event).toEqual({
      eventId: "delivery-1",
      actor: "bob",
      kind: "ticket.labeled",
      ticket: expectedTicket(),
      label: "loop",
    });
  });

  it("maps issue_comment created", () => {
    const payload = {
      action: "created",
      issue: baseIssue,
      comment: { id: 77, body: "any update?", created_at: "2026-01-02T00:00:00Z", user: { login: "Carol" } },
      repository: { full_name: "owner/repo" },
      sender: { login: "Carol" },
    };
    const event = mapGitHubWebhook("delivery-2", "issue_comment", payload);
    expect(event).toEqual({
      eventId: "delivery-2",
      actor: "carol",
      kind: "comment.created",
      comment: {
        ticketId: { connectorId: "github", externalId: "owner/repo#42" },
        externalId: "77",
        author: "carol",
        body: "any update?",
        createdAt: "2026-01-02T00:00:00Z",
      },
    });
  });

  it("ignores unmapped actions", () => {
    expect(assignedEvent(issuesPayload("opened"))).toBeNull();
    expect(assignedEvent(issuesPayload("assigned"))).toBeNull(); // missing assignee
    expect(assignedEvent(issuesPayload("labeled"))).toBeNull(); // missing label
  });

  it("ignores issue_comment edits and deletes", () => {
    const payload = { action: "edited", issue: baseIssue, comment: {}, repository: {}, sender: {} };
    expect(mapGitHubWebhook("d", "issue_comment", payload)).toBeNull();
  });

  it("ignores other event types like ping and pull_request", () => {
    expect(mapGitHubWebhook("d", "ping", { zen: "keep it simple" })).toBeNull();
    expect(mapGitHubWebhook("d", "pull_request", { action: "opened" })).toBeNull();
    expect(mapGitHubWebhook("d", undefined, {})).toBeNull();
  });

  it("ignores malformed payloads", () => {
    expect(assignedEvent({ action: "assigned", issue: { number: "not-a-number" } })).toBeNull();
    expect(assignedEvent("garbage")).toBeNull();
  });
});

function expectedTicket(): Ticket {
  return {
    id: { connectorId: "github", externalId: "owner/repo#42" },
    project: "owner/repo",
    title: "Fix login",
    body: "steps to repro",
    author: "alice",
    labels: ["bug", "loop"],
    url: "https://github.com/owner/repo/issues/42",
    createdAt: "2026-01-01T00:00:00Z",
  };
}

describe("parseIssueRef", () => {
  it("parses owner/repo#number", () => {
    expect(parseIssueRef("owner/repo#42")).toEqual({ owner: "owner", repo: "repo", number: 42 });
  });

  it("rejects malformed refs", () => {
    expect(() => parseIssueRef("owner/repo")).toThrow();
    expect(() => parseIssueRef("https://github.com/owner/repo/issues/42")).toThrow();
  });
});
