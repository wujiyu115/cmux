import { execFile } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { GitWorktreeFactory } from "../../src/workspace/git_worktree";

const execFileAsync = promisify(execFile);

const root = mkdtempSync(join(tmpdir(), "loop-wt-"));
const repoDir = join(root, "repo");
const worktreesRoot = join(root, "worktrees");

async function git(args: string[]): Promise<void> {
  await execFileAsync("git", args, { cwd: repoDir });
}

beforeAll(async () => {
  // git >= 2.28 supports "init -b"; older gits (Ubuntu 20.04's 2.25) can't
  // rename an unborn branch, so point HEAD at refs/heads/main instead.
  try {
    await execFileAsync("git", ["init", "-b", "main", repoDir]);
  } catch {
    await execFileAsync("git", ["init", repoDir]);
    await execFileAsync("git", ["symbolic-ref", "HEAD", "refs/heads/main"], { cwd: repoDir });
  }
  writeFileSync(join(repoDir, "README.md"), "hello\n");
  await git(["add", "."]);
  await git(["-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-m", "init"]);
});

afterAll(() => {
  try {
    rmSync(root, { recursive: true, force: true });
  } catch {
    // Windows may briefly hold worktree handles; leaving temp files behind is fine.
  }
});

describe("GitWorktreeFactory", () => {
  it("creates a worktree on a new branch from base", async () => {
    const factory = new GitWorktreeFactory({ root: worktreesRoot });
    const prepared = await factory.prepare({ repoDir, baseBranch: "main", branch: "loop/abc" });
    expect(existsSync(prepared.dir)).toBe(true);
    expect(existsSync(join(prepared.dir, "README.md"))).toBe(true);
    expect(prepared.branch).toBe("loop/abc");
  });

  it("reuses the same worktree when the branch is prepared twice", async () => {
    const factory = new GitWorktreeFactory({ root: worktreesRoot });
    const first = await factory.prepare({ repoDir, baseBranch: "main", branch: "loop/idem" });
    const second = await factory.prepare({ repoDir, baseBranch: "main", branch: "loop/idem" });
    expect(second.dir).toBe(first.dir);
  });

  it("creates a worktree for an existing branch without recreating it", async () => {
    const factory = new GitWorktreeFactory({ root: worktreesRoot });
    const first = await factory.prepare({ repoDir, baseBranch: "main", branch: "loop/reuse" });
    await factory.release(first.dir);

    const second = await factory.prepare({ repoDir, baseBranch: "main", branch: "loop/reuse" });
    expect(existsSync(second.dir)).toBe(true);
    expect(second.dir).toBe(first.dir);
  });

  it("releases worktrees", async () => {
    const factory = new GitWorktreeFactory({ root: worktreesRoot });
    const prepared = await factory.prepare({ repoDir, baseBranch: "main", branch: "loop/tmp" });
    await factory.release(prepared.dir);
    expect(existsSync(prepared.dir)).toBe(false);
  });

  it("pushes the branch to the repo's origin remote", async () => {
    // bare "origin" in the same temp root stands in for the real remote
    const originDir = join(root, "origin.git");
    await execFileAsync("git", ["init", "--bare", originDir]);
    await git(["remote", "add", "origin", originDir]);
    const factory = new GitWorktreeFactory({ root: worktreesRoot });
    const prepared = await factory.prepare({ repoDir, baseBranch: "main", branch: "loop/pushy" });

    // simulate the agent's commit on the worktree branch
    writeFileSync(join(prepared.dir, "CHANGE.md"), "change\n");
    await execFileAsync("git", ["add", "."], { cwd: prepared.dir });
    await execFileAsync(
      "git",
      ["-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-m", "change"],
      { cwd: prepared.dir },
    );

    await factory.push({ repoDir, branch: "loop/pushy" });
    // the branch now exists on the remote
    const { stdout } = await execFileAsync("git", ["ls-remote", "--heads", originDir], {
      cwd: repoDir,
    });
    expect(stdout).toContain("refs/heads/loop/pushy");
  });
});
