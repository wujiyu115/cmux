import { describe, expect, it } from "vitest";

import type { AgentRunResult, AgentRunSpec, AgentRunner } from "../../src/agents/runner";
import type { Connector, PullRequestSpec, PullState, Reporter } from "../../src/connectors/connector";
import { ConnectorRegistry } from "../../src/connectors/registry";
import type { IntakeEvent } from "../../src/domain/events";
import type { Ticket } from "../../src/domain/ticket";
import type { TodoItem } from "../../src/domain/todo";
import type { EngineConfig, RepoConfig } from "../../src/engine/config";
import { LoopEngine } from "../../src/engine/loop";
import type { VerificationReport, VerificationStep, Verifier } from "../../src/engine/verifier";
import { InMemoryWorkStore } from "../../src/store/store";
import type { WorktreeFactory, WorktreeSpec } from "../../src/workspace/worktree";

const NOW = new Date("2026-01-01T00:00:00.000Z");

function makeTicket(overrides: Partial<Ticket> = {}): Ticket {
  return {
    id: { connectorId: "github", externalId: "owner/repo#1" },
    project: "owner/repo",
    title: "Fix login bug",
    body: "Login fails when the password contains spaces.",
    author: "alice",
    labels: ["bug"],
    url: "https://github.com/owner/repo/issues/1",
    createdAt: NOW.toISOString(),
    ...overrides,
  };
}

function assignedEvent(
  ticket: Ticket,
  overrides: Partial<Extract<IntakeEvent, { kind: "ticket.assigned" }>> = {},
): IntakeEvent {
  return {
    eventId: `${ticket.id.externalId}-assigned`,
    actor: "alice",
    kind: "ticket.assigned",
    ticket,
    assignee: "loop-agent",
    ...overrides,
  };
}

function labeledEvent(ticket: Ticket, label = "loop"): IntakeEvent {
  return {
    eventId: `${ticket.id.externalId}-labeled-${label}`,
    actor: "alice",
    kind: "ticket.labeled",
    ticket,
    label,
  };
}

class FakeReporter implements Reporter {
  readonly calls: Array<{ method: string; args: unknown[] }> = [];
  readonly pullStates: Record<string, PullState | "error"> = {};
  readonly markDoneCalls: Ticket[] = [];

  async claim(ticket: Ticket): Promise<void> {
    this.calls.push({ method: "claim", args: [ticket] });
  }

  async postProgress(ticket: Ticket, message: string): Promise<void> {
    this.calls.push({ method: "postProgress", args: [ticket, message] });
  }

  async openPullRequest(ticket: Ticket, spec: PullRequestSpec): Promise<{ url: string }> {
    this.calls.push({ method: "openPullRequest", args: [ticket, spec] });
    return { url: "https://github.com/owner/repo/pull/99" };
  }

  async postResult(ticket: Ticket, summary: string, prUrl?: string): Promise<void> {
    this.calls.push({ method: "postResult", args: [ticket, summary, prUrl] });
  }

  async fail(ticket: Ticket, reason: string): Promise<void> {
    this.calls.push({ method: "fail", args: [ticket, reason] });
  }

  async getPullState(_ticket: Ticket, prUrl: string): Promise<PullState> {
    const state = this.pullStates[prUrl] ?? "open";
    if (state === "error") throw new Error("state check failed");
    return state;
  }

  async markDone(ticket: Ticket): Promise<void> {
    this.markDoneCalls.push(ticket);
  }

  has(method: string): boolean {
    return this.calls.some((c) => c.method === method);
  }
}

function okRun(
  todos: TodoItem[] = [
    { text: "repro", status: "pending" },
    { text: "fix", status: "pending" },
  ],
): AgentRunResult {
  return {
    ok: true,
    summary: "agent summary",
    todos,
    transcriptPath: "/tmp/transcript.jsonl",
    usage: { inputTokens: 100, outputTokens: 50 },
  };
}

