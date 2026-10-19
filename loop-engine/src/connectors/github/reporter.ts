import type { Ticket } from "../../domain/ticket";
import type { PullRequestSpec, PullState, Reporter } from "../connector";
import type { GitHubClient } from "./client";
import { parseIssueRef, parseRepoRef } from "./mapper";

export interface GitHubReporterLabels {
  inProgress: string;
  needsHuman: string;
}

export class GitHubReporter implements Reporter {
  constructor(
    private readonly deps: { client: GitHubClient; labels: GitHubReporterLabels },
  ) {}

  async claim(ticket: Ticket): Promise<void> {
    const ref = parseIssueRef(ticket.id.externalId);
    await this.deps.client.addLabels(ref.owner, ref.repo, ref.number, [this.deps.labels.inProgress]);
  }

  async postProgress(ticket: Ticket, message: string): Promise<void> {
    await this.comment(ticket, message);
  }

  async openPullRequest(_ticket: Ticket, spec: PullRequestSpec): Promise<{ url: string }> {
    // The PR target comes from the spec, not the ticket: tickets raised in other
    // systems still open their PR against the configured GitHub repo.
    const ref = parseRepoRef(spec.repo);
    try {
      return await this.deps.client.createPullRequest(ref.owner, ref.repo, {
        title: spec.title,
        head: spec.head,
        base: spec.base,
        body: spec.body,
      });
    } catch (err) {
      // Idempotency: a retry after a crash (or a race with another worker)
      // may find the PR already open for this head (GitHub answers 422).
      // Return the existing PR instead of failing the work.
      if ((err as { status?: number }).status === 422) {
        const url = await this.deps.client.findOpenPullRequest(ref.owner, ref.repo, spec.head);
        if (url) return { url };
      }
      throw err;
    }
  }

  async postResult(ticket: Ticket, summary: string, prUrl?: string): Promise<void> {
    await this.comment(ticket, prUrl ? `${summary}\n\nPull request: ${prUrl}` : summary);
  }

  async fail(ticket: Ticket, reason: string): Promise<void> {
    const ref = parseIssueRef(ticket.id.externalId);
    await this.deps.client.addLabels(ref.owner, ref.repo, ref.number, [this.deps.labels.needsHuman]);
    await this.comment(
      ticket,
      `Loop agent gave up after exhausting its attempt budget.\n\nLast error: ${reason}`,
    );
  }

  async getPullState(_ticket: Ticket, prUrl: string): Promise<PullState> {
    // Parse everything from the URL so state checks work for cross-system tickets.
    const match = /^https:\/\/github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)$/.exec(prUrl);
    if (!match) throw new Error(`cannot parse pull request url: ${prUrl}`);
    const pr = await this.deps.client.getPullRequest(match[1]!, match[2]!, Number(match[3]!));
    if (pr.merged) return "merged";
    return pr.state === "closed" ? "closed" : "open";
  }

  async markDone(ticket: Ticket): Promise<void> {
    const ref = parseIssueRef(ticket.id.externalId);
    try {
      await this.deps.client.removeLabel(ref.owner, ref.repo, ref.number, this.deps.labels.inProgress);
    } catch {
      // the label may already be gone; removal is cosmetic cleanup
    }
  }

  private async comment(ticket: Ticket, body: string): Promise<void> {
    const ref = parseIssueRef(ticket.id.externalId);
    await this.deps.client.createComment(ref.owner, ref.repo, ref.number, body);
  }
}
