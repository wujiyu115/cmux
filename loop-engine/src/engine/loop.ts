import { randomUUID } from "node:crypto";

import { buildExecutorPrompt, buildPlannerPrompt } from "../agents/prompts";
import type { AgentRunner } from "../agents/runner";
import type { Reporter } from "../connectors/connector";
import type { ConnectorRegistry } from "../connectors/registry";
import type { IntakeEvent } from "../domain/events";
import type { Ticket } from "../domain/ticket";
import type { TodoItem } from "../domain/todo";
import type { WorkRecord, WorkStatus } from "../domain/work";
import type { WorkStore } from "../store/store";
import type { WorktreeFactory } from "../workspace/worktree";
import type { EngineConfig, RepoConfig } from "./config";
import type { VerificationReport, Verifier } from "./verifier";

export interface EnginePorts {
  connectors: ConnectorRegistry;
  runners: Map<string, AgentRunner>;
  store: WorkStore;
  worktrees: WorktreeFactory;
  verifier: Verifier;
  now: () => Date;
}

export class LoopEngine {
  private timer: ReturnType<typeof setInterval> | undefined;
  private ticking = false;

  constructor(
    private readonly ports: EnginePorts,
    private readonly config: EngineConfig,
  ) {}

  /** Webhook / poll events funnel in here: dedup → trigger match → claim. */
  async ingest(events: IntakeEvent[]): Promise<void> {
    for (const event of events) {
      await this.ingestOne(event);
    }
  }

  start(intervalMs = 5_000): void {
    if (this.timer) return;
    this.timer = setInterval(() => {
      void this.tick().catch((err) => console.error("[loop-engine] tick failed:", err));
    }, intervalMs);
  }

  async stop(): Promise<void> {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
  }

  /** Advance one actionable record by one stage. Idempotent and re-entrant after a crash. */
  async tick(): Promise<void> {
    if (this.ticking) return;
    this.ticking = true;
    try {
      const record = await this.ports.store.nextActionable();
      if (record) await this.advance(record);
    } finally {
      this.ticking = false;
    }
  }

  private async ingestOne(event: IntakeEvent): Promise<void> {
    if (await this.ports.store.hasEvent(event.eventId)) return;
    await this.ports.store.markEvent(event.eventId);

    if (event.kind === "comment.created") return;

    const ticket = event.ticket;
    const connector = this.ports.connectors.get(ticket.id.connectorId);
    if (!connector?.intake) return;

    const identities = await connector.intake.selfIdentities();
    if (identities.includes(event.actor)) return;

    const repo = this.config.repos[ticket.project];
    if (!repo) return;

    const triggered =
      (event.kind === "ticket.assigned" &&
        repo.trigger.assignees.some((a) => a.toLowerCase() === event.assignee.toLowerCase())) ||
      (event.kind === "ticket.labeled" && repo.trigger.labels.includes(event.label));
    if (!triggered) return;

    const active = await this.ports.store.findActiveByTicket(ticket.id);
    if (active) return;

    await connector.reporter?.claim(ticket);
    await this.ports.store.create({
      id: randomUUID(),
      ticket,
      status: "claimed",
      attempt: 0,
      todos: [],
      runnerId: repo.runner,
      usage: { inputTokens: 0, outputTokens: 0 },
      createdAt: this.ports.now().toISOString(),
      updatedAt: this.ports.now().toISOString(),
    });
  }

  private async advance(record: WorkRecord): Promise<void> {
    const repo = this.repoConfigFor(record);
    const tokensUsed = record.usage.inputTokens + record.usage.outputTokens;
    if (repo.budget.maxTokens !== undefined && tokensUsed >= repo.budget.maxTokens) {
      const reason = `token budget exhausted (${tokensUsed} of ${repo.budget.maxTokens})`;
      record.lastError = reason;
      await this.tryReport(record.ticket, (r) => r.fail(record.ticket, reason));
      await this.setStatus(record, "failed");
      await this.releaseWorktree(record);
      return;
    }

    switch (record.status) {
      // "planning" is re-enterable: a crash mid-planner leaves it here and the
      // next tick restarts the stage. Same for "executing"/"verifying".
      case "claimed":
      case "retrying":
      case "planning":
        return this.runPlanning(record);
      case "executing":
        return this.runExecution(record);
      case "verifying":
        return this.runVerification(record);
      default:
        return;
    }
  }

