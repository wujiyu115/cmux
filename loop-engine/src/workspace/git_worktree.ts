import { execFile } from "node:child_process";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { promisify } from "node:util";

import type { PreparedWorktree, WorktreeFactory, WorktreeSpec } from "./worktree";

const execFileAsync = promisify(execFile);

async function git(args: string[], cwd?: string): Promise<string> {
  const { stdout } = await execFileAsync("git", args, { cwd, maxBuffer: 10 * 1024 * 1024 });
  return stdout;
}

async function gitSucceeds(args: string[], cwd?: string): Promise<boolean> {
  try {
    await git(args, cwd);
    return true;
  } catch {
    return false;
  }
}

export class GitWorktreeFactory implements WorktreeFactory {
  private readonly repoDirs = new Map<string, string>();

  constructor(private readonly options: { root: string }) {}

  async prepare(spec: WorktreeSpec): Promise<PreparedWorktree> {
    mkdirSync(this.options.root, { recursive: true });
    const dir = join(this.options.root, spec.branch.replace(/[^a-zA-Z0-9._-]/g, "-"));
    if (existsSync(dir)) {
      // Crash-recovery path: a retry after a crash between worktree add and
      // the status write reuses the existing worktree on the same branch.
      this.repoDirs.set(dir, spec.repoDir);
      return { dir, branch: spec.branch };
    }
    const branchExists = await gitSucceeds(
      ["show-ref", "--verify", "--quiet", `refs/heads/${spec.branch}`],
      spec.repoDir,
    );
    if (branchExists) {
      await git(["worktree", "add", dir, spec.branch], spec.repoDir);
    } else {
      await git(["worktree", "add", "-b", spec.branch, dir, spec.baseBranch], spec.repoDir);
    }
    this.repoDirs.set(dir, spec.repoDir);
    return { dir, branch: spec.branch };
  }

  async release(dir: string): Promise<void> {
    rmSync(dir, { recursive: true, force: true });
    const repoDir = this.repoDirs.get(dir);
    this.repoDirs.delete(dir);
    if (repoDir) await gitSucceeds(["worktree", "prune"], repoDir);
  }
}
