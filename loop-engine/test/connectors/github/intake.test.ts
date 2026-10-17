import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";

import { WebhookPayloadError, WebhookSignatureError } from "../../../src/connectors/connector";
import { GitHubIntake } from "../../../src/connectors/github/intake";
import { FakeGitHubClient } from "../../support/fake_github_client";

const SECRET = "s3cret";

const payload = JSON.stringify({
  action: "assigned",
  issue: {
    number: 42,
    title: "Fix login",
    body: null,
    html_url: "https://github.com/owner/repo/issues/42",
    created_at: "2026-01-01T00:00:00Z",
    user: { login: "Alice" },
    labels: [],
  },
  repository: { full_name: "owner/repo" },
  sender: { login: "Bob" },
  assignee: { login: "loop-agent" },
});

function signature(body: string, secret: string = SECRET): string {
  return `sha256=${createHmac("sha256", secret).update(body, "utf8").digest("hex")}`;
}

function headers(body: string, overrides: Record<string, string> = {}): Record<string, string> {
  return {
    "x-github-delivery": "delivery-1",
    "x-github-event": "issues",
    "x-hub-signature-256": signature(body),
    ...overrides,
  };
}

function makeIntake(webhookSecret?: string): GitHubIntake {
  return new GitHubIntake({ client: new FakeGitHubClient(), webhookSecret });
}

describe("GitHubIntake", () => {
  it("accepts a correctly signed webhook", async () => {
    const intake = makeIntake(SECRET);
    const events = await intake.handleWebhook({ headers: headers(payload), body: payload });
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ eventId: "delivery-1", kind: "ticket.assigned" });
  });

  it("rejects a wrong signature", async () => {
    const intake = makeIntake(SECRET);
    const bad = headers(payload, { "x-hub-signature-256": signature(payload, "wrong-secret") });
    await expect(intake.handleWebhook({ headers: bad, body: payload })).rejects.toBeInstanceOf(
      WebhookSignatureError,
    );
  });

  it("rejects a missing signature header when a secret is configured", async () => {
    const intake = makeIntake(SECRET);
    const bad = headers(payload);
    delete bad["x-hub-signature-256"];
    await expect(intake.handleWebhook({ headers: bad, body: payload })).rejects.toBeInstanceOf(
      WebhookSignatureError,
    );
  });

  it("skips verification when no secret is configured", async () => {
    const intake = makeIntake(undefined);
    const events = await intake.handleWebhook({ headers: headers(payload), body: payload });
    expect(events).toHaveLength(1);
  });

  it("rejects non-JSON bodies", async () => {
    const intake = makeIntake(SECRET);
    const body = "not json at all";
    await expect(intake.handleWebhook({ headers: headers(body), body })).rejects.toBeInstanceOf(
      WebhookPayloadError,
    );
  });

  it("rejects a missing delivery header", async () => {
    const intake = makeIntake(undefined);
    const bad = headers(payload);
    delete bad["x-github-delivery"];
    await expect(intake.handleWebhook({ headers: bad, body: payload })).rejects.toBeInstanceOf(
      WebhookPayloadError,
    );
  });

  it("returns no events for ping deliveries", async () => {
    const intake = makeIntake(SECRET);
    const body = JSON.stringify({ zen: "keep it simple" });
    const events = await intake.handleWebhook({
      headers: headers(body, { "x-github-event": "ping" }),
      body,
    });
    expect(events).toEqual([]);
  });

  it("reports the authenticated login lowercased", async () => {
    const client = new FakeGitHubClient();
    const intake = new GitHubIntake({ client });
    expect(await intake.selfIdentities()).toEqual(["loop-bot"]);
    await intake.selfIdentities();
    expect(client.loginRequests).toBe(1); // cached
  });
});
