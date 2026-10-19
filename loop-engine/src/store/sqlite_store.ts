import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

import type { TicketId } from "../domain/ticket";
import type { Usage, WorkRecord } from "../domain/work";
import { ACTIONABLE_STATUSES, ACTIVE_STATUSES } from "../domain/work";
import type { WorkStore } from "./store";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS work (
  id TEXT PRIMARY KEY,
  ticket_json TEXT NOT NULL,
  connector_id TEXT NOT NULL,
  external_id TEXT NOT NULL,
  status TEXT NOT NULL,
  attempt INTEGER NOT NULL DEFAULT 0,
  todos_json TEXT NOT NULL DEFAULT '[]',
  usage_json TEXT,
  branch TEXT,
  worktree_dir TEXT,
  pr_url TEXT,
  agent_summary TEXT,
  last_error TEXT,
  runner_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_work_ticket ON work(connector_id, external_id, status);
CREATE INDEX IF NOT EXISTS idx_work_status ON work(status);
CREATE TABLE IF NOT EXISTS event_dedup (
  event_id TEXT PRIMARY KEY,
  seen_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS poll_cursor (
  connector_id TEXT PRIMARY KEY,
  cursor TEXT NOT NULL
);
`;

interface WorkRow {
  id: string;
  ticket_json: string;
  status: string;
  attempt: number;
  todos_json: string;
  usage_json: string | null;
  branch: string | null;
  worktree_dir: string | null;
  pr_url: string | null;
  agent_summary: string | null;
  last_error: string | null;
  runner_id: string;
  created_at: string;
  updated_at: string;
}

function parseUsage(raw: string | null): Usage {
  const parsed: Partial<Usage> | null = raw ? JSON.parse(raw) : null;
  return {
    inputTokens: typeof parsed?.inputTokens === "number" ? parsed.inputTokens : 0,
    outputTokens: typeof parsed?.outputTokens === "number" ? parsed.outputTokens : 0,
  };
}

function fromRow(row: WorkRow): WorkRecord {
  return {
    id: row.id,
    ticket: JSON.parse(row.ticket_json),
    status: row.status as WorkRecord["status"],
    attempt: row.attempt,
    todos: JSON.parse(row.todos_json),
    usage: parseUsage(row.usage_json),
    branch: row.branch ?? undefined,
    worktreeDir: row.worktree_dir ?? undefined,
    prUrl: row.pr_url ?? undefined,
    agentSummary: row.agent_summary ?? undefined,
    lastError: row.last_error ?? undefined,
    runnerId: row.runner_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

const INSERT_SQL = `INSERT INTO work (
  id, ticket_json, connector_id, external_id, status, attempt, todos_json, usage_json,
  branch, worktree_dir, pr_url, agent_summary, last_error, runner_id, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;

const UPDATE_SQL = `UPDATE work SET
  ticket_json = ?, status = ?, attempt = ?, todos_json = ?, usage_json = ?, branch = ?, worktree_dir = ?,
  pr_url = ?, agent_summary = ?, last_error = ?, runner_id = ?, updated_at = ?
WHERE id = ?`;

export class SqliteWorkStore implements WorkStore {
  private readonly db: Database.Database;

  constructor(path: string) {
    if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
    this.db = new Database(path);
    this.db.pragma("journal_mode = WAL");
    this.db.exec(SCHEMA);
    // Databases created before usage tracking lack the column; dev DBs keep working.
    this.ensureColumn("usage_json", "ALTER TABLE work ADD COLUMN usage_json TEXT");
  }

  private ensureColumn(column: string, ddl: string): void {
    const columns = this.db.prepare("PRAGMA table_info(work)").all() as Array<{ name: string }>;
    if (!columns.some((c) => c.name === column)) this.db.exec(ddl);
  }

  close(): void {
    this.db.close();
  }

  async create(record: WorkRecord): Promise<void> {
    this.db
      .prepare(INSERT_SQL)
      .run(
        record.id,
        JSON.stringify(record.ticket),
        record.ticket.id.connectorId,
        record.ticket.id.externalId,
        record.status,
        record.attempt,
        JSON.stringify(record.todos),
        JSON.stringify(record.usage),
        record.branch ?? null,
        record.worktreeDir ?? null,
        record.prUrl ?? null,
        record.agentSummary ?? null,
        record.lastError ?? null,
        record.runnerId,
        record.createdAt,
        record.updatedAt,
      );
  }

  async update(record: WorkRecord): Promise<void> {
    this.db
      .prepare(UPDATE_SQL)
      .run(
        JSON.stringify(record.ticket),
        record.status,
        record.attempt,
        JSON.stringify(record.todos),
        JSON.stringify(record.usage),
        record.branch ?? null,
        record.worktreeDir ?? null,
        record.prUrl ?? null,
        record.agentSummary ?? null,
        record.lastError ?? null,
        record.runnerId,
        record.updatedAt,
        record.id,
      );
  }

  async get(id: string): Promise<WorkRecord | undefined> {
    const row = this.db.prepare("SELECT * FROM work WHERE id = ?").get(id) as WorkRow | undefined;
    return row ? fromRow(row) : undefined;
  }

  async list(): Promise<WorkRecord[]> {
    const rows = this.db.prepare("SELECT * FROM work ORDER BY created_at, rowid").all() as WorkRow[];
    return rows.map(fromRow);
  }

  async findActiveByTicket(ticketId: TicketId): Promise<WorkRecord | undefined> {
    const placeholders = ACTIVE_STATUSES.map(() => "?").join(",");
    const row = this.db
      .prepare(
        `SELECT * FROM work WHERE connector_id = ? AND external_id = ? AND status IN (${placeholders})
         ORDER BY created_at, rowid LIMIT 1`,
      )
      .get(ticketId.connectorId, ticketId.externalId, ...ACTIVE_STATUSES) as WorkRow | undefined;
    return row ? fromRow(row) : undefined;
  }

  async nextActionable(excludeIds: string[] = []): Promise<WorkRecord | undefined> {
    const placeholders = ACTIONABLE_STATUSES.map(() => "?").join(",");
    const rows = this.db
      .prepare(`SELECT * FROM work WHERE status IN (${placeholders}) ORDER BY created_at, rowid`)
      .all(...ACTIONABLE_STATUSES) as WorkRow[];
    const row = rows.find((r) => !excludeIds.includes(r.id));
    return row ? fromRow(row) : undefined;
  }

  async listAwaitingReview(): Promise<WorkRecord[]> {
    const rows = this.db
      .prepare("SELECT * FROM work WHERE status = 'awaiting_review' ORDER BY created_at, rowid")
      .all() as WorkRow[];
    return rows.map(fromRow);
  }

  async hasEvent(eventId: string): Promise<boolean> {
    return this.db.prepare("SELECT 1 FROM event_dedup WHERE event_id = ?").get(eventId) !== undefined;
  }

  async markEvent(eventId: string): Promise<void> {
    this.db
      .prepare("INSERT OR IGNORE INTO event_dedup (event_id, seen_at) VALUES (?, ?)")
      .run(eventId, new Date().toISOString());
  }

  async getPollCursor(connectorId: string): Promise<{ at: string } | null> {
    const row = this.db
      .prepare("SELECT cursor FROM poll_cursor WHERE connector_id = ?")
      .get(connectorId) as { cursor: string } | undefined;
    return row ? { at: row.cursor } : null;
  }

  async savePollCursor(connectorId: string, cursor: { at: string }): Promise<void> {
    this.db
      .prepare(
        "INSERT INTO poll_cursor (connector_id, cursor) VALUES (?, ?) ON CONFLICT(connector_id) DO UPDATE SET cursor = excluded.cursor",
      )
      .run(connectorId, cursor.at);
  }
}
