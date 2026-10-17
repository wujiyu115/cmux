import { WebhookPayloadError } from "../../src/connectors/connector";
import type { Intake, PollCursor, WebhookRequest } from "../../src/connectors/connector";
import type { IntakeEvent } from "../../src/domain/events";
import type { JiraClient } from "./client";
import { mapJiraWebhook, mapPollIssue, type PollProject } from "./mapper";

export interface JiraIntakeDeps {
  client: JiraClient;
  pollProjects: PollProject[];
  ignoreActors: string[];
}

export class JiraIntake implements Intake {
  private cachedAccountId?: string;

  constructor(private readonly deps: JiraIntakeDeps) {}

  async handleWebhook(req: WebhookRequest): Promise<IntakeEvent[]> {
    if (typeof req.body !== "string") throw new WebhookPayloadError("raw string body required");
    let payload: unknown;
    try {
      payload = JSON.parse(req.body);
    } catch {
      throw new WebhookPayloadError("webhook body is not valid JSON");
    }
    // Jira Cloud webhooks are not HMAC-signed; network-level access control applies.
    return mapJiraWebhook(payload, (key) => this.deps.client.browseUrl(key));
  }

  /** Fallback for missed webhooks; the first call only establishes a cursor. */
  async poll(cursor: PollCursor | null): Promise<{ events: IntakeEvent[]; cursor: PollCursor }> {
    if (!cursor || this.deps.pollProjects.length === 0) {
      return { events: [], cursor: { at: new Date().toISOString() } };
    }
    // JQL dates are day-granular; overlap one day so midnight changes are not missed.
    const since = new Date(new Date(cursor.at).getTime() - 24 * 60 * 60 * 1000);
    const date = since.toISOString().slice(0, 10);
    const events: IntakeEvent[] = [];
    for (const target of this.deps.pollProjects) {
      const jql = `project = "${target.project}" AND updated >= "${date}"`;
      const issues = await this.deps.client.searchIssues(jql);
      for (const issue of issues) {
        events.push(...mapPollIssue(issue, target));
      }
    }
    return { events, cursor: { at: new Date().toISOString() } };
  }

  async selfIdentities(): Promise<string[]> {
    this.cachedAccountId ??= await this.deps.client.getSelfAccountId();
    return [this.cachedAccountId, ...this.deps.ignoreActors];
  }
}
