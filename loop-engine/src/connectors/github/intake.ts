import { createHmac, timingSafeEqual } from "node:crypto";

import type { IntakeEvent } from "../../domain/events";
import { WebhookPayloadError, WebhookSignatureError } from "../connector";
import type { Intake, PollCursor, WebhookRequest } from "../connector";
import type { GitHubClient } from "./client";
import { mapGitHubWebhook, mapPollIssue, type PollTarget } from "./mapper";

function verifySignature(secret: string, rawBody: string, signatureHeader: string): boolean {
  const prefix = "sha256=";
  if (!signatureHeader.startsWith(prefix)) return false;
  const expected = createHmac("sha256", secret).update(rawBody, "utf8").digest("hex");
  const provided = signatureHeader.slice(prefix.length);
  if (provided.length !== expected.length) return false;
  return timingSafeEqual(Buffer.from(provided, "utf8"), Buffer.from(expected, "utf8"));
}

export interface GitHubIntakeDeps {
  client: GitHubClient;
  webhookSecret?: string;
  pollTargets?: PollTarget[];
}

/** Search dates are day-granular; overlap one day so nothing at midnight is missed. */
function toDateFilter(cursorAt: string): string {
  const date = new Date(new Date(cursorAt).getTime() - 24 * 60 * 60 * 1000);
  return date.toISOString().slice(0, 10);
}

export class GitHubIntake implements Intake {
  private cachedLogin?: string;

  constructor(private readonly deps: GitHubIntakeDeps) {}

  async handleWebhook(req: WebhookRequest): Promise<IntakeEvent[]> {
    if (typeof req.body !== "string") throw new WebhookPayloadError("raw string body required");
    if (this.deps.webhookSecret) {
      const signature = req.headers["x-hub-signature-256"];
      if (typeof signature !== "string" || !verifySignature(this.deps.webhookSecret, req.body, signature)) {
        throw new WebhookSignatureError("invalid webhook signature");
      }
    }
    const delivery = req.headers["x-github-delivery"];
    if (typeof delivery !== "string" || delivery.length === 0) {
      throw new WebhookPayloadError("missing X-GitHub-Delivery header");
    }
    let payload: unknown;
    try {
      payload = JSON.parse(req.body);
    } catch {
      throw new WebhookPayloadError("webhook body is not valid JSON");
    }
    const event = mapGitHubWebhook(delivery, req.headers["x-github-event"], payload);
    return event ? [event] : [];
  }

  async selfIdentities(): Promise<string[]> {
    this.cachedLogin ??= (await this.deps.client.getAuthenticatedLogin()).toLowerCase();
    return [this.cachedLogin];
  }

  /**
   * Fallback for missed webhooks: re-derive trigger events from the current
   * state of open issues. The first call only establishes a cursor.
   */
  async poll(cursor: PollCursor | null): Promise<{ events: IntakeEvent[]; cursor: PollCursor }> {
    const targets = this.deps.pollTargets ?? [];
    if (!cursor || targets.length === 0) {
      return { events: [], cursor: { at: new Date().toISOString() } };
    }
    const events: IntakeEvent[] = [];
    for (const target of targets) {
      const query = `repo:${target.repo} is:issue is:open updated:>=${toDateFilter(cursor.at)}`;
      const items = await this.deps.client.searchIssues(query);
      for (const item of items) {
        events.push(...mapPollIssue(item, target));
      }
    }
    return { events, cursor: { at: new Date().toISOString() } };
  }
}
