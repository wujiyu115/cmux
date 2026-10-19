import { describe, expect, it } from "vitest";

import type { Sandbox, SandboxSpec } from "../../src/sandbox/sandbox";
import { NullSandbox } from "../../src/sandbox/sandbox";
import { BwrapSandbox, createSandbox, DockerSandbox } from "../../src/sandbox/sandboxes";

const HOME = "/home/agent";

function spec(): SandboxSpec {
  return { command: "pi", args: ["--mode", "json", "--print"], cwd: "/srv/worktrees/loop-1" };
}

describe("NullSandbox", () => {
  it("passes the command through unchanged", () => {
    const wrapped = new NullSandbox().wrap(spec());
    expect(wrapped).toEqual({ command: "pi", args: ["--mode", "json", "--print"] });
  });
});

describe("DockerSandbox", () => {
  function wrap(s: Sandbox): ReturnType<Sandbox["wrap"]> {
    return s.wrap({ ...spec(), command: "claude", args: ["-p", "--output-format", "json"] });
  }

  it("wraps the CLI with a writable worktree bind and read-only home", () => {
    const sandbox = new DockerSandbox({ image: "agent-cli:latest", home: HOME });
    const wrapped = wrap(sandbox);
    expect(wrapped.command).toBe("docker");
    expect(wrapped.args).toContain("agent-cli:latest");
    expect(wrapped.args.join(" ")).toContain(
      `type=bind,source=/srv/worktrees/loop-1,target=/srv/worktrees/loop-1`,
    );
    expect(wrapped.args.join(" ")).toContain(`type=bind,source=${HOME},target=${HOME},readonly`);
    // the original CLI runs inside the container
    expect(wrapped.args.slice(-4)).toEqual(["claude", "-p", "--output-format", "json"]);
    // network on by default: pi / Claude Code need LLM API access
    expect(wrapped.args).not.toContain("none");
  });

  it("cuts the network when allowNetwork is false", () => {
    const sandbox = new DockerSandbox({ image: "img", allowNetwork: false, home: HOME });
    expect(sandbox.wrap(spec()).args).toContain("none");
  });
});

describe("BwrapSandbox", () => {
  it("binds the root and worktree, read-only home, dies with parent", () => {
    const sandbox = new BwrapSandbox({ home: HOME });
    const wrapped = sandbox.wrap(spec());
    expect(wrapped.command).toBe("bwrap");
    const args = wrapped.args.join(" ");
    expect(args).toContain("--bind /srv/worktrees/loop-1 /srv/worktrees/loop-1");
    expect(args).toContain(`--ro-bind ${HOME} ${HOME}`);
    expect(args).toContain("--die-with-parent");
    expect(args).toContain("pi --mode json --print");
  });

  it("unshares the network when allowNetwork is false", () => {
    const sandbox = new BwrapSandbox({ allowNetwork: false, home: HOME });
    expect(sandbox.wrap(spec()).args).toContain("--unshare-net");
  });
});

describe("createSandbox", () => {
  it("returns NullSandbox for none/undefined", () => {
    expect(createSandbox(undefined).id).toBe("none");
    expect(createSandbox({ mode: "none" }).id).toBe("none");
  });

  it("requires an image for docker mode", () => {
    withPlatform("linux", () => {
      expect(() => createSandbox({ mode: "docker" })).toThrow(/requires .*image/);
    });
  });

  it("rejects bwrap outside linux", () => {
    withPlatform("win32", () => {
      expect(() => createSandbox({ mode: "bwrap" })).toThrow(/only supported on Linux/);
    });
  });

  it("builds a docker sandbox on linux hosts", () => {
    withPlatform("linux", () => {
      expect(createSandbox({ mode: "docker", image: "img" }).id).toBe("docker");
    });
  });
});

/** Stubs process.platform for host-independent assertions. */
function withPlatform(platform: string, fn: () => void): void {
  const original = Object.getOwnPropertyDescriptor(process, "platform");
  Object.defineProperty(process, "platform", { value: platform, configurable: true });
  try {
    fn();
  } finally {
    if (original) Object.defineProperty(process, "platform", original);
  }
}
