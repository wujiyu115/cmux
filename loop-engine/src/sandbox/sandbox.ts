/**
 * Sandboxing seam for agent CLI invocations. A sandbox rewrites the spawn
 * command so the agent runs inside an isolated environment; the runner stays
 * responsible for transcripts, timeouts and output parsing.
 *
 * Implementations must be pure argv rewrites (no IO) so they stay trivially
 * testable; the actual isolation is provided by the wrapped tool
 * (docker / bubblewrap).
 */

export interface SandboxSpec {
  /** Executable the runner wants to launch, e.g. "claude". */
  command: string;
  /** Extra args for the executable. */
  args: string[];
  /** Host working directory the process needs visible and writable. */
  cwd: string;
}

export interface SandboxedCommand {
  command: string;
  args: string[];
  /** Override for the spawn cwd; omit to keep the runner's cwd. */
  cwd?: string;
}

export interface Sandbox {
  readonly id: string;
  wrap(spec: SandboxSpec): SandboxedCommand;
}

export type SandboxMode = "none" | "docker" | "bwrap";

export interface SandboxConfig {
  mode: SandboxMode;
  /** docker: image to run the agent CLI in (must contain the CLI). */
  image?: string;
  /** Allow outbound network inside the sandbox (default: denied). */
  allowNetwork?: boolean;
}

/** Pass-through: the original behavior, used when mode is "none". */
export class NullSandbox implements Sandbox {
  readonly id = "none";

  wrap(spec: SandboxSpec): SandboxedCommand {
    return { command: spec.command, args: spec.args };
  }
}