class FakeRunner implements AgentRunner {
  readonly id = "claude";
  readonly specs: AgentRunSpec[] = [];
  private readonly queue: Array<AgentRunResult | Error>;

  constructor(script: Array<AgentRunResult | Error> = []) {
    this.queue = [...script];
  }

  async run(spec: AgentRunSpec): Promise<AgentRunResult> {
    this.specs.push(spec);
    const next = this.queue.length > 0 ? this.queue.shift()! : okRun();
    if (next instanceof Error) throw next;
    return next;
  }
}

class FakeVerifier implements Verifier {
  readonly calls: Array<{ dir: string; steps: VerificationStep[] }> = [];
  private readonly queue: boolean[];

  constructor(results: boolean[] = []) {
    this.queue = [...results];
  }

  async verify(dir: string, steps: VerificationStep[]): Promise<VerificationReport> {
    this.calls.push({ dir, steps });
    const passed = this.queue.length > 0 ? this.queue.shift()! : true;
    return {
      passed,
      steps: steps.map((s) => ({ name: s.name, passed, logPath: `/tmp/${s.name}.log` })),
    };
  }
}

class FakeWorktreeFactory implements WorktreeFactory {
  readonly branches: string[] = [];
  readonly released: string[] = [];
  readonly pushes: Array<{ repoDir: string; branch: string }> = [];

  async prepare(spec: WorktreeSpec) {
    this.branches.push(spec.branch);
    return { dir: `/tmp/wt/${spec.branch}`, branch: spec.branch };
  }

  async release(dir: string): Promise<void> {
    this.released.push(dir);
  }

  async push(spec: { repoDir: string; branch: string }): Promise<void> {
    this.pushes.push(spec);
  }
}

function makeHarness(
  opts: {
    runnerScript?: Array<AgentRunResult | Error>;
    verifyResults?: boolean[];
    maxAttempts?: number;
    maxTokens?: number;
    maxWorkers?: number;
    extraConnectors?: Connector[];
    repoReporter?: string;
  } = {},
) {
  const reporter = new FakeReporter();
  const connector: Connector = {
    id: "github",
    intake: { handleWebhook: async () => [], selfIdentities: async () => ["loop-bot"] },
    reporter,
  };
  const registry = new ConnectorRegistry();
  registry.register(connector);
  for (const extra of opts.extraConnectors ?? []) registry.register(extra);

  const runner = new FakeRunner(opts.runnerScript);
  const store = new InMemoryWorkStore();
  const worktrees = new FakeWorktreeFactory();
  const verifier = new FakeVerifier(opts.verifyResults);

  const repoConfig: RepoConfig = {
    repoDir: "/repos/owner/repo",
    runner: "claude",
    reporter: opts.repoReporter,
    trigger: { assignees: ["loop-agent"], labels: ["loop"] },
    verification: [{ name: "test", command: "npm test", required: true }],
    budget: { maxAttempts: opts.maxAttempts ?? 3, timeoutMs: 600_000, maxTokens: opts.maxTokens },
    pr: { base: "main" },
  };
  const engine = new LoopEngine(
    {
      connectors: registry,
      runners: new Map([[runner.id, runner]]),
      store,
      worktrees,
      verifier,
      now: () => NOW,
    },
    { repos: { "owner/repo": repoConfig }, maxWorkers: opts.maxWorkers } satisfies EngineConfig,
  );

  return { engine, reporter, runner, store, verifier, worktrees };
}

