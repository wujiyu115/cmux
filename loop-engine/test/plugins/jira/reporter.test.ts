import { describe, expect, it } from "vitest";

import { createJiraConnector } from "../../../plugins/jira";
import type { Ticket } from "../../../src/domain/ticket";
import { FakeJiraClient } from "../../support/fake_jira_client";

const ticket: Ticket = {
  id: { connectorId: "jira", externalId: "PROJ-1" },
  project: "PROJ",
  title: "Fix login",
  body: "steps",
  author: "acc-creator",
  labels: ["bug"],
  url: "https://x.atlassian.net/browse/PROJ-1",
  createdAt: "2026-01-01T00:00:00Z",
};

function makeConnector(transitions: { inProgress: string; blocked?: string }) {
  const client = new FakeJiraClient();
  const connector = createJiraConnector(
    {
      baseUrl: "https://x.atlassian.net",
      email: "e",
      apiToken: "t",
      transitions,
      ignoreActors: [],
      pollProjects: [],
    },
    client,
  );
  return { client, connector };
}

describe("JiraReporter", () => {
  it("claims via the in-progress transition, matched case-insensitively by name", async () => {
    const { client, connector } = makeConnector({ inProgress: "In Progress" });
    client.transitionsByIssue["PROJ-1"] = [
      { id: "11", name: "in progress" },
      { id: "31", name: "Done" },
    ];
    await connector.reporter!.claim(ticket);
    expect(client.transitionCalls).toEqual([{ issueKey: "PROJ-1", transitionId: "11" }]);
  });

  it("fails loudly when the transition name does not exist", async () => {
    const { client, connector } = makeConnector({ inProgress: "In Progress" });
    client.transitionsByIssue["PROJ-1"] = [{ id: "31", name: "Done" }];
    await expect(connector.reporter!.claim(ticket)).rejects.toThrow(/not found on PROJ-1.*Done/);
  });

  it("posts progress and results as comments", async () => {
    const { client, connector } = makeConnector({ inProgress: "In Progress" });
    await connector.reporter!.postProgress(ticket, "planned 2 todos");
    await connector.reporter!.postResult(ticket, "done", "https://github.com/o/r/pull/9");
    expect(client.comments).toEqual([
      { issueKey: "PROJ-1", body: "planned 2 todos" },
      { issueKey: "PROJ-1", body: "done\n\nPull request: https://github.com/o/r/pull/9" },
    ]);
  });

  it("fails with a comment plus the blocked transition when configured", async () => {
    const { client, connector } = makeConnector({ inProgress: "In Progress", blocked: "Blocked" });
    client.transitionsByIssue["PROJ-1"] = [{ id: "41", name: "Blocked" }];
    await connector.reporter!.fail(ticket, "verification failed: test");
    expect(client.comments[0]!.body).toContain("verification failed: test");
    expect(client.transitionCalls).toEqual([{ issueKey: "PROJ-1", transitionId: "41" }]);
  });

  it("omits the blocked transition when not configured", async () => {
    const { client, connector } = makeConnector({ inProgress: "In Progress" });
    await connector.reporter!.fail(ticket, "boom");
    expect(client.comments).toHaveLength(1);
    expect(client.transitionCalls).toEqual([]);
  });

  it("implements no git-side capabilities", () => {
    const { connector } = makeConnector({ inProgress: "In Progress" });
    expect(connector.reporter!.openPullRequest).toBeUndefined();
    expect(connector.reporter!.getPullState).toBeUndefined();
    expect(connector.reporter!.markDone).toBeUndefined();
  });
});
