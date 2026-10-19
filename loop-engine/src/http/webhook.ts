import Fastify, { type FastifyInstance } from "fastify";

import { WebhookPayloadError, WebhookSignatureError } from "../connectors/connector";
import type { ConnectorRegistry } from "../connectors/registry";
import type { IntakeEvent } from "../domain/events";
import type { WorkRecord } from "../domain/work";
import type { WorkStore } from "../store/store";
import { registerPanelRoutes } from "./panel";

export interface WebhookServerDeps {
  connectors: ConnectorRegistry;
  onEvents: (events: IntakeEvent[]) => Promise<void>;
  /** When present, exposes the work-history read API. */
  store?: WorkStore;
}

export interface WorkSummary {
  id: string;
  status: string;
  attempt: number;
  ticket: { title: string; url: string; project: string };
  usage: { inputTokens: number; outputTokens: number };
  branch?: string;
  prUrl?: string;
  lastError?: string;
  createdAt: string;
  updatedAt: string;
}

function summarize(record: WorkRecord): WorkSummary {
  return {
    id: record.id,
    status: record.status,
    attempt: record.attempt,
    ticket: { title: record.ticket.title, url: record.ticket.url, project: record.ticket.project },
    usage: record.usage,
    branch: record.branch,
    prUrl: record.prUrl,
    lastError: record.lastError,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
  };
}

export function createWebhookServer(deps: WebhookServerDeps): FastifyInstance {
  const app = Fastify({ logger: false });

  // Keep the raw body string so connectors can verify webhook signatures.
  app.addContentTypeParser("application/json", { parseAs: "string" }, (_request, body, done) => {
    done(null, body as string);
  });

  app.get("/healthz", async () => ({ ok: true }));
  registerPanelRoutes(app);

  if (deps.store) {
    app.get("/work", async () => {
      const records = await deps.store!.list();
      return records.map(summarize);
    });

    app.get<{ Params: { id: string } }>("/work/:id", async (request, reply) => {
      const record = await deps.store!.get(request.params.id);
      if (!record) return reply.code(404).send({ error: "work not found" });
      return record;
    });
  }

  app.post<{ Params: { connectorId: string } }>("/webhooks/:connectorId", async (request, reply) => {
    const connector = deps.connectors.get(request.params.connectorId);
    if (!connector?.intake) {
      return reply.code(404).send({ error: `unknown connector: ${request.params.connectorId}` });
    }
    try {
      const events = await connector.intake.handleWebhook({
        headers: normalizeHeaders(request.headers),
        body: request.body,
      });
      await deps.onEvents(events);
      return reply.code(200).send({ received: events.length });
    } catch (err) {
      if (err instanceof WebhookSignatureError) return reply.code(401).send({ error: err.message });
      if (err instanceof WebhookPayloadError) return reply.code(400).send({ error: err.message });
      throw err;
    }
  });

  return app;
}

function normalizeHeaders(headers: Record<string, unknown>): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, value] of Object.entries(headers)) {
    result[key] = Array.isArray(value) ? String(value[0] ?? "") : String(value ?? "");
  }
  return result;
}