describe("ingest", () => {
  it("claims a ticket when the assignee matches the trigger", async () => {
    const h = makeHarness();
    await h.engine.ingest([assignedEvent(makeTicket())]);

    const records = await h.store.list();
    expect(records).toHaveLength(1);
    expect(records[0]!.status).toBe("claimed");
    expect(records[0]!.runnerId).toBe("claude");
    expect(h.reporter.has("claim")).toBe(true);
  });

  it("claims a ticket when a label matches the trigger", async () => {
    const h = makeHarness();
    await h.engine.ingest([labeledEvent(makeTicket())]);

    const records = await h.store.list();
    expect(records).toHaveLength(1);
    expect(records[0]!.status).toBe("claimed");
  });

  it("ignores events that match no trigger rule", async () => {
    const h = makeHarness();
    await h.engine.ingest([
      assignedEvent(makeTicket(), { assignee: "someone-else" }),
      labeledEvent(makeTicket(), "wontfix"),
    ]);

    expect(await h.store.list()).toHaveLength(0);
    expect(h.reporter.has("claim")).toBe(false);
  });

  it("ignores events authored by connector self identities", async () => {
    const h = makeHarness();
    await h.engine.ingest([assignedEvent(makeTicket(), { actor: "loop-bot" })]);

    expect(await h.store.list()).toHaveLength(0);
  });

  it("claims poll-derived events even when the author is a self identity", async () => {
    // single-person setup: the maintainer authors and self-assigns their own
    // issue with the account whose token the connector uses
    const h = makeHarness();
    await h.engine.ingest([assignedEvent(makeTicket(), { actor: "loop-bot", pollDerived: true })]);

    const records = await h.store.list();
    expect(records).toHaveLength(1);
    expect(records[0]!.status).toBe("claimed");
  });

  it("ignores duplicate event deliveries", async () => {
    const h = makeHarness();
    const event = assignedEvent(makeTicket());
    await h.engine.ingest([event]);
    await h.engine.ingest([event]);

    expect(await h.store.list()).toHaveLength(1);
    expect(h.reporter.calls.filter((c) => c.method === "claim")).toHaveLength(1);
  });

  it("ignores tickets from unconfigured projects", async () => {
    const h = makeHarness();
    await h.engine.ingest([assignedEvent(makeTicket({ project: "other/repo" }))]);

    expect(await h.store.list()).toHaveLength(0);
  });

  it("ignores comment events", async () => {
    const h = makeHarness();
    const ticket = makeTicket();
    const comment: IntakeEvent = {
      eventId: "comment-1",
      actor: "alice",
      kind: "comment.created",
      comment: {
        ticketId: ticket.id,
        externalId: "comment-1",
        author: "alice",
        body: "any update?",
        createdAt: NOW.toISOString(),
      },
    };
    await h.engine.ingest([comment]);

    expect(await h.store.list()).toHaveLength(0);
  });

  it("does not start a second work while the ticket is active", async () => {
    const h = makeHarness();
    const ticket = makeTicket();
    await h.engine.ingest([assignedEvent(ticket)]);
    await h.engine.ingest([labeledEvent(ticket)]);

    expect(await h.store.list()).toHaveLength(1);
  });
});

