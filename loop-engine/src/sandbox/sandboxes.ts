import { homedir } from "node:os";
import { resolve } from "node:path";

import type { Sandbox, SandboxConfig, SandboxSpec, SandboxedCommand } from "./sandbox";
import { NullSandbox } from "./sandbox";

/**
 * Docker-based sandbox for agent CLIs. The worktree is bind-mounted writable
 * at the same host path (so git/agent paths stay identical), $HOME is mounted
 * read-only so credentials (~/.claude, ~/.pi, provider keychains) work, and
 * the network is on by default because pi and Claude Code need LLM API
 * access. Set allowNetwork: false to run fully hermetic.
 *
 * Path conversion is performed in the container path syntax (posix); on
 * Windows hosts this sandbox is not selectable (config validation rejects it).
 */
export class DockerSandbox implements Sandbox {
  readonly id = "docker";

  constructor(private readonly options: { image: string; allowNetwork?: boolean; home?: string }) {}

  wrap(spec: SandboxSpec): SandboxedCommand {
    const home = this.options.home ?? homedir();
    const network = this.options.allowNetwork === false ? ["--network", "none"] : [];
    const cwd = toPosix(spec.cwd);
    return {
      command: "docker",
      args: [
        "run",
        "--rm",
        "-i",
        ...network,
        "--mount",
        `type=bind,source=${spec.cwd},target=${cwd}`,
        "--mount",
        `type=bind,source=${home},target=${toPosix(home)},readonly`,
        "-w",
        cwd,
        "-e",
        `HOME=${toPosix(home)}`,
        this.options.image,
        spec.command,
        ...spec.args,
      ],
      cwd: resolve(spec.cwd),
    };
  }
}

/** Linux bubblewrap sandbox: user namespaces, no daemon, fine-grained binds. */
export class BwrapSandbox implements Sandbox {
  readonly id = "bwrap";

  constructor(private readonly options: { allowNetwork?: boolean; home?: string }) {}

  wrap(spec: SandboxSpec): SandboxedCommand {
    const home = this.options.home ?? homedir();
    const network = this.options.allowNetwork === false ? ["--unshare-net"] : [];
    const args = [
      "--dev-bind",
      "/",
      "/",
      "--bind",
      spec.cwd,
      spec.cwd,
      "--ro-bind",
      home,
      home,
      ...network,
      "--die-with-parent",
      spec.command,
      ...spec.args,
    ];
    return { command: "bwrap", args, cwd: spec.cwd };
  }
}

export function createSandbox(config: SandboxConfig | undefined): Sandbox {
  if (!config || config.mode === "none") return new NullSandbox();
  if (config.mode === "docker") {
    if (process.platform === "win32") {
      throw new Error(`sandbox mode "docker" is not supported on Windows hosts yet`);
    }
    if (!config.image) {
      throw new Error(`sandbox mode "docker" requires engine.sandbox.image`);
    }
    return new DockerSandbox({ image: config.image, allowNetwork: config.allowNetwork });
  }
  if (config.mode === "bwrap") {
    if (process.platform !== "linux") {
      throw new Error(`sandbox mode "bwrap" is only supported on Linux`);
    }
    return new BwrapSandbox({ allowNetwork: config.allowNetwork });
  }
  throw new Error(`unknown sandbox mode: ${(config as { mode: string }).mode}`);
}

/** Windows drive letters (D:\\x) become docker-style posix paths (/d/x not needed — we keep host path but normalize separators). */
function toPosix(path: string): string {
  return path.replace(/\\/g, "/");
}
