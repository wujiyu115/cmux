import { spawn, type ChildProcess } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import type { TodoItem } from "../domain/todo";
import type { AgentRunResult, AgentRunSpec, AgentRunner } from "./runner";

export interface CliAgentRunnerOptions {
  id: string;
  /** Executable to launch, e.g. "claude". Must resolve via the shell. */
  command: string;
  /** Extra CLI args; must be shell-safe (no spaces in individual args). */
  args?: string[];
  env?: Record<string, string>;
  transcriptDir: string;
}

interface CliOutcome {
  started: boolean;
  timedOut: boolean;
  exitCode: number | null;
  stdout: string;
  stderr: string;
}

interface ParsedOutput {
  ok: boolean;
  text: string;
  usage: { inputTokens: number; outputTokens: number };
}

function tail(text: string, max = 400): string {
  const trimmed = text.trim();
  return trimmed.length > max ? trimmed.slice(-max) : trimmed;
}

function parseUsage(value: unknown): { inputTokens: number; outputTokens: number } {
  if (!value || typeof value !== "object") return { inputTokens: 0, outputTokens: 0 };
  const record = value as Record<string, unknown>;
  const num = (x: unknown): number => (typeof x === "number" && Number.isFinite(x) ? x : 0);
  return { inputTokens: num(record.input_tokens), outputTokens: num(record.output_tokens) };
}

/**
 * Accepts either a Claude-Code-shaped JSON result (`claude -p --output-format json`)
 * or plain text output. Anything that is not JSON is treated as agent prose.
 */
export function parseCliOutput(raw: string): ParsedOutput {
  const trimmed = raw.trim();
  if (trimmed.length > 0) {
    try {
      const parsed: unknown = JSON.parse(trimmed);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        const record = parsed as Record<string, unknown>;
        const result = typeof record.result === "string" ? record.result : trimmed;
        const ok =
          record.is_error !== true &&
          record.subtype !== "error_during_execution" &&
          record.subtype !== "error_max_turns";
        return { ok, text: result, usage: parseUsage(record.usage) };
      }
    } catch {
      // not JSON — fall through to plain text
    }
  }
  return { ok: true, text: trimmed, usage: { inputTokens: 0, outputTokens: 0 } };
}

export function extractTodos(text: string): TodoItem[] {
  const blocks = [...text.matchAll(/```(?:json)?\s*([\s\S]*?)```/g)].map((m) => m[1]!.trim());
  for (const block of [...blocks].reverse()) {
    try {
      const parsed: unknown = JSON.parse(block);
      if (parsed && typeof parsed === "object" && Array.isArray((parsed as { todos?: unknown }).todos)) {
        return sanitizeTodos((parsed as { todos: unknown[] }).todos);
      }
    } catch {
      // try the next block
    }
  }
  return [];
}

function sanitizeTodos(value: unknown[]): TodoItem[] {
  const todos: TodoItem[] = [];
  for (const item of value) {
    if (!item || typeof item !== "object") continue;
    const record = item as Record<string, unknown>;
    if (typeof record.text !== "string" || record.text.length === 0) continue;
    const status =
      record.status === "in_progress" || record.status === "done" ? record.status : "pending";
    todos.push({ text: record.text, status });
  }
  return todos;
}

export class CliAgentRunner implements AgentRunner {
  readonly id: string;

  constructor(private readonly options: CliAgentRunnerOptions) {
    this.id = options.id;
  }

  async run(spec: AgentRunSpec): Promise<AgentRunResult> {
    mkdirSync(this.options.transcriptDir, { recursive: true });
    const startedAt = Date.now();
    const outcome = await this.spawnCli(spec);
    const transcriptPath = this.writeTranscript(spec, outcome, Date.now() - startedAt);
    const emptyUsage = { inputTokens: 0, outputTokens: 0 };

    if (!outcome.started) {
      return { ok: false, summary: `failed to start command: ${outcome.stderr}`, todos: [], transcriptPath, usage: emptyUsage };
    }
    if (outcome.timedOut) {
      return { ok: false, summary: `timed out after ${spec.timeoutMs}ms`, todos: [], transcriptPath, usage: emptyUsage };
    }
    if (outcome.exitCode !== 0) {
      return {
        ok: false,
        summary: `command exited with code ${outcome.exitCode}: ${tail(outcome.stderr || outcome.stdout)}`,
        todos: [],
        transcriptPath,
        usage: emptyUsage,
      };
    }

    const parsed = parseCliOutput(outcome.stdout);
    return { ok: parsed.ok, summary: parsed.text, todos: extractTodos(parsed.text), transcriptPath, usage: parsed.usage };
  }

  private spawnCli(spec: AgentRunSpec): Promise<CliOutcome> {
    return new Promise((resolve) => {
      const child = spawn(this.options.command, this.options.args ?? [], {
        cwd: spec.cwd,
        shell: true,
        env: { ...process.env, ...this.options.env },
        stdio: ["pipe", "pipe", "pipe"],
      });

      let stdout = "";
      let stderr = "";
      let started = true;
      let timedOut = false;
      let exitCode: number | null = null;
      let settled = false;

      const finish = (): void => {
        if (settled) return;
        settled = true;
        resolve({ started, timedOut, exitCode, stdout, stderr });
      };

      const timer = setTimeout(() => {
        timedOut = true;
        this.killTree(child);
      }, spec.timeoutMs);

      child.on("error", (err: NodeJS.ErrnoException) => {
        started = false;
        stderr = err.message;
        clearTimeout(timer);
        finish();
      });
      child.on("close", (code) => {
        exitCode = code;
        clearTimeout(timer);
        finish();
      });
      child.stdout?.on("data", (chunk) => {
        stdout += String(chunk);
      });
      child.stderr?.on("data", (chunk) => {
        stderr += String(chunk);
      });
      child.stdin?.on("error", () => {
        // the CLI may exit before consuming all prompt bytes
      });
      child.stdin?.write(spec.prompt);
      child.stdin?.end();
    });
  }

  private killTree(child: ChildProcess): void {
    if (process.platform === "win32" && child.pid) {
      spawn("taskkill", ["/pid", String(child.pid), "/T", "/F"]);
    } else {
      child.kill("SIGTERM");
    }
  }

  private writeTranscript(spec: AgentRunSpec, outcome: CliOutcome, durationMs: number): string {
    const fileName = `${spec.branch.replace(/[^a-zA-Z0-9._-]/g, "-")}-${Date.now()}.json`;
    const path = join(this.options.transcriptDir, fileName);
    writeFileSync(path, JSON.stringify({ spec, outcome, durationMs }, null, 2));
    return path;
  }
}
