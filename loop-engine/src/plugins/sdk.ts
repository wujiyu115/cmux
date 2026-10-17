import type { Connector } from "../connectors/connector";

export interface ConnectorPluginManifest {
  /** Must match the created connector's id. */
  id: string;
  name?: string;
  version: string;
}

/** Engine repo/project config slice: poll queries and triggers derive from these. */
export interface PluginProject {
  project: string;
  assignees: string[];
  labels: string[];
}

export interface ConnectorPluginContext {
  /** Plugin config from config.yaml with env: secrets already resolved. */
  config: Record<string, unknown>;
  /** All configured repo projects; connectors use them to build poll targets. */
  projects: PluginProject[];
}

export interface ConnectorPlugin {
  manifest: ConnectorPluginManifest;
  createConnector(ctx: ConnectorPluginContext): Connector | Promise<Connector>;
}

export function definePlugin(
  manifest: ConnectorPluginManifest,
  createConnector: (ctx: ConnectorPluginContext) => Connector | Promise<Connector>,
): ConnectorPlugin {
  return { manifest, createConnector };
}
