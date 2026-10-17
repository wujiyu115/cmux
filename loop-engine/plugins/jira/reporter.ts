import type { Reporter } from "../../src/connectors/connector";
import type { Ticket } from "../../src/domain/ticket";
import type { JiraClient } from "./client";

export interface JiraReporterDeps {
  client: JiraClient;
  transitions: { inProgress: string; blocked?: string };
}

/**
 * Ticket-side only: claims/comments/transitions live in Jira. No
 * openPullRequest — PRs route through the repo-configured git reporter.
 */
export class JiraReporter implements Reporter {
  constructor(private readonly deps: JiraReporterDeps) {}

  async claim(ticket: Ticket): Promise<void> {
    await this.transitionByName(ticket, this.deps.transitions.inProgress);
  }

  async postProgress(ticket: Ticket, message: string): Promise<void> {
    await this.deps.client.addComment(ticket.id.externalId, message);
  }

  async postResult(ticket: Ticket, summary: string, prUrl?: string): Promise<void> {
    await this.deps.client.addComment(
      ticket.id.externalId,
      prUrl ? `${summary}\n\nPull request: ${prUrl}` : summary,
    );
  }

  async fail(ticket: Ticket, reason: string): Promise<void> {
    await this.deps.client.addComment(
      ticket.id.externalId,
      `Loop agent gave up after exhausting its attempt budget.\n\nLast error: ${reason}`,
    );
    if (this.deps.transitions.blocked) {
      await this.transitionByName(ticket, this.deps.transitions.blocked);
    }
  }

  private async transitionByName(ticket: Ticket, name: string): Promise<void> {
    const key = ticket.id.externalId;
    const transitions = await this.deps.client.listTransitions(key);
    const match = transitions.find((t) => t.name.toLowerCase() === name.toLowerCase());
    if (!match) {
      const available = transitions.map((t) => t.name).join(", ") || "none";
      throw new Error(`transition "${name}" not found on ${key}; available: ${available}`);
    }
    await this.deps.client.transition(key, match.id);
  }
}
