import type { Ticket } from "./ticket";
import type { TodoItem } from "./todo";

export type WorkStatus =
  | "claimed"
  | "planning"
  | "executing"
  | "verifying"
  | "retrying"
  | "awaiting_review"
  | "done"
  | "failed";

/** Statuses the tick loop will pick up and advance. */
export const ACTIONABLE_STATUSES: readonly WorkStatus[] = [
  "claimed",
  "planning",
  "executing",
  "verifying",
  "retrying",
];

/** Statuses that count as "work already exists for this ticket". */
export const ACTIVE_STATUSES: readonly WorkStatus[] = [...ACTIONABLE_STATUSES, "awaiting_review"];

export interface Usage {
  inputTokens: number;
  outputTokens: number;
}

export interface WorkRecord {
  id: string;
  ticket: Ticket;
  status: WorkStatus;
  attempt: number;
  todos: TodoItem[];
  runnerId: string;
  /** Accumulated across all agent runs of this work. */
  usage: Usage;
  branch?: string;
  worktreeDir?: string;
  prUrl?: string;
  agentSummary?: string;
  lastError?: string;
  createdAt: string;
  updatedAt: string;
}
