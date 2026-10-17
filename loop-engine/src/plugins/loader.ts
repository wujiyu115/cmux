import { existsSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { z } from "zod";

import type { Connector } from "../connectors/connector";
import type { ConnectorRegistry } from "../connectors/registry";
import type { ConnectorPlugin, PluginProject } from "./sdk";

export interface PluginSpec {
  /** Plugin directory (needs plugin.ts/plugin.js or index.ts/index.js) or module file. */
  path: string;
  config?: Record<string, unknown>;
}

const manifestSchema = z.object({
  id: z.string().min(1),
  name: z.string().optional(),
  version: z.string().min(1),
});

const ENTRY_CANDIDATES = ["plugin.ts", "plugin.js", "index.ts", "index.js"];

function resolveModulePath(path: string): string {
  const resolved = resolve(path);
  if (!existsSync(resolved)) return resolved; // let import() produce the error
  if (!statSync(resolved).isDirectory()) return resolved;
  const entry = ENTRY_CANDIDATES.map((candidate) => join(resolved, candidate)).find((candidate) =>
    existsSync(candidate),
  );
  if (!entry) {
    throw new Error(`no plugin entry found in ${resolved} (expected plugin.ts, plugin.js, index.ts or index.js)`);
  }
  return entry;
}

/** Deep-resolves "env:VAR" strings so secrets stay out of config files. */
export function resolveEnvSecrets(value: unknown): unknown {
  if (typeof value === "string") {
    if (!value.startsWith("env:")) return value;
    const name = value.slice("env:".length);
    const resolved = process.env[name];
    if (!resolved) throw new Error(`environment variable ${name} is not set (plugin config)`);
    return resolved;
  }
  if (Array.isArray(value)) return value.map(resolveEnvSecrets);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, resolveEnvSecrets(item)]));
  }
  return value;
}

async function importPlugin(modulePath: string): Promise<ConnectorPlugin> {
  const mod = (await import(pathToFileURL(modulePath).href)) as { default?: unknown; plugin?: unknown };
  const candidate = mod.default ?? mod.plugin;
  if (!candidate || typeof candidate !== "object") {
    throw new Error(`${modulePath} must default-export a plugin (see definePlugin)`);
  }
  const plugin = candidate as Partial<ConnectorPlugin>;
  const manifest = manifestSchema.safeParse(plugin.manifest);
  if (!manifest.success) {
    throw new Error(`${modulePath}: invalid plugin manifest (${manifest.error.message})`);
  }
  if (typeof plugin.createConnector !== "function") {
    throw new Error(`${modulePath}: plugin has no createConnector()`);
  }
  return plugin as ConnectorPlugin;
}

export async function loadPlugins(
  specs: PluginSpec[],
  registry: ConnectorRegistry,
  projects: PluginProject[] = [],
): Promise<Connector[]> {
  const loaded: Connector[] = [];
  for (const spec of specs) {
    const modulePath = resolveModulePath(spec.path);
    const plugin = await importPlugin(modulePath);
    const config = resolveEnvSecrets(spec.config ?? {}) as Record<string, unknown>;
    const connector = await plugin.createConnector({ config, projects });
    if (connector.id !== plugin.manifest.id) {
      throw new Error(
        `${modulePath}: manifest id "${plugin.manifest.id}" does not match connector id "${connector.id}"`,
      );
    }
    if (!connector.intake && !connector.reporter) {
      throw new Error(`${modulePath}: plugin "${connector.id}" implements neither intake nor reporter`);
    }
    if (registry.get(connector.id)) {
      throw new Error(`connector id "${connector.id}" is already registered`);
    }
    registry.register(connector);
    loaded.push(connector);
    console.log(`[loop-engine] loaded plugin ${plugin.manifest.id}@${plugin.manifest.version} from ${spec.path}`);
  }
  return loaded;
}
