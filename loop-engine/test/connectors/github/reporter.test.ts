import { describe, expect, it } from "vitest";

import { createGitHubConnector } from "../../../src/connectors/github";
import type { PullRequestSpec } from "../../../src/connectors/connector";
import type { Ticket } from "../../../src/domain/ticket";
import { FakeGitHubClient } from "../../support/fake_github_client";

const ticket: Ticket = {
  id: { connectorId: "github", externalId: "owner/repo#42" },
  project: "owner/repo",
  title: "Fix login",
  body: "steps",
  author: "alice",
  labels: ["bug"],
  url: "https://github.com/owner/repo/issues/42",
  createdAt: "2026-01-01T00:00:00Z",
};

function makeConnector() {
  const client = new FakeGitHubClient();
  const connector = createGitHubConnector({ token: "t" }, client);
  return { client, connector };
}

describe("GitHubReporter", () => {
  it("claim adds the in-progress label", async () => {
    const { client, connector } = makeConnector();
    await connector.reporter!.claim(ticket);
    expect(client.labelCalls).toEqual([
      { owner: "owner", repo: "repo", number: 42, labels: ["loop-in-progress"] },
    ]);
  });

  it("postProgress comments on the issue", async () => {
    const { client, connector } = makeConnector();
    await connector.reporter!.postProgress(ticket, "planned 2 todos");
    expect(client.comments).toHaveLength(1);
    expect(client.comments[0]).toMatchObject({ owner: "owner", repo: "repo", number: 42 });
    expect(client.comments[0]!.body).toBe("planned 2 todos");
  });

  it("opens a pull request against spec.repo", async () => {
    const { client, connector } = makeConnector();
    const spec: PullRequestSpec = {
      title: "Fix login",
      body: "summary",
      head: "loop/abc",
      base: "main",
      repo: "owner/repo",
    };
    const result = await connector.reporter!.openPullRequest!(ticket, spec);
    expect(result.url).toBe("https://github.com/owner/repo/pull/9");
    // repo routes the call; it is not forwarded to the GitHub API params
    expect(client.pullRequests).toEqual([
      {
        owner: "owner",
        repo: "repo",
        params: { title: "Fix login", body: "summary", head: "loop/abc", base: "main" },
      },
    ]);
  });

  it("returns the existing PR when one is already open for the head (idempotent retry)", async () => {
    const { client, connector } = makeConnector();
    client.existingPulls["loop/abc"] = "https://github.com/owner/repo/pull/7";
    const spec: PullRequestSpec = {
      title: "Fix login",
      body: "summary",
      head: "loop/abc",
      base: "main",
      repo: "owner/repo",
    };
    const result = await connector.reporter!.openPullRequest!(ticket, spec);
    expect(result.url).toBe("https://github.com/owner/repo/pull/7");
  });

  it("opens pull requests for tickets raised in other systems", async () => {
    const { client, connector } = makeConnector();
    const external: Ticket = {
      ...ticket,
      id: { connectorId: "generic-webhook", externalId: "alert-1" },
    };
    await connector.reporter!.openPullRequest!(external, {
      title: "Fix login",
      body: "summary",
      head: "loop/abc",
      base: "main",
      repo: "other/repo",
    });
    expect(client.pullRequests[0]).toMatchObject({ owner: "other", repo: "repo" });
  });

  it("postResult appends the PR url", async () => {
    const { client, connector } = makeConnector();
    await connector.reporter!.postResult(ticket, "done", "https://github.com/owner/repo/pull/9");
    expect(client.comments[0]!.body).toBe("done\n\nPull request: https://github.com/owner/repo/pull/9");
  });

  it("fail labels needs-human and explains why", async () => {
    const { client, connector } = makeConnector();
    await connector.reporter!.fail(ticket, "verification failed: test");
    expect(client.labelCalls).toEqual([
      { owner: "owner", repo: "repo", number: 42, labels: ["loop-needs-human"] },
    ]);
    expect(client.comments[0]!.body).toContain("verification failed: test");
  });

  it("uses custom label names when configured", async () => {
    const client = new FakeGitHubClient();
    const connector = createGitHubConnector(
      { token: "t", labels: { inProgress: "agent-working", needsHuman: "agent-stuck" } },
      client,
    );
    await connector.reporter!.claim(ticket);
    expect(client.labelCalls[0]!.labels).toEqual(["agent-working"]);
  });

  it("getPullState reports merged, closed and open PRs", async () => {
    const { client, connector } = makeConnector();
    const prUrl = "https://github.com/owner/repo/pull/9";
    expect(await connector.reporter!.getPullState!(ticket, prUrl)).toBe("open");

    client.pullRequestStates["owner/repo#9"] = { state: "closed", merged: true };
    expect(await connector.reporter!.getPullState!(ticket, prUrl)).toBe("merged");

    client.pullRequestStates["owner/repo#9"] = { state: "closed", merged: false };
    expect(await connector.reporter!.getPullState!(ticket, prUrl)).toBe("closed");
  });

  it("getPullState rejects urls without a pull number", async () => {
    const { connector } = makeConnector();
    await expect(
      connector.reporter!.getPullState!(ticket, "https://github.com/owner/repo"),
    ).rejects.toThrow(/cannot parse pull request url/);
  });

  it("markDone removes the in-progress label", async () => {
    const { client, connector } = makeConnector();
    await connector.reporter!.markDone!(ticket);
    expect(client.removedLabels).toEqual([
      { owner: "owner", repo: "repo", number: 42, name: "loop-in-progress" },
    ]);
  });
});
