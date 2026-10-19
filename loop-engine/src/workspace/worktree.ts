export interface WorktreeSpec {
  repoDir: string;
  baseBranch: string;
  branch: string;
}

export interface PreparedWorktree {
  dir: string;
  branch: string;
}

export interface PushSpec {
  /** Local clone whose "origin" remote receives the branch. */
  repoDir: string;
  branch: string;
}

export interface WorktreeFactory {
  /** Must be idempotent per branch: retries reuse the same worktree. */
  prepare(spec: WorktreeSpec): Promise<PreparedWorktree>;
  release(dir: string): Promise<void>;
  /** Publish the branch to the repo's origin; called before opening a PR. */
  push(spec: PushSpec): Promise<void>;
}