describe("tick lifecycle", () => {
  it("runs plan → execute → verify and opens a PR", async () => {
    const h = makeHarness();
    await h.engine.ingest([assignedEvent(makeTicket())]);
    const id = (await h.store.list())[0]!.id;

    await h.engine.tick();
    let record = await h.store.get(id);
    expect(record!.status).toBe("executing");
    expect(record!.todos.map((t) => t.text)).toEqual(["repro", "fix"]);
    expect(record!.branch).toBe(`loop/${id}`);
    expect(h.runner.specs[0]!.prompt).toContain("Fix login bug");
    expect(h.reporter.has("postProgress")).toBe(true);

    await h.engine.tick();
    record = await h.store.get(id);
    expect(record!.status).toBe("verifying");
    expect(record!.agentSummary).toBe("agent summary");
    expect(h.runner.specs[1]!.prompt).toContain("repro");

    await h.engine.tick();
    record = await h.store.get(id);
    expect(record!.status).toBe("awaiting_review");
    expect(record!.prUrl).toBe("https://github.com/owner/repo/pull/99");
    expect(h.reporter.has("openPullRequest")).toBe(true);
    expect(h.reporter.has("postResult")).toBe(true);
    // the branch is pushed to origin before the PR opens
    expect(h.worktrees.pushes).toEqual([{ repoDir: "/repos/owner/repo", branch: `loop/${id}` }]);

    const prCall = h.reporter.calls.find((c) => c.method === "openPullRequest")!;
    const spec = prCall.args[1] as PullRequestSpec;
    expect(spec.title).toBe("Fix login bug");
    expect(spec.base).toBe("main");
    expect(spec.repo).toBe("owner/repo");
    expect(spec.body).toContain("- [pending] repro");
    expect(spec.body).toContain("Closes https://github.com/owner/repo/issues/1");

    // the worktree is released once the PR is open; the branch keeps it alive
    expect(h.worktrees.released).toEqual([`/tmp/wt/loop/${id}`]);
    expect((await h.store.get(id))!.worktreeDir).toBeUndefined();

    // no more actionable work
    await h.engine.tick();
    expect(h.runner.specs).toHaveLength(2);
  });

  it("retries from planning after a verification failure, then succeeds", async () => {
    const h = makeHarness({ verifyResults: [false, true] });
    await h.engine.ingest([assignedEvent(makeTicket())]);
    const id = (await h.store.list())[0]!.id;

    await h.engine.tick();
    await h.engine.tick();
    await h.engine.tick();
    let record = await h.store.get(id);
    expect(record!.status).toBe("retrying");
    expect(record!.attempt).toBe(1);
    // a non-terminal failure keeps the worktree so the retry reuses it
    expect(h.worktrees.released).toEqual([]);
    expect(h.reporter.calls.some((c) => c.method === "postProgress" && String(c.args[1]).includes("Attempt 1 failed"))).toBe(true);

    await h.engine.tick();
    await h.engine.tick();
    await h.engine.tick();
    record = await h.store.get(id);
    expect(record!.status).toBe("awaiting_review");
    expect(h.runner.specs).toHaveLength(4);
    // retry re-plans on the same branch
    expect(record!.branch).toBe(`loop/${id}`);
    expect(h.worktrees.released).toEqual([`/tmp/wt/loop/${id}`]);
  });

  it("marks the work failed after exhausting the attempt budget", async () => {
    const h = makeHarness({ verifyResults: [false, false], maxAttempts: 2 });
    await h.engine.ingest([assignedEvent(makeTicket())]);

    for (let i = 0; i < 6; i++) await h.engine.tick();

    const record = (await h.store.list())[0]!;
    expect(record.status).toBe("failed");
    expect(record.attempt).toBe(2);
    expect(record.worktreeDir).toBeUndefined();
    expect(h.worktrees.released).toEqual([`/tmp/wt/loop/${record.id}`]);
    expect(h.reporter.has("fail")).toBe(true);
    expect(h.reporter.has("openPullRequest")).toBe(false);
  });

  it("counts runner errors as failed attempts", async () => {
    const h = makeHarness({ runnerScript: [okRun(), new Error("runner crashed")] });
    await h.engine.ingest([assignedEvent(makeTicket())]);

    await h.engine.tick();
    await h.engine.tick();

    const record = (await h.store.list())[0]!;
    expect(record.status).toBe("retrying");
    expect(record.attempt).toBe(1);
    expect(record.lastError).toBe("runner crashed");
  });

  it("recovers a stale planning record left by a crash", async () => {
    const h = makeHarness();
    await h.engine.ingest([assignedEvent(makeTicket())]);
    const record = (await h.store.list())[0]!;
    record.status = "planning";
    await h.store.update(record);

    await h.engine.tick();

    const updated = await h.store.get(record.id);
    expect(updated!.status).toBe("executing");
  });

  it("accumulates token usage across planner and executor runs", async () => {
    const h = makeHarness();
    await h.engine.ingest([assignedEvent(makeTicket())]);
    const id = (await h.store.list())[0]!.id;

    await h.engine.tick();
    await h.engine.tick();
    await h.engine.tick();

    const record = await h.store.get(id);
    expect(record!.usage).toEqual({ inputTokens: 200, outputTokens: 100 });
  });

  it("stops before the next attempt when the token budget is exhausted", async () => {
    const h = makeHarness({ maxTokens: 100 });
    await h.engine.ingest([assignedEvent(makeTicket())]);

    await h.engine.tick();
    let record = (await h.store.list())[0]!;
    expect(record.usage).toEqual({ inputTokens: 100, outputTokens: 50 });
    expect(record.status).toBe("executing");

    await h.engine.tick();
    record = (await h.store.list())[0]!;
    expect(record.status).toBe("failed");
    expect(record.lastError).toContain("token budget exhausted (150 of 100)");
    expect(record.worktreeDir).toBeUndefined();
    expect(h.runner.specs).toHaveLength(1);
    expect(h.reporter.has("fail")).toBe(true);
  });
});

