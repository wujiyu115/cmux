import { spawn, type ChildProcess } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import type { TodoItem } from "../domain/todo";
import type { Sandbox } from "../sandbox/sandbox";
import type { AgentRunResult, AgentRunSpec, AgentRunner } from "./runner";

export interface CliAgentRunnerOptions {
  id: string;
  /** Executable to launch, e.g. "claude" or "pi". Must resolve via the shell. */
  command: string;
  /** Extra CLI args; must be shell-safe (no spaces in individual args). */
  args?: string[];
  env?: Record<string, string>;
  /** Optional execution isolation (docker/bwrap); defaults to pass-through. */
  sandbox?: Sandbox;
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
  // Claude Code shape: input_tokens / output_tokens
  if (record.input_tokens !== undefined || record.output_tokens !== undefined) {
    return { inputTokens: num(record.input_tokens), outputTokens: num(record.output_tokens) };
  }
  // pi shape: input / output
  return { inputTokens: num(record.input), outputTokens: num(record.output) };
}

function assistantText(message: unknown): string {
  if (!message || typeof message !== "object") return "";
  const content = (message as Record<string, unknown>).content;
  if (!Array.isArray(content)) return "";
  return content
    .filter(
      (part): part is { type: "text"; text: string } =>
        !!part && typeof part === "object" && (part as { type?: unknown }).type === "text",
    )
    .map((part) => part.text)
    .join("");
}

/**
 * Parses pi's NDJSON event stream (`pi --mode json -p`): the final answer is
 * the last turn_end/agent_end event's assistant text, usage comes from
 * turn_end.message.usage (pi shape: input/output).
 */
export function parsePiStream(raw: string): ParsedOutput {
  const lines = raw.split("\n").map((l) => l.trim()).filter((l) => l.length > 0);
  let text = "";
  let usage: { inputTokens: number; outputTokens: number } = { inputTokens: 0, outputTokens: 0 };
  let ok = true;
  for (const line of lines) {
    let event: Record<string, unknown>;
    try {
      const parsed: unknown = JSON.parse(line);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) continue;
      event = parsed as Record<string, unknown>;
    } catch {
      continue;
    }
    if (event.type === "error" || event.type === "abort") {
      ok = false;
      const message = typeof event.message === "string" ? event.message : "agent reported an error";
      text = text ? `${text}\n${message}` : message;
      continue;
    }
    if (event.type === "turn_end" && event.message && typeof event.message === "object") {
      const message = event.message as Record<string, unknown>;
      const next = assistantText(message);
      if (next) text = next;
      if (message.usage) usage = parseUsage(message.usage);
    }
  }
  return { ok, text, usage };
}

/**
 * Accepts three shapes and picks by sniffing the first non-empty line:
 * 1. Claude-Code-shaped single JSON object (`claude -p --output-format json`)
 * 2. pi's NDJSON event stream (`pi --mode json -p`)
 * 3. plain text output (anything else; treated as agent prose)
 */
export function parseCliOutput(raw: string): ParsedOutput {
  const trimmed = raw.trim();
  if (trimmed.length > 0) {
    const firstLine = trimmed.split("\n", 1)[0]!.trim();
    try {
      const first: unknown = JSON.parse(firstLine);
      if (first && typeof first === "object" && !Array.isArray(first)) {
        const record = first as Record<string, unknown>;
        // pi NDJSON streams open with lifecycle events (session/agent_start/...)
        // while a Claude result object carries result/is_error/subtype fields.
        const piEventType =
          typeof record.type === "string" &&
          record.result === undefined &&
          record.is_error === undefined &&
          record.subtype === undefined;
        if (piEventType) return parsePiStream(trimmed);
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
      const wrapped = this.options.sandbox
        ? this.options.sandbox.wrap({ command: this.options.command, args: this.options.args ?? [], cwd: spec.cwd })
        : { command: this.options.command, args: this.options.args ?? [] };
      const child = spawn(wrapped.command, wrapped.args, {
        cwd: wrapped.cwd ?? spec.cwd,
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
