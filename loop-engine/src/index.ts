import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

import { CliAgentRunner } from "./agents/cli_runner";
import { createGitHubConnector } from "./connectors/github";
import { ConnectorRegistry } from "./connectors/registry";
import { loadConfig, type AppConfig } from "./config";
import { LoopEngine } from "./engine/loop";
import { ShellVerifier } from "./engine/shell_verifier";
import { createWebhookServer } from "./http/webhook";
import { loadPlugins } from "./plugins/loader";
import { SqliteWorkStore } from "./store/sqlite_store";
import { GitWorktreeFactory } from "./workspace/git_worktree";

function ensureDirs(config: AppConfig): void {
  for (const dir of [config.engine.transcriptDir, config.engine.logDir, config.engine.worktreesRoot]) {
    mkdirSync(dir, { recursive: true });
  }
  if (config.engine.dbPath !== ":memory:") {
    mkdirSync(dirname(config.engine.dbPath), { recursive: true });
  }
}

async function main(): Promise<void> {
  const configPath = process.argv[2] ?? "config.yaml";
  const config = loadConfig(configPath);
  ensureDirs(config);

  const store = new SqliteWorkStore(config.engine.dbPath);
  const connectors = new ConnectorRegistry();
  const projects = Object.entries(config.repos).map(([project, repoConfig]) => ({
    project,
    assignees: repoConfig.trigger.assignees,
    labels: repoConfig.trigger.labels,
  }));
  if (config.connectors.github) {
    // Poll fallback covers webhook loss; trigger rules mirror the repo config.
    connectors.register(
      createGitHubConnector({
        ...config.connectors.github,
        pollTargets: projects.map(({ project, assignees, labels }) => ({
          repo: project,
          assignees,
          labels,
        })),
      }),
    );
  }
  await loadPlugins(config.plugins, connectors, projects);

  const runners = new Map(
    Object.entries(config.runners).map(([id, runner]) => [
      id,
      new CliAgentRunner({
        id,
        command: runner.command,
        args: runner.args,
        transcriptDir: config.engine.transcriptDir,
      }),
    ]),
  );

  const engine = new LoopEngine(
    {
      connectors,
      runners,
      store,
      worktrees: new GitWorktreeFactory({ root: config.engine.worktreesRoot }),
      verifier: new ShellVerifier({ logDir: config.engine.logDir }),
      now: () => new Date(),
    },
    { repos: config.repos, maxWorkers: config.engine.maxWorkers },
  );

  const server = createWebhookServer({ connectors, onEvents: (events) => engine.ingest(events), store });
  engine.start(config.engine.intervalMs);
  await server.listen({ port: config.engine.port, host: "0.0.0.0" });
  console.log(`loop-engine listening on :${config.engine.port} (config: ${configPath})`);

  let pollTimer: ReturnType<typeof setInterval> | undefined;
  if (config.engine.pollIntervalMs > 0) {
    const pollOnce = async (): Promise<void> => {
      for (const connector of connectors.list()) {
        const intake = connector.intake;
        if (!intake?.poll) continue;
        try {
          const cursor = await store.getPollCursor(connector.id);
          const { events, cursor: next } = await intake.poll(cursor);
          await engine.ingest(events);
          await store.savePollCursor(connector.id, next);
        } catch (err) {
          console.error(`[loop-engine] poll failed for ${connector.id}:`, err);
        }
      }
      await engine.reconcile();
    };
    pollTimer = setInterval(() => {
      void pollOnce().catch((err) => console.error("[loop-engine] poll cycle failed:", err));
    }, config.engine.pollIntervalMs);
  }

  const shutdown = (): void => {
    void (async () => {
      if (pollTimer) clearInterval(pollTimer);
      await engine.stop();
      await server.close();
      store.close();
      process.exit(0);
    })();
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((err) => {
  console.error("[loop-engine] fatal:", err);
  process.exit(1);
});