describe("concurrent workers", () => {
  class GatedRunner implements AgentRunner {
    readonly id = "claude";
    readonly specs: AgentRunSpec[] = [];
    private readonly gates: Array<() => void> = [];

    async run(spec: AgentRunSpec): Promise<AgentRunResult> {
      this.specs.push(spec);
      await new Promise<void>((resolve) => this.gates.push(resolve));
      return okRun();
    }

    releaseAll(): void {
      for (const resolve of this.gates.splice(0)) resolve();
    }
  }

  function makeTicketFor(key: string): Ticket {
    return makeTicket({
      id: { connectorId: "github", externalId: `owner/repo#${key}` },
      url: `https://github.com/owner/repo/issues/${key}`,
      title: `Task ${key}`,
    });
  }

  it("advances one record at a time with maxWorkers=1 (default)", async () => {
    const h = makeHarness();
    await h.engine.ingest([assignedEvent(makeTicketFor("1")), assignedEvent(makeTicketFor("2"))]);

    await h.engine.tick();

    const records = await h.store.list();
    const statuses = records.map((r) => r.status).sort();
    // one record advanced to executing, the other untouched
    expect(statuses).toEqual(["claimed", "executing"]);
    expect(h.runner.specs).toHaveLength(1);
  });

  it("advances up to maxWorkers records in parallel per tick", async () => {
    const h = makeHarness({ maxWorkers: 2 });
    await h.engine.ingest([assignedEvent(makeTicketFor("1")), assignedEvent(makeTicketFor("2"))]);

    const tickPromise = h.engine.tick();
    // let the microtasks settle: both records should have been claimed and advanced
    await new Promise((resolve) => setTimeout(resolve, 10));
    const records = await h.store.list();
    const statuses = records.map((r) => r.status).sort();
    expect(statuses).toEqual(["executing", "executing"]);
    expect(h.runner.specs).toHaveLength(2);
    await tickPromise;
  });

  it("never advances the same record twice across overlapping ticks", async () => {
    const h = makeHarness({ maxWorkers: 2 });
    const ticket = makeTicketFor("1");
    await h.engine.ingest([assignedEvent(ticket)]);

    const first = h.engine.tick();
    const second = h.engine.tick();
    await Promise.all([first, second]);

    expect(h.runner.specs).toHaveLength(1);
  });

  it("caps claims at maxWorkers when more records are ready", async () => {
    const h = makeHarness({ maxWorkers: 2 });
    await h.engine.ingest([
      assignedEvent(makeTicketFor("1")),
      assignedEvent(makeTicketFor("2")),
      assignedEvent(makeTicketFor("3")),
    ]);

    await h.engine.tick();

    const statuses = (await h.store.list()).map((r) => r.status).sort();
    expect(statuses).toEqual(["claimed", "executing", "executing"]);
  });

  it("keeps advancing remaining records on the next tick", async () => {
    const h = makeHarness({ maxWorkers: 2 });
    await h.engine.ingest([
      assignedEvent(makeTicketFor("1")),
      assignedEvent(makeTicketFor("2")),
      assignedEvent(makeTicketFor("3")),
    ]);

    // each tick always advances the earliest actionable records first, so
    // records 1-2 finish before record 3 starts; 6 ticks total
    for (let i = 0; i < 6; i++) await h.engine.tick();

    const records = await h.store.list();
    expect(records.every((r) => r.status === "awaiting_review")).toBe(true);
  });
});

