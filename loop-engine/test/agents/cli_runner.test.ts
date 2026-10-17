import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { CliAgentRunner, extractTodos, parseCliOutput } from "../../src/agents/cli_runner";
import type { AgentRunSpec } from "../../src/agents/runner";

const fixturesDir = join(dirname(fileURLToPath(import.meta.url)), "..", "fixtures");
const fakeCli = join(fixturesDir, "fake-cli.mjs").replace(/\\/g, "/");

function makeRunner(extraArgs: string[] = []) {
  const transcriptDir = mkdtempSync(join(tmpdir(), "loop-transcripts-"));
  const runner = new CliAgentRunner({
    id: "fake",
    command: "node",
    args: [fakeCli, ...extraArgs],
    transcriptDir,
  });
  return { runner, transcriptDir };
}

function spec(prompt: string, timeoutMs = 10_000): AgentRunSpec {
  return { prompt, cwd: process.cwd(), branch: "loop/test-branch", timeoutMs };
}

describe("CliAgentRunner", () => {
  it("parses planner output into todos", async () => {
    const { runner } = makeRunner();
    const result = await runner.run(spec("Break the ticket down: fix login"));
    expect(result.ok).toBe(true);
    expect(result.summary).toContain("Here is the plan");
    expect(result.todos).toEqual([
      { text: "repro the bug", status: "pending" },
      { text: "fix it", status: "pending" },
    ]);
    expect(result.usage).toEqual({ inputTokens: 12, outputTokens: 34 });
    expect(existsSync(result.transcriptPath)).toBe(true);
  });

  it("returns plain summary for executor output without todos", async () => {
    const { runner } = makeRunner();
    const result = await runner.run(spec("Work through the todos"));
    expect(result.ok).toBe(true);
    expect(result.todos).toEqual([]);
    expect(result.summary).toContain("committed everything");
  });

  it("reports non-zero exit codes as failures", async () => {
    const { runner } = makeRunner(["--fail"]);
    const result = await runner.run(spec("anything"));
    expect(result.ok).toBe(false);
    expect(result.summary).toContain("exited with code 1");
    expect(result.summary).toContain("fake cli failure");
  });

  it("times out long-running commands", { timeout: 15_000 }, async () => {
    const { runner } = makeRunner(["--sleep=5000"]);
    const result = await runner.run(spec("anything", 150));
    expect(result.ok).toBe(false);
    expect(result.summary).toContain("timed out after 150ms");
  });
});

describe("parseCliOutput", () => {
  it("extracts result text and usage from claude-style JSON", () => {
    const raw = JSON.stringify({
      type: "result",
      is_error: false,
      result: "hello",
      usage: { input_tokens: 3, output_tokens: 4 },
    });
    const parsed = parseCliOutput(raw);
    expect(parsed).toEqual({ ok: true, text: "hello", usage: { inputTokens: 3, outputTokens: 4 } });
  });

  it("marks is_error results as failures", () => {
    const raw = JSON.stringify({ is_error: true, result: "nope" });
    expect(parseCliOutput(raw).ok).toBe(false);
  });

  it("falls back to raw text for non-JSON output", () => {
    const parsed = parseCliOutput("just text\n");
    expect(parsed).toEqual({ ok: true, text: "just text", usage: { inputTokens: 0, outputTokens: 0 } });
  });
});

describe("extractTodos", () => {
  it("uses the last fenced json block containing todos", () => {
    const text = 'intro\n```json\n{"other": 1}\n```\n```json\n{"todos": [{"text": "a"}]}\n```';
    expect(extractTodos(text)).toEqual([{ text: "a", status: "pending" }]);
  });

  it("drops malformed todo entries", () => {
    const text = '```json\n{"todos": [{"text": "a"}, {"nope": 1}, "x"]}\n```';
    expect(extractTodos(text)).toEqual([{ text: "a", status: "pending" }]);
  });

  it("returns empty array when no todo block exists", () => {
    expect(extractTodos("no blocks")).toEqual([]);
  });
});
