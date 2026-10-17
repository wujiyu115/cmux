import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { ConnectorRegistry } from "../../src/connectors/registry";
import { loadPlugins, resolveEnvSecrets } from "../../src/plugins/loader";

const fixturesRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "fixtures", "plugins");
const fixture = (name: string): string => join(fixturesRoot, name);

describe("loadPlugins", () => {
  it("loads a plugin from a directory and registers its connector", async () => {
    const registry = new ConnectorRegistry();
    const loaded = await loadPlugins([{ path: fixture("echo") }], registry);
    expect(loaded.map((c) => c.id)).toEqual(["echo"]);
    expect(registry.get("echo")?.intake).toBeDefined();
  });

  it("loads a plugin from a direct file path", async () => {
    const registry = new ConnectorRegistry();
    await loadPlugins([{ path: fixture("echo/plugin.ts") }], registry);
    expect(registry.get("echo")).toBeDefined();
  });

  it("passes env-resolved config to the plugin", async () => {
    process.env.LOADER_TEST_ACTOR = "alice";
    const registry = new ConnectorRegistry();
    await loadPlugins(
      [{ path: fixture("config-echo"), config: { actors: ["env:LOADER_TEST_ACTOR", "bob"] } }],
      registry,
    );
    expect(await registry.get("config-echo")!.intake!.selfIdentities()).toEqual(["alice", "bob"]);
  });

  it("passes the repo projects into the plugin context", async () => {
    const registry = new ConnectorRegistry();
    await loadPlugins([{ path: fixture("projects-echo") }], registry, [
      { project: "owner/repo", assignees: ["loop-agent"], labels: ["loop"] },
      { project: "PROJ", assignees: ["acc-1"], labels: [] },
    ]);
    expect(await registry.get("projects-echo")!.intake!.selfIdentities()).toEqual(["owner/repo", "PROJ"]);
  });

  it("throws when an env secret is missing", async () => {
    delete process.env.LOADER_TEST_MISSING;
    const registry = new ConnectorRegistry();
    await expect(
      loadPlugins([{ path: fixture("config-echo"), config: { actors: ["env:LOADER_TEST_MISSING"] } }], registry),
    ).rejects.toThrow(/LOADER_TEST_MISSING/);
  });

  it("rejects modules without a valid manifest", async () => {
    const registry = new ConnectorRegistry();
    await expect(loadPlugins([{ path: fixture("bad-shape") }], registry)).rejects.toThrow(/manifest/);
  });

  it("rejects connectors implementing neither intake nor reporter", async () => {
    const registry = new ConnectorRegistry();
    await expect(loadPlugins([{ path: fixture("neither") }], registry)).rejects.toThrow(
      /neither intake nor reporter/,
    );
  });

  it("rejects manifest/connector id mismatches", async () => {
    const registry = new ConnectorRegistry();
    await expect(loadPlugins([{ path: fixture("mismatch") }], registry)).rejects.toThrow(/does not match/);
  });

  it("rejects duplicate connector ids", async () => {
    const registry = new ConnectorRegistry();
    await loadPlugins([{ path: fixture("echo") }], registry);
    await expect(loadPlugins([{ path: fixture("echo") }], registry)).rejects.toThrow(/already registered/);
  });

  it("reports plugin directories without an entry file", async () => {
    const registry = new ConnectorRegistry();
    await expect(loadPlugins([{ path: fixture(".") }], registry)).rejects.toThrow(/no plugin entry/);
  });
});

describe("resolveEnvSecrets", () => {
  it("resolves nested structures and leaves plain values alone", () => {
    process.env.LOADER_TEST_A = "x";
    expect(resolveEnvSecrets({ a: "env:LOADER_TEST_A", b: [{ c: "plain", d: 1 }] })).toEqual({
      a: "x",
      b: [{ c: "plain", d: 1 }],
    });
  });
});
