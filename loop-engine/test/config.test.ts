import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";

import { loadConfig } from "../src/config";

const dirs: string[] = [];

function writeConfig(yaml: string): string {
  const dir = mkdtempSync(join(tmpdir(), "loop-cfg-"));
  dirs.push(dir);
  const path = join(dir, "config.yaml");
  writeFileSync(path, yaml);
  return path;
}

afterAll(() => {
  for (const dir of dirs) rmSync(dir, { recursive: true, force: true });
});

describe("loadConfig", () => {
  it("resolves env secrets and applies defaults", () => {
    process.env.LOOP_TEST_TOKEN = "tok-123";
    const path = writeConfig(`
runners:
  claude:
    command: claude
repos:
  owner/repo:
    repoDir: /repos/owner/repo
    runner: claude
    trigger:
      assignees: [loop-agent]
connectors:
  github:
    token: env:LOOP_TEST_TOKEN
`);
    const config = loadConfig(path);
    expect(config.connectors.github?.token).toBe("tok-123");
    expect(config.engine.port).toBe(8787);
    expect(config.engine.dbPath).toBe("./data/loop-engine.db");
    expect(config.repos["owner/repo"]!.pr.base).toBe("main");
    expect(config.repos["owner/repo"]!.budget.maxAttempts).toBe(3);
    expect(config.repos["owner/repo"]!.budget.timeoutMs).toBe(600_000);
    expect(config.repos["owner/repo"]!.budget.maxTokens).toBeUndefined();
    expect(config.repos["owner/repo"]!.reporter).toBeUndefined();
    expect(config.plugins).toEqual([]);
    expect(config.engine.pollIntervalMs).toBe(60_000);
    expect(config.repos["owner/repo"]!.verification).toEqual([]);
    expect(config.repos["owner/repo"]!.trigger.labels).toEqual([]);
    expect(config.runners["claude"]!.args).toEqual([]);
  });

  it("fails when an env secret is missing", () => {
    delete process.env.LOOP_TEST_MISSING_TOKEN;
    const path = writeConfig(`
runners:
  claude:
    command: claude
repos:
  owner/repo:
    repoDir: /repos/owner/repo
    runner: claude
connectors:
  github:
    token: env:LOOP_TEST_MISSING_TOKEN
`);
    expect(() => loadConfig(path)).toThrow(/LOOP_TEST_MISSING_TOKEN/);
  });

  it("rejects configs without repos or runners", () => {
    expect(() => loadConfig(writeConfig("engine:\n  port: 1\n"))).toThrow();
  });
});
