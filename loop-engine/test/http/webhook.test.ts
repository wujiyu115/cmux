import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";

import { createGitHubConnector } from "../../src/connectors/github";
import { ConnectorRegistry } from "../../src/connectors/registry";
import type { IntakeEvent } from "../../src/domain/events";
import type { Ticket } from "../../src/domain/ticket";
import type { WorkRecord } from "../../src/domain/work";
import { createWebhookServer } from "../../src/http/webhook";
import { InMemoryWorkStore } from "../../src/store/store";
import { FakeGitHubClient } from "../support/fake_github_client";

const SECRET = "s3cret";

const assignedPayload = JSON.stringify({
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

function signature(body: string): string {
  return `sha256=${createHmac("sha256", SECRET).update(body, "utf8").digest("hex")}`;
}

function headers(body: string, overrides: Record<string, string> = {}): Record<string, string> {
  return {
    "content-type": "application/json",
    "x-github-delivery": "delivery-1",
    "x-github-event": "issues",
    "x-hub-signature-256": signature(body),
    ...overrides,
  };
}

function makeServer() {
  const registry = new ConnectorRegistry();
  registry.register(createGitHubConnector({ token: "t", webhookSecret: SECRET }, new FakeGitHubClient()));
  const received: IntakeEvent[] = [];
  const server = createWebhookServer({
    connectors: registry,
    onEvents: async (events) => {
      received.push(...events);
    },
  });
  return { server, received };
}

describe("webhook server", () => {
  it("routes signed webhooks to onEvents", async () => {
    const { server, received } = makeServer();
    const res = await server.inject({
      method: "POST",
      url: "/webhooks/github",
      headers: headers(assignedPayload),
      payload: assignedPayload,
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ received: 1 });
    expect(received).toHaveLength(1);
    expect(received[0]).toMatchObject({ kind: "ticket.assigned", eventId: "delivery-1" });
  });

  it("rejects invalid signatures with 401", async () => {
    const { server, received } = makeServer();
    const badSignature = "sha256=" + "0".repeat(64);
    const res = await server.inject({
      method: "POST",
      url: "/webhooks/github",
      headers: headers(assignedPayload, { "x-hub-signature-256": badSignature }),
      payload: assignedPayload,
    });
    expect(res.statusCode).toBe(401);
    expect(received).toHaveLength(0);
  });

  it("rejects malformed JSON with 400", async () => {
    const { server } = makeServer();
    const body = "not json";
    const res = await server.inject({
      method: "POST",
      url: "/webhooks/github",
      headers: headers(body),
      payload: body,
    });
    expect(res.statusCode).toBe(400);
  });

  it("returns 404 for unknown connectors", async () => {
    const { server } = makeServer();
    const res = await server.inject({
      method: "POST",
      url: "/webhooks/gitlab",
      headers: headers(assignedPayload),
      payload: assignedPayload,
    });
    expect(res.statusCode).toBe(404);
  });

  it("acknowledges ping deliveries without producing events", async () => {
    const { server, received } = makeServer();
    const body = JSON.stringify({ zen: "keep it simple" });
    const res = await server.inject({
      method: "POST",
      url: "/webhooks/github",
      headers: headers(body, { "x-github-event": "ping" }),
      payload: body,
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ received: 0 });
    expect(received).toHaveLength(0);
  });

  it("exposes a health check", async () => {
    const { server } = makeServer();
    const res = await server.inject({ method: "GET", url: "/healthz" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });
  });

  it("lists work history and serves full records by id", async () => {
    const store = new InMemoryWorkStore();
    const registry = new ConnectorRegistry();
    const ticket: Ticket = {
      id: { connectorId: "github", externalId: "owner/repo#1" },
      project: "owner/repo",
      title: "Fix login",
      body: "steps",
      author: "alice",
      labels: [],
      url: "https://github.com/owner/repo/issues/1",
      createdAt: "2026-01-01T00:00:00Z",
    };
    const record: WorkRecord = {
      id: "w1",
      ticket,
      status: "awaiting_review",
      attempt: 1,
      todos: [],
      runnerId: "claude",
      usage: { inputTokens: 0, outputTokens: 0 },
      branch: "loop/w1",
      prUrl: "https://github.com/owner/repo/pull/9",
      createdAt: "2026-01-01T00:00:00Z",
      updatedAt: "2026-01-01T00:01:00Z",
    };
    await store.create(record);

    const server = createWebhookServer({
      connectors: registry,
      onEvents: async () => {},
      store,
    });

    const listRes = await server.inject({ method: "GET", url: "/work" });
    expect(listRes.statusCode).toBe(200);
    expect(listRes.json()).toEqual([
      {
        id: "w1",
        status: "awaiting_review",
        attempt: 1,
        ticket: { title: "Fix login", url: "https://github.com/owner/repo/issues/1", project: "owner/repo" },
        usage: { inputTokens: 0, outputTokens: 0 },
        branch: "loop/w1",
        prUrl: "https://github.com/owner/repo/pull/9",
        lastError: undefined,
        createdAt: "2026-01-01T00:00:00Z",
        updatedAt: "2026-01-01T00:01:00Z",
      },
    ]);

    const detailRes = await server.inject({ method: "GET", url: "/work/w1" });
    expect(detailRes.statusCode).toBe(200);
    expect(detailRes.json()).toEqual(record);

    const missingRes = await server.inject({ method: "GET", url: "/work/nope" });
    expect(missingRes.statusCode).toBe(404);
  });

  it("omits the work routes when no store is provided", async () => {
    const { server } = makeServer();
    const res = await server.inject({ method: "GET", url: "/work" });
    expect(res.statusCode).toBe(404);
  });
});
