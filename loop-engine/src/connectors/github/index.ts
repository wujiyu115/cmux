import type { Connector } from "../connector";
import { OctokitGitHubClient, type GitHubClient } from "./client";
import { GitHubIntake } from "./intake";
import { type PollTarget } from "./mapper";
import { GitHubReporter } from "./reporter";

export interface GitHubConnectorOptions {
  token: string;
  webhookSecret?: string;
  labels?: { inProgress?: string; needsHuman?: string };
  /** Repos to poll for missed webhooks, with their trigger rules. */
  pollTargets?: PollTarget[];
}

/** One connector per system: intake and reporter share the client, credentials and identity. */
export function createGitHubConnector(options: GitHubConnectorOptions, client?: GitHubClient): Connector {
  const gh = client ?? new OctokitGitHubClient(options.token);
  return {
    id: "github",
    intake: new GitHubIntake({
      client: gh,
      webhookSecret: options.webhookSecret,
      pollTargets: options.pollTargets,
    }),
    reporter: new GitHubReporter({
      client: gh,
      labels: {
        inProgress: options.labels?.inProgress ?? "loop-in-progress",
        needsHuman: options.labels?.needsHuman ?? "loop-needs-human",
      },
    }),
  };
}