describe("reconcile", () => {
  async function driveToReview(h: ReturnType<typeof makeHarness>) {
    await h.engine.ingest([assignedEvent(makeTicket())]);
    await h.engine.tick();
    await h.engine.tick();
    await h.engine.tick();
    return (await h.store.list())[0]!;
  }

  it("marks work done when the PR merges and cleans the label", async () => {
    const h = makeHarness();
    const record = await driveToReview(h);
    h.reporter.pullStates[record.prUrl!] = "merged";

    await h.engine.reconcile();

    const done = await h.store.get(record.id);
    expect(done!.status).toBe("done");
    expect(h.reporter.markDoneCalls).toHaveLength(1);
  });

  it("marks work failed when the PR is closed without merging", async () => {
    const h = makeHarness();
    const record = await driveToReview(h);
    h.reporter.pullStates[record.prUrl!] = "closed";

    await h.engine.reconcile();

    const failed = await h.store.get(record.id);
    expect(failed!.status).toBe("failed");
    expect(failed!.lastError).toContain("closed without merging");
    expect(h.reporter.has("fail")).toBe(true);
    expect(h.reporter.markDoneCalls).toHaveLength(0);
  });

  it("leaves work alone while the PR is open", async () => {
    const h = makeHarness();
    const record = await driveToReview(h);

    await h.engine.reconcile();

    const unchanged = await h.store.get(record.id);
    expect(unchanged!.status).toBe("awaiting_review");
    expect(h.reporter.markDoneCalls).toHaveLength(0);
  });

  it("survives state-check errors without changing the record", async () => {
    const h = makeHarness();
    const record = await driveToReview(h);
    h.reporter.pullStates[record.prUrl!] = "error";

    await h.engine.reconcile();

    const unchanged = await h.store.get(record.id);
    expect(unchanged!.status).toBe("awaiting_review");
  });
});

describe("cross-system routing", () => {
  const genericConnector: Connector = {
    id: "generic",
    intake: { handleWebhook: async () => [], selfIdentities: async () => [] },
  };

  function genericTicket(): Ticket {
    return makeTicket({
      id: { connectorId: "generic", externalId: "alert-1" },
      url: "generic-webhook:alert-1",
    });
  }

  it("opens the PR on the configured git reporter; ticket-side reporting is skipped", async () => {
    const h = makeHarness({ extraConnectors: [genericConnector], repoReporter: "github" });
    await h.engine.ingest([assignedEvent(genericTicket())]);
    const id = (await h.store.list())[0]!.id;

    for (let i = 0; i < 3; i++) await h.engine.tick();
    const record = await h.store.get(id);
    expect(record!.status).toBe("awaiting_review");
    expect(record!.prUrl).toBe("https://github.com/owner/repo/pull/99");

    const prCalls = h.reporter.calls.filter((c) => c.method === "openPullRequest");
    expect(prCalls).toHaveLength(1);
    expect((prCalls[0]!.args[1] as PullRequestSpec).repo).toBe("owner/repo");
    // the intake-only connector has no reporter: no ticket-side calls happened
    expect(h.reporter.has("claim")).toBe(false);
    expect(h.reporter.has("postProgress")).toBe(false);
    expect(h.reporter.has("postResult")).toBe(false);

    h.reporter.pullStates[record!.prUrl!] = "merged";
    await h.engine.reconcile();
    expect((await h.store.get(id))!.status).toBe("done");
    expect(h.reporter.markDoneCalls).toHaveLength(0);
  });

  it("fails with a clear error when no git reporter can be resolved", async () => {
    const h = makeHarness({ extraConnectors: [genericConnector] });
    await h.engine.ingest([assignedEvent(genericTicket())]);

    for (let i = 0; i < 3; i++) await h.engine.tick();

    const record = (await h.store.list())[0]!;
    expect(record.status).toBe("retrying");
    expect(record.attempt).toBe(1);
    expect(record.lastError).toContain("no reporter for project owner/repo");
    expect(h.reporter.has("openPullRequest")).toBe(false);
  });
});