  private async runPlanning(record: WorkRecord): Promise<void> {
    try {
      const repo = this.repoConfigFor(record);
      const runner = this.runnerFor(record);
      await this.setStatus(record, "planning");

      const branch = `loop/${record.id}`;
      const worktree = await this.ports.worktrees.prepare({
        repoDir: repo.repoDir,
        baseBranch: repo.pr.base,
        branch,
      });
      record.branch = worktree.branch;
      record.worktreeDir = worktree.dir;

      const result = await runner.run({
        prompt: buildPlannerPrompt(record.ticket, record.lastError),
        cwd: worktree.dir,
        branch,
        timeoutMs: repo.budget.timeoutMs,
      });
      this.addUsage(record, result.usage);
      if (!result.ok) throw new Error(result.summary || "planner reported failure");

      record.todos = result.todos;
      await this.setStatus(record, "executing");
      const todos = record.todos;
      await this.tryReport(record.ticket, (r) =>
        r.postProgress(record.ticket, `Planned ${todos.length} todos:\n${formatTodos(todos)}`),
      );
    } catch (err) {
      await this.handleStageFailure(record, err);
    }
  }

  private async runExecution(record: WorkRecord): Promise<void> {
    try {
      const repo = this.repoConfigFor(record);
      const runner = this.runnerFor(record);
      if (!record.worktreeDir || !record.branch) throw new Error("worktree missing for execution");

      const result = await runner.run({
        prompt: buildExecutorPrompt(record.ticket, record.todos, record.lastError),
        cwd: record.worktreeDir,
        branch: record.branch,
        timeoutMs: repo.budget.timeoutMs,
      });
      this.addUsage(record, result.usage);
      if (!result.ok) throw new Error(result.summary || "executor reported failure");

      record.agentSummary = result.summary;
      await this.setStatus(record, "verifying");
    } catch (err) {
      await this.handleStageFailure(record, err);
    }
  }

  private async runVerification(record: WorkRecord): Promise<void> {
    try {
      if (!record.worktreeDir || !record.branch) throw new Error("worktree missing for verification");
      const repo = this.repoConfigFor(record);

      const report = await this.ports.verifier.verify(record.worktreeDir, repo.verification);
      if (!report.passed) {
        const failed = report.steps.filter((s) => !s.passed).map((s) => s.name);
        throw new Error(`verification failed: ${failed.join(", ")}`);
      }

      const gitReporter = this.gitReporterFor(record);
      if (!gitReporter) {
        throw new Error(
          `no reporter for project ${record.ticket.project}: connector "${record.ticket.id.connectorId}" cannot open pull requests; set repos.<project>.reporter`,
        );
      }
      const pr = await gitReporter.openPullRequest!(record.ticket, {
        title: record.ticket.title,
        body: buildPrBody(record, report),
        head: record.branch,
        base: repo.pr.base,
        repo: record.ticket.project,
      });
      record.prUrl = pr.url;
      await this.ticketReporterFor(record.ticket)?.postResult(
        record.ticket,
        buildResultSummary(record),
        record.prUrl,
      );
      await this.setStatus(record, "awaiting_review");
      // The PR references the branch, not the worktree; free the disk space.
      await this.releaseWorktree(record);
    } catch (err) {
      await this.handleStageFailure(record, err);
    }
  }

  /** Advance awaiting_review records from PR state: merged → done, closed → failed. */
  async reconcile(): Promise<void> {
    const records = await this.ports.store.listAwaitingReview();
    for (const record of records) {
      if (!record.prUrl) continue;
      try {
        const gitReporter = this.gitReporterFor(record);
        if (!gitReporter?.getPullState) continue;
        const state = await gitReporter.getPullState(record.ticket, record.prUrl);
        if (state === "merged") {
          await this.ticketReporterFor(record.ticket)?.markDone?.(record.ticket);
          await this.setStatus(record, "done");
        } else if (state === "closed") {
          const reason = "pull request was closed without merging";
          record.lastError = reason;
          await this.tryReport(record.ticket, (r) => r.fail(record.ticket, reason));
          await this.setStatus(record, "failed");
        }
      } catch (err) {
        console.error(`[loop-engine] reconcile failed for work ${record.id}:`, err);
      }
    }
  }

