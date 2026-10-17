import { exec } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { promisify } from "node:util";

import type { VerificationReport, VerificationStep, Verifier } from "./verifier";

const execAsync = promisify(exec);

export interface ShellVerifierOptions {
  logDir: string;
  stepTimeoutMs?: number;
}

interface ShellResult {
  code: number;
  stdout: string;
  stderr: string;
}

async function runShell(command: string, cwd: string, timeoutMs: number): Promise<ShellResult> {
  try {
    const { stdout, stderr } = await execAsync(command, { cwd, timeout: timeoutMs, maxBuffer: 10 * 1024 * 1024 });
    return { code: 0, stdout, stderr };
  } catch (err) {
    const e = err as { stdout?: string; stderr?: string; code?: number; killed?: boolean; message?: string };
    return {
      code: typeof e.code === "number" ? e.code : 1,
      stdout: e.stdout ?? "",
      stderr: `${e.killed ? "(timed out)\n" : ""}${e.stderr ?? e.message ?? ""}`,
    };
  }
}

export class ShellVerifier implements Verifier {
  constructor(private readonly options: ShellVerifierOptions) {}

  async verify(worktreeDir: string, steps: VerificationStep[]): Promise<VerificationReport> {
    mkdirSync(this.options.logDir, { recursive: true });
    const stepTimeoutMs = this.options.stepTimeoutMs ?? 600_000;
    const results: VerificationReport["steps"] = [];
    for (const step of steps) {
      const result = await runShell(step.command, worktreeDir, stepTimeoutMs);
      const logPath = join(this.options.logDir, `${sanitizeName(step.name)}-${Date.now()}.log`);
      writeFileSync(logPath, `$ ${step.command}\n${result.stdout}\n${result.stderr}`);
      results.push({ name: step.name, passed: result.code === 0, logPath });
    }
    const passed = steps.every((step, index) => results[index]!.passed || !step.required);
    return { passed, steps: results };
  }
}

function sanitizeName(name: string): string {
  return name.replace(/[^a-zA-Z0-9._-]/g, "-");
}
