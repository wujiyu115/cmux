import { readFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { ShellVerifier } from "../../src/engine/shell_verifier";
import type { VerificationStep } from "../../src/engine/verifier";

const fixturesDir = join(dirname(fileURLToPath(import.meta.url)), "..", "fixtures");
const exit0 = join(fixturesDir, "exit0.mjs").replace(/\\/g, "/");
const exit1 = join(fixturesDir, "exit1.mjs").replace(/\\/g, "/");
const echo = join(fixturesDir, "echo.mjs").replace(/\\/g, "/");

function makeVerifier(): ShellVerifier {
  const logDir = mkdtempSync(join(tmpdir(), "loop-logs-"));
  return new ShellVerifier({ logDir });
}

describe("ShellVerifier", () => {
  it("passes when required steps succeed", async () => {
    const verifier = makeVerifier();
    const steps: VerificationStep[] = [{ name: "ok step", command: `node ${exit0}`, required: true }];
    const report = await verifier.verify(process.cwd(), steps);
    expect(report.passed).toBe(true);
    expect(report.steps[0]!.passed).toBe(true);
  });

  it("fails when a required step fails", async () => {
    const verifier = makeVerifier();
    const steps: VerificationStep[] = [{ name: "bad step", command: `node ${exit1}`, required: true }];
    const report = await verifier.verify(process.cwd(), steps);
    expect(report.passed).toBe(false);
    expect(report.steps[0]!.passed).toBe(false);
  });

  it("tolerates failures of non-required steps", async () => {
    const verifier = makeVerifier();
    const steps: VerificationStep[] = [
      { name: "optional step", command: `node ${exit1}`, required: false },
      { name: "required step", command: `node ${exit0}`, required: true },
    ];
    const report = await verifier.verify(process.cwd(), steps);
    expect(report.passed).toBe(true);
    expect(report.steps[0]!.passed).toBe(false);
    expect(report.steps[1]!.passed).toBe(true);
  });

  it("captures command output in log files", async () => {
    const verifier = makeVerifier();
    const steps: VerificationStep[] = [{ name: "echo step", command: `node ${echo}`, required: true }];
    const report = await verifier.verify(process.cwd(), steps);
    const log = readFileSync(report.steps[0]!.logPath, "utf8");
    expect(log).toContain("hello stdout");
    expect(log).toContain("hello stderr");
  });
});
