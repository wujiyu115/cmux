import type { VerificationStep } from "./verifier";

export interface RepoConfig {
  /** Local clone used to create worktrees. */
  repoDir: string;
  runner: string;
  /** Git-side reporter id for PRs; defaults to the ticket's own connector. */
  reporter?: string;
  trigger: { assignees: string[]; labels: string[] };
  verification: VerificationStep[];
  budget: { maxAttempts: number; timeoutMs: number; maxTokens?: number };
  pr: { base: string };
}

export interface EngineConfig {
  /** Keyed by Ticket.project. */
  repos: Record<string, RepoConfig>;
}
