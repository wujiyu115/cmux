import { z } from "zod";

import type { IntakeEvent } from "../../src/domain/events";
import type { Ticket } from "../../src/domain/ticket";
import { adfToText, type JiraIssue } from "./client";

export interface PollProject {
  project: string;
  assignees: string[];
  labels: string[];
}

const accountSchema = z.object({ accountId: z.string() });

const issueFieldsSchema = z.object({
  project: z.object({ key: z.string() }),
  summary: z.string(),
  description: z.unknown().nullish(),
  labels: z.array(z.string()).default([]),
  assignee: accountSchema.nullish(),
  creator: accountSchema,
  created: z.string(),
  updated: z.string(),
});

const issueSchema = z.object({ key: z.string(), fields: issueFieldsSchema });

const changelogSchema = z
  .object({
    id: z.string().optional(),
    items: z.array(
      z.object({
        field: z.string(),
        fromString: z.string().nullish(),
        toString: z.string().nullish(),
      }),
    ),
  })
  .optional();

const issueWebhookSchema = z.object({
  webhookEvent: z.literal("jira:issue_updated"),
  timestamp: z.number().optional(),
  user: accountSchema.optional(),
  issue: issueSchema,
  changelog: changelogSchema,
});

const commentWebhookSchema = z.object({
  timestamp: z.number().optional(),
  user: accountSchema.optional(),
  issue: issueSchema,
  comment: z.object({
    id: z.string(),
    body: z.unknown().nullish(),
    created: z.string(),
    author: accountSchema,
  }),
});

type IssuePayload = z.infer<typeof issueSchema>;

function toTicket(issue: IssuePayload, browseUrl: (key: string) => string): Ticket {
  const fields = issue.fields;
  return {
    id: { connectorId: "jira", externalId: issue.key },
    project: fields.project.key,
    title: fields.summary,
    body: adfToText(fields.description),
    author: fields.creator.accountId,
    labels: fields.labels,
    url: browseUrl(issue.key),
    createdAt: fields.created,
  };
}

function splitLabels(raw: string | null | undefined): string[] {
  return (raw ?? "")
    .split(/[,; ]+/)
    .map((label) => label.trim())
    .filter((label) => label !== "");
}

/**
 * Normalizes one Jira webhook delivery. Update events are changelog-driven:
 * assignee changes become ticket.assigned, label changes become the set
 * difference of the label list. Returns [] for unrelated events and payloads.
 */
export function mapJiraWebhook(
  payload: unknown,
  browseUrl: (key: string) => string,
): IntakeEvent[] {
  const eventName = (payload as { webhookEvent?: unknown } | null)?.webhookEvent;
  if (eventName === "comment_created" || eventName === "jira:comment_created") {
    const parsed = commentWebhookSchema.safeParse(payload);
    if (!parsed.success) return [];
    const data = parsed.data;
    const ticket = toTicket(data.issue, browseUrl);
    return [
      {
        eventId: `jira:${data.issue.key}:comment:${data.comment.id}`,
        actor: data.user?.accountId ?? data.comment.author.accountId,
        kind: "comment.created",
        comment: {
          ticketId: ticket.id,
          externalId: data.comment.id,
          author: data.comment.author.accountId,
          body: adfToText(data.comment.body),
          createdAt: data.comment.created,
        },
      },
    ];
  }

  if (eventName !== "jira:issue_updated") return [];
  const parsed = issueWebhookSchema.safeParse(payload);
  if (!parsed.success) return [];
  const data = parsed.data;
  const fields = data.issue.fields;
  const ticket = toTicket(data.issue, browseUrl);
  const actor = data.user?.accountId ?? fields.creator.accountId;
  const base = `jira:${data.issue.key}:${data.changelog?.id ?? data.timestamp ?? ""}`;
  const events: IntakeEvent[] = [];

  for (const item of data.changelog?.items ?? []) {
    if (item.field === "assignee") {
      if (fields.assignee) {
        events.push({
          eventId: `${base}:assigned:${fields.assignee.accountId}`,
          actor,
          kind: "ticket.assigned",
          ticket,
          assignee: fields.assignee.accountId,
        });
      }
    } else if (item.field === "labels") {
      const before = splitLabels(item.fromString);
      const after = splitLabels(item.toString);
      for (const label of after) {
        if (!before.includes(label)) {
          events.push({
            eventId: `${base}:labeled:${label}`,
            actor,
            kind: "ticket.labeled",
            ticket,
            label,
          });
        }
      }
    }
  }
  return events;
}

/**
 * Poll fallback: re-derives trigger events from issue snapshots. Jira cannot
 * tell us who assigned or labeled, so actor falls back to the creator; the
 * engine's trigger rules and event-id dedup keep re-deliveries inert.
 */
export function mapPollIssue(issue: JiraIssue, target: PollProject): IntakeEvent[] {
  const ticket: Ticket = {
    id: { connectorId: "jira", externalId: issue.key },
    project: issue.projectKey,
    title: issue.summary,
    body: issue.descriptionText,
    author: issue.creatorAccountId,
    labels: issue.labels,
    url: issue.url,
    createdAt: issue.created,
  };
  const events: IntakeEvent[] = [];
  if (issue.assigneeAccountId && target.assignees.includes(issue.assigneeAccountId)) {
    events.push({
      eventId: `poll:jira:${issue.key}:${issue.updated}:assigned:${issue.assigneeAccountId}`,
      actor: ticket.author,
      kind: "ticket.assigned",
      ticket,
      assignee: issue.assigneeAccountId,
      pollDerived: true,
    });
  }
  for (const label of issue.labels) {
    if (target.labels.includes(label)) {
      events.push({
        eventId: `poll:jira:${issue.key}:${issue.updated}:labeled:${label}`,
        actor: ticket.author,
        kind: "ticket.labeled",
        ticket,
        label,
        pollDerived: true,
      });
    }
  }
  return events;
}