  private addUsage(record: WorkRecord, usage: { inputTokens: number; outputTokens: number }): void {
    record.usage.inputTokens += usage.inputTokens;
    record.usage.outputTokens += usage.outputTokens;
  }

  private async handleStageFailure(record: WorkRecord, err: unknown): Promise<void> {
    const repo = this.repoConfigFor(record);
    const reason = err instanceof Error ? err.message : String(err);
    record.lastError = reason;
    record.attempt += 1;

    if (record.attempt >= repo.budget.maxAttempts) {
      await this.tryReport(record.ticket, (r) => r.fail(record.ticket, reason));
      await this.setStatus(record, "failed");
      await this.releaseWorktree(record);
      return;
    }
    await this.tryReport(record.ticket, (r) =>
      r.postProgress(record.ticket, `Attempt ${record.attempt} failed (${reason}). Retrying.`),
    );
    await this.setStatus(record, "retrying");
  }

  /** Conversation side: the system where the ticket was raised. */
  private ticketReporterFor(ticket: Ticket): Reporter | undefined {
    return this.ports.connectors.get(ticket.id.connectorId)?.reporter;
  }

  /** Git side: opens PRs. Repo-configured, else the ticket's own connector. */
  private gitReporterFor(record: WorkRecord): Reporter | undefined {
    const repo = this.repoConfigFor(record);
    const id = repo.reporter ?? record.ticket.id.connectorId;
    const reporter = this.ports.connectors.get(id)?.reporter;
    return reporter?.openPullRequest ? reporter : undefined;
  }

  /** Best-effort reporting that must never block a state transition. */
  private async tryReport(ticket: Ticket, fn: (reporter: Reporter) => Promise<void>): Promise<void> {
    const reporter = this.ticketReporterFor(ticket);
    if (!reporter) return;
    try {
      await fn(reporter);
    } catch (err) {
      console.error("[loop-engine] best-effort report failed:", err);
    }
  }

  /** Best-effort cleanup: a failed release leaves the directory for the next retry to reuse. */
  private async releaseWorktree(record: WorkRecord): Promise<void> {
    if (!record.worktreeDir) return;
    const dir = record.worktreeDir;
    try {
      await this.ports.worktrees.release(dir);
      record.worktreeDir = undefined;
      await this.ports.store.update(record);
    } catch (err) {
      console.error("[loop-engine] worktree release failed:", err);
    }
  }

  private repoConfigFor(record: WorkRecord): RepoConfig {
    const repo = this.config.repos[record.ticket.project];
    if (!repo) throw new Error(`no repo config for project ${record.ticket.project}`);
    return repo;
  }

  private runnerFor(record: WorkRecord): AgentRunner {
    const runner = this.ports.runners.get(record.runnerId);
    if (!runner) throw new Error(`no runner registered: ${record.runnerId}`);
    return runner;
  }

  private async setStatus(record: WorkRecord, status: WorkStatus): Promise<void> {
    record.status = status;
    record.updatedAt = this.ports.now().toISOString();
    await this.ports.store.update(record);
  }
}

function formatTodos(todos: TodoItem[]): string {
  return todos.map((t) => `- [${t.status}] ${t.text}`).join("\n");
}

function buildPrBody(record: WorkRecord, report: VerificationReport): string {
  return [
    "## Summary",
    record.agentSummary ?? "(no agent summary)",
    "",
    "## Todos",
    ...record.todos.map((t) => `- [${t.status}] ${t.text}`),
    "",
    "## Verification",
    ...report.steps.map((s) => `- ${s.name}: ${s.passed ? "passed" : "failed"}`),
    "",
    `Closes ${record.ticket.url}`,
  ].join("\n");
}

function buildResultSummary(record: WorkRecord): string {
  return `Finished: ${record.agentSummary ?? "work complete"} (${record.todos.length} todos, verification passed).`;
}
