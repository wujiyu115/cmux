import { createHmac, timingSafeEqual } from "node:crypto";
import { z } from "zod";

import type { Connector, Intake, WebhookRequest } from "../../src/connectors/connector";
import { WebhookPayloadError, WebhookSignatureError } from "../../src/connectors/connector";
import type { IntakeEvent } from "../../src/domain/events";
import type { Ticket } from "../../src/domain/ticket";
import { definePlugin } from "../../src/plugins/sdk";

const PLUGIN_ID = "generic-webhook";

/**
 * One-way source: any monitoring/form/mail system can POST a fixed-shape
 * payload and it becomes a ticket. Tickets raised here carry a `project` that
 * must match a repo config; PR reporting is routed via `repos.<project>.reporter`.
 */
const payloadSchema = z.object({
  /** Source-local alert id; event ids derive from it so re-posts dedup. */
  id: z.string().min(1),
  project: z.string().min(1),
  title: z.string().min(1),
  description: z.string().optional(),
  labels: z.array(z.string()).default([]),
  assignee: z.string().optional(),
  author: z.string().optional(),
  url: z.string().optional(),
});

const configSchema = z.object({
  secret: z.string().optional(),
  /** Events authored by these actors are ignored (same contract as GitHub bots). */
  ignoreActors: z.array(z.string()).default([]),
});

function verifySignature(secret: string, rawBody: string, signatureHeader: string): boolean {
  const prefix = "sha256=";
  if (!signatureHeader.startsWith(prefix)) return false;
  const expected = createHmac("sha256", secret).update(rawBody, "utf8").digest("hex");
  const provided = signatureHeader.slice(prefix.length);
  if (provided.length !== expected.length) return false;
  return timingSafeEqual(Buffer.from(provided, "utf8"), Buffer.from(expected, "utf8"));
}

class GenericWebhookIntake implements Intake {
  constructor(private readonly config: z.infer<typeof configSchema>) {}

  async handleWebhook(req: WebhookRequest): Promise<IntakeEvent[]> {
    if (typeof req.body !== "string") throw new WebhookPayloadError("raw string body required");
    if (this.config.secret) {
      const signature = req.headers["x-signature-256"];
      if (typeof signature !== "string" || !verifySignature(this.config.secret, req.body, signature)) {
        throw new WebhookSignatureError("invalid webhook signature");
      }
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(req.body);
    } catch {
      throw new WebhookPayloadError("webhook body is not valid JSON");
    }
    const result = payloadSchema.safeParse(parsed);
    if (!result.success) throw new WebhookPayloadError(`invalid payload (${result.error.message})`);
    const data = result.data;

    const ticket: Ticket = {
      id: { connectorId: PLUGIN_ID, externalId: data.id },
      project: data.project,
      title: data.title,
      body: data.description ?? "",
      author: data.author ?? "external",
      labels: data.labels,
      url: data.url ?? `${PLUGIN_ID}:${data.id}`,
      createdAt: new Date().toISOString(),
    };

    const events: IntakeEvent[] = [];
    if (data.assignee) {
      events.push({
        eventId: `${PLUGIN_ID}:${data.id}:assigned`,
        actor: ticket.author,
        kind: "ticket.assigned",
        ticket,
        assignee: data.assignee,
      });
    }
    for (const label of data.labels) {
      events.push({
        eventId: `${PLUGIN_ID}:${data.id}:labeled:${label}`,
        actor: ticket.author,
        kind: "ticket.labeled",
        ticket,
        label,
      });
    }
    return events;
  }

  async selfIdentities(): Promise<string[]> {
    return this.config.ignoreActors;
  }
}

export default definePlugin(
  { id: PLUGIN_ID, name: "Generic webhook source", version: "0.1.0" },
  (ctx) => {
    const config = configSchema.parse(ctx.config ?? {});
    return { id: PLUGIN_ID, intake: new GenericWebhookIntake(config) } satisfies Connector;
  },
);
