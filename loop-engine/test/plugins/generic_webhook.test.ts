import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";

import type { IntakeEvent } from "../../src/domain/events";
import plugin from "../../plugins/generic-webhook/plugin";

const SECRET = "s3cret";

async function makeConnector(config: Record<string, unknown> = {}) {
  return plugin.createConnector({ config: { secret: SECRET, ...config }, projects: [] });
}

function sign(body: string, secret: string = SECRET): string {
  return `sha256=${createHmac("sha256", secret).update(body, "utf8").digest("hex")}`;
}

function post(
  intake: NonNullable<Awaited<ReturnType<typeof plugin.createConnector>>["intake"]>,
  body: string,
  headers: Record<string, string> = {},
): Promise<IntakeEvent[]> {
  return intake.handleWebhook({
    headers: { "x-signature-256": sign(body), ...headers },
    body,
  });
}

async function eventsFor(
  connector: Awaited<ReturnType<typeof makeConnector>>,
  body: string,
  headers: Record<string, string> = {},
): Promise<IntakeEvent[]> {
  return post(connector.intake!, body, headers);
}

describe("generic-webhook plugin", () => {
  it("maps assignee and labels to trigger events with stable ids", async () => {
    const connector = await makeConnector();
    const body = JSON.stringify({
      id: "alert-1",
      project: "owner/repo",
      title: "Disk full on db-1",
      description: "Disk usage above 90%",
      labels: ["loop", "ops"],
      assignee: "loop-agent",
      author: "monitor",
    });
    const events = await eventsFor(connector, body);
    expect(events.map((e) => e.kind)).toEqual(["ticket.assigned", "ticket.labeled", "ticket.labeled"]);
    expect(events[0]).toMatchObject({
      eventId: "generic-webhook:alert-1:assigned",
      actor: "monitor",
      assignee: "loop-agent",
    });
    expect(events[1]).toMatchObject({ eventId: "generic-webhook:alert-1:labeled:loop", label: "loop" });
    expect(events[2]).toMatchObject({ eventId: "generic-webhook:alert-1:labeled:ops", label: "ops" });
    expect(events[0]).toMatchObject({
      ticket: {
        id: { connectorId: "generic-webhook", externalId: "alert-1" },
        project: "owner/repo",
        title: "Disk full on db-1",
        body: "Disk usage above 90%",
        url: "generic-webhook:alert-1",
      },
    });
  });

  it("emits label events only when no assignee is present", async () => {
    const connector = await makeConnector();
    const body = JSON.stringify({ id: "alert-2", project: "owner/repo", title: "CPU high", labels: ["loop"] });
    const events = await eventsFor(connector, body);
    expect(events.map((e) => e.kind)).toEqual(["ticket.labeled"]);
  });

  it("applies defaults for optional fields", async () => {
    const connector = await makeConnector();
    const body = JSON.stringify({ id: "alert-3", project: "owner/repo", title: "Bare alert" });
    const events = await eventsFor(connector, body);
    expect(events).toEqual([]);
    // labels default to [] so no events fire, but the payload itself is valid;
    // a bare ticket with no trigger info produces no trigger events.
  });

  it("rejects invalid signatures", async () => {
    const connector = await makeConnector();
    const body = JSON.stringify({ id: "a", project: "p", title: "t" });
    await expect(eventsFor(connector, body, { "x-signature-256": sign(body, "wrong") })).rejects.toThrow(
      /invalid webhook signature/,
    );
    // missing header entirely: call the intake directly, the helper re-adds signatures
    await expect(connector.intake!.handleWebhook({ headers: {}, body })).rejects.toThrow(
      /invalid webhook signature/,
    );
  });

  it("accepts unsigned posts when no secret is configured", async () => {
    const connector = await makeConnector({ secret: undefined });
    const body = JSON.stringify({ id: "a", project: "p", title: "t", labels: ["loop"] });
    const events = await connector.intake!.handleWebhook({ headers: {}, body });
    expect(events).toHaveLength(1);
  });

  it("rejects malformed bodies and invalid payloads", async () => {
    const connector = await makeConnector();
    await expect(eventsFor(connector, "not json")).rejects.toThrow(/not valid JSON/);
    const bad = JSON.stringify({ id: "a", title: "missing project" });
    await expect(eventsFor(connector, bad)).rejects.toThrow(/invalid payload/);
  });

  it("re-posts of the same alert id produce identical event ids (dedup-safe)", async () => {
    const connector = await makeConnector();
    const body = JSON.stringify({ id: "alert-4", project: "owner/repo", title: "Same", labels: ["loop"] });
    const first = await eventsFor(connector, body);
    const second = await eventsFor(connector, body);
    expect(second.map((e) => e.eventId)).toEqual(first.map((e) => e.eventId));
  });

  it("honors ignoreActors as self identities", async () => {
    const connector = await makeConnector({ ignoreActors: ["ci-bot"] });
    expect(await connector.intake!.selfIdentities()).toEqual(["ci-bot"]);
  });
});
