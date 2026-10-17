import { z } from "zod";

import type { Connector } from "../../src/connectors/connector";
import { definePlugin } from "../../src/plugins/sdk";
import { RestJiraClient, type JiraClient } from "./client";
import { JiraIntake } from "./intake";
import { JiraReporter } from "./reporter";

export const jiraConfigSchema = z.object({
  baseUrl: z.string().url(),
  email: z.string().min(1),
  apiToken: z.string().min(1),
  transitions: z
    .object({
      inProgress: z.string().default("In Progress"),
      blocked: z.string().optional(),
    })
    .default({}),
  ignoreActors: z.array(z.string()).default([]),
});

export type JiraConfig = z.infer<typeof jiraConfigSchema>;

export interface JiraConnectorOptions extends JiraConfig {
  /** Projects to poll for missed webhooks, derived from engine repos config. */
  pollProjects: Array<{ project: string; assignees: string[]; labels: string[] }>;
}

export function createJiraConnector(options: JiraConnectorOptions, client?: JiraClient): Connector {
  const jira = client ?? new RestJiraClient(options);
  return {
    id: "jira",
    intake: new JiraIntake({
      client: jira,
      pollProjects: options.pollProjects,
      ignoreActors: options.ignoreActors,
    }),
    reporter: new JiraReporter({ client: jira, transitions: options.transitions }),
  };
}

export default definePlugin({ id: "jira", name: "Jira Cloud", version: "0.1.0" }, (ctx) => {
  const config = jiraConfigSchema.parse(ctx.config ?? {});
  return createJiraConnector({ ...config, pollProjects: ctx.projects });
});
