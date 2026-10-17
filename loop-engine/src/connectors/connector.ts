import type { Ticket } from "../domain/ticket";
import type { IntakeEvent } from "../domain/events";

export interface PollCursor {
  at: string;
}

export interface WebhookRequest {
  headers: Record<string, string>;
  body: unknown;
}

export interface Intake {
  /** Verify signature and normalize the raw webhook payload into events. */
  handleWebhook(req: WebhookRequest): Promise<IntakeEvent[]>;
  /** Poll fallback when webhooks are missed (local dev, retries). */
  poll?(cursor: PollCursor | null): Promise<{ events: IntakeEvent[]; cursor: PollCursor }>;
  /** Accounts this connector writes as; events they trigger are ignored. */
  selfIdentities(): Promise<string[]>;
}

export interface PullRequestSpec {
  title: string;
  body: string;
  head: string;
  base: string;
  /** Git repo identity (e.g. "owner/repo"); PRs open here regardless of ticket source. */
  repo: string;
}

export type PullState = "open" | "merged" | "closed";

/** Thrown by intake when webhook signature verification fails. Maps to HTTP 401. */
export class WebhookSignatureError extends Error {}

/** Thrown by intake when the webhook body or headers are malformed. Maps to HTTP 400. */
export class WebhookPayloadError extends Error {}

/**
 * Ticket-side capabilities target the system where the ticket lives.
 * `openPullRequest`/`getPullState` are the git-side capabilities: connectors
 * whose system has no PR concept (Jira, chat tools) omit them and PRs route
 * via `repos.<project>.reporter` instead.
 */
export interface Reporter {
  /** Mark the ticket as being worked on (label, status transition, ...). */
  claim(ticket: Ticket): Promise<void>;
  postProgress(ticket: Ticket, message: string): Promise<void>;
  postResult(ticket: Ticket, summary: string, prUrl?: string): Promise<void>;
  fail(ticket: Ticket, reason: string): Promise<void>;
  openPullRequest?(ticket: Ticket, spec: PullRequestSpec): Promise<{ url: string }>;
  /** Reconcile support: current state of the work's pull request. */
  getPullState?(ticket: Ticket, prUrl: string): Promise<PullState>;
  /** Cleanup after the PR merged, e.g. remove the in-progress label. */
  markDone?(ticket: Ticket): Promise<void>;
}

/**
 * One connector per external system. Most systems implement both directions;
 * read-only sources implement only `intake`, write-only targets only `reporter`.
 */
export interface Connector {
  id: string;
  intake?: Intake;
  reporter?: Reporter;
}
