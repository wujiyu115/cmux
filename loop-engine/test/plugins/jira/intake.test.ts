import { describe, expect, it } from "vitest";

import { JiraIntake } from "../../../plugins/jira/intake";
import type { JiraIssue } from "../../../plugins/jira/client";
import { FakeJiraClient } from "../../support/fake_jira_client";

const target = { project: "PROJ", assignees: ["acc-bot"], labels: ["loop"] };

function makeIntake(pollProjects = [target]) {
  const client = new FakeJiraClient();
  const intake = new JiraIntake({ client, pollProjects, ignoreActors: ["ci-bot"] });
  return { client, intake };
}

describe("JiraIntake", () => {
  it("parses webhook bodies into events via the client's browse urls", async () => {
    const { intake } = makeIntake();
    const body = JSON.stringify({
      webhookEvent: "jira:issue_updated",
      timestamp: 1,
      user: { accountId: "acc-actor" },
      issue: {
        key: "PROJ-1",
        fields: {
          project: { key: "PROJ" },
          summary: "Fix login",
          labels: [],
          assignee: { accountId: "acc-bot" },
          creator: { accountId: "acc-creator" },
          created: "2026-01-01T00:00:00Z",
          updated: "2026-01-02T00:00:00Z",
        },
      },
      changelog: { id: "cl-1", items: [{ field: "assignee", toString: "New" }] },
    });
    const events = await intake.handleWebhook({ headers: {}, body });
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ kind: "ticket.assigned", assignee: "acc-bot" });
    expect(events[0]).toMatchObject({
      ticket: { url: "https://x.atlassian.net/browse/PROJ-1", project: "PROJ" },
    });
  });

  it("rejects non-JSON bodies", async () => {
    const { intake } = makeIntake();
    await expect(intake.handleWebhook({ headers: {}, body: "nope" })).rejects.toThrow(/not valid JSON/);
    await expect(intake.handleWebhook({ headers: {}, body: {} })).rejects.toThrow(/raw string body/);
  });

  it("establishes a cursor on the first poll without emitting events", async () => {
    const { intake } = makeIntake();
    const result = await intake.poll(null);
    expect(result.events).toEqual([]);
    expect(result.cursor.at).toBeTruthy();
  });

  it("searches each project with a day-overlap JQL and maps snapshots", async () => {
    const { client, intake } = makeIntake();
    const issue: JiraIssue = {
      key: "PROJ-1",
      projectKey: "PROJ",
      summary: "Fix login",
      descriptionText: "",
      creatorAccountId: "acc-creator",
      labels: ["loop"],
      assigneeAccountId: "acc-bot",
      url: "https://x.atlassian.net/browse/PROJ-1",
      created: "2026-01-01T00:00:00Z",
      updated: "2026-01-02T00:00:00Z",
    };
    client.searchResults = [issue];
    const result = await intake.poll({ at: "2026-01-03T00:00:00Z" });
    expect(client.searchJqls).toEqual(['project = "PROJ" AND updated >= "2026-01-02"']);
    expect(result.events.map((e) => e.kind)).toEqual(["ticket.assigned", "ticket.labeled"]);
  });

  it("skips polling when no projects are configured", async () => {
    const { client, intake } = makeIntake([]);
    const result = await intake.poll({ at: "2026-01-03T00:00:00Z" });
    expect(result.events).toEqual([]);
    expect(client.searchJqls).toEqual([]);
  });

  it("reports self identities with the bot account, cached after first call", async () => {
    const { client, intake } = makeIntake();
    expect(await intake.selfIdentities()).toEqual(["jira-bot", "ci-bot"]);
    await intake.selfIdentities();
    expect(client.selfRequests).toBe(1);
  });
});