describe("ticket-only reporters", () => {
  // Jira-shaped: claims/comments/transitions on the ticket, no git-side capabilities.
  class TicketOnlyReporter implements Reporter {
    readonly calls: Array<{ method: string; args: unknown[] }> = [];

    async claim(ticket: Ticket): Promise<void> {
      this.calls.push({ method: "claim", args: [ticket] });
    }

    async postProgress(ticket: Ticket, message: string): Promise<void> {
      this.calls.push({ method: "postProgress", args: [ticket, message] });
    }

    async postResult(ticket: Ticket, summary: string, prUrl?: string): Promise<void> {
      this.calls.push({ method: "postResult", args: [ticket, summary, prUrl] });
    }

    async fail(ticket: Ticket, reason: string): Promise<void> {
      this.calls.push({ method: "fail", args: [ticket, reason] });
    }

    has(method: string): boolean {
      return this.calls.some((c) => c.method === method);
    }
  }

  function jiraTicket(): Ticket {
    return makeTicket({
      id: { connectorId: "jira", externalId: "PROJ-7" },
      url: "https://x.atlassian.net/browse/PROJ-7",
    });
  }

  it("routes ticket conversation to the ticket reporter and the PR to the git reporter", async () => {
    const ticketReporter = new TicketOnlyReporter();
    const jiraConnector: Connector = {
      id: "jira",
      intake: { handleWebhook: async () => [], selfIdentities: async () => [] },
      reporter: ticketReporter,
    };
    const h = makeHarness({ extraConnectors: [jiraConnector], repoReporter: "github" });
    await h.engine.ingest([assignedEvent(jiraTicket())]);
    const id = (await h.store.list())[0]!.id;

    for (let i = 0; i < 3; i++) await h.engine.tick();
    const record = await h.store.get(id);
    expect(record!.status).toBe("awaiting_review");
    expect(record!.prUrl).toBe("https://github.com/owner/repo/pull/99");

    expect(h.reporter.has("openPullRequest")).toBe(true);
    expect(ticketReporter.has("claim")).toBe(true);
    expect(ticketReporter.has("postResult")).toBe(true);
    const resultCall = ticketReporter.calls.find((c) => c.method === "postResult")!;
    expect(resultCall.args[2]).toBe(record!.prUrl);

    h.reporter.pullStates[record!.prUrl!] = "merged";
    await h.engine.reconcile();
    expect((await h.store.get(id))!.status).toBe("done");
  });

  it("never falls back to a ticket-only reporter for pull requests", async () => {
    const ticketReporter = new TicketOnlyReporter();
    const jiraConnector: Connector = {
      id: "jira",
      intake: { handleWebhook: async () => [], selfIdentities: async () => [] },
      reporter: ticketReporter,
    };
    const h = makeHarness({ extraConnectors: [jiraConnector] });
    await h.engine.ingest([assignedEvent(jiraTicket())]);

    for (let i = 0; i < 3; i++) await h.engine.tick();

    const record = (await h.store.list())[0]!;
    expect(record.status).toBe("retrying");
    expect(record.lastError).toContain("no reporter for project owner/repo");
    // ticket-side reporting still happened before the git-side failure
    expect(ticketReporter.has("claim")).toBe(true);
    expect(h.reporter.has("openPullRequest")).toBe(false);
  });
});
