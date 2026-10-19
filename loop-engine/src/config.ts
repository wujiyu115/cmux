import { readFileSync } from "node:fs";
import { parse as parseYaml } from "yaml";
import { z } from "zod";

/** Resolves "env:VAR" references so secrets stay out of the config file. */
const secret = z.string().transform((value, ctx) => {
  if (!value.startsWith("env:")) return value;
  const name = value.slice("env:".length);
  const resolved = process.env[name];
  if (!resolved) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: `environment variable ${name} is not set` });
    return z.NEVER;
  }
  return resolved;
});

const verificationStepSchema = z.object({
  name: z.string().min(1),
  command: z.string().min(1),
  required: z.boolean().default(true),
});

const repoConfigSchema = z.object({
  repoDir: z.string().min(1),
  runner: z.string().min(1),
  reporter: z.string().min(1).optional(),
  trigger: z.object({
    assignees: z.array(z.string()).default([]),
    labels: z.array(z.string()).default([]),
  }),
  verification: z.array(verificationStepSchema).default([]),
  budget: z
    .object({
      maxAttempts: z.number().int().min(1).default(3),
      timeoutMs: z.number().int().positive().default(600_000),
      /** Optional per-work token cap (input + output); checked before each attempt. */
      maxTokens: z.number().int().positive().optional(),
    })
    .default({}),
  pr: z.object({ base: z.string().default("main") }).default({}),
});

const runnerConfigSchema = z.object({
  command: z.string().min(1),
  args: z.array(z.string()).default([]),
});

const pluginSpecSchema = z.object({
  path: z.string().min(1),
  config: z.record(z.string(), z.unknown()).optional(),
});

const githubConnectorSchema = z.object({
  token: secret,
  webhookSecret: secret.optional(),
  labels: z
    .object({
      inProgress: z.string().default("loop-in-progress"),
      needsHuman: z.string().default("loop-needs-human"),
    })
    .default({}),
});

export const appConfigSchema = z.object({
  engine: z
    .object({
      dbPath: z.string().default("./data/loop-engine.db"),
      intervalMs: z.number().int().positive().default(5_000),
      /** Interval for the webhook-loss poll fallback; 0 disables polling. */
      pollIntervalMs: z.number().int().min(0).default(60_000),
      transcriptDir: z.string().default("./data/transcripts"),
      logDir: z.string().default("./data/logs"),
      worktreesRoot: z.string().default("./data/worktrees"),
      port: z.number().int().positive().default(8787),
      /** Concurrent work records advanced per tick; 1 keeps the serial loop. */
      maxWorkers: z.number().int().min(1).default(1),
      /** Agent CLI execution isolation: "none" | "docker" | "bwrap". */
      sandbox: z
        .object({
          mode: z.enum(["none", "docker", "bwrap"]).default("none"),
          image: z.string().optional(),
          /** pi and Claude Code need LLM API access, so network defaults to on. */
          allowNetwork: z.boolean().optional(),
        })
        .default({}),
    })
    .default({}),
  connectors: z.object({ github: githubConnectorSchema.optional() }).default({}),
  plugins: z.array(pluginSpecSchema).default([]),
  runners: z.record(z.string().min(1), runnerConfigSchema),
  repos: z.record(z.string().min(1), repoConfigSchema),
});

export type AppConfig = z.output<typeof appConfigSchema>;

export function loadConfig(path: string): AppConfig {
  const raw = readFileSync(path, "utf8");
  const parsed: unknown = parseYaml(raw);
  return appConfigSchema.parse(parsed);
}
