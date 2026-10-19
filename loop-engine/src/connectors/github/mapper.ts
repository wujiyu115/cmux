import { z } from "zod";

import type { IntakeEvent } from "../../domain/events";
import type { Ticket } from "../../domain/ticket";
import type { SearchIssueItem } from "./client";

const issueSchema = z.object({
  number: z.number(),
  title: z.string(),
  body: z.string().nullish(),
  html_url: z.string(),
  created_at: z.string(),
  user: z.object({ login: z.string() }),
  labels: z.array(z.object({ name: z.string() })).default([]),
});

const repositorySchema = z.object({ full_name: z.string() });

const issuesPayloadSchema = z.object({
  action: z.string(),
  issue: issueSchema,
  repository: repositorySchema,
  sender: z.object({ login: z.string() }),
  assignee: z.object({ login: z.string() }).nullish(),
  label: z.object({ name: z.string() }).optional(),
});

const issueCommentPayloadSchema = z.object({
  action: z.string(),
  issue: issueSchema,
  comment: z.object({
    id: z.number(),
    body: z.string(),
    created_at: z.string(),
    user: z.object({ login: z.string() }),
  }),
  repository: repositorySchema,
  sender: z.object({ login: z.string() }),
});

type IssuePayload = z.infer<typeof issuesPayloadSchema>;

function toTicket(issue: IssuePayload["issue"], repoFullName: string): Ticket {
  return {
    id: { connectorId: "github", externalId: `${repoFullName}#${issue.number}` },
    project: repoFullName,
    title: issue.title,
    body: issue.body ?? "",
    // GitHub logins are case-insensitive; normalize so identity comparisons hold.
    author: issue.user.login.toLowerCase(),
    labels: issue.labels.map((l) => l.name),
    url: issue.html_url,
    createdAt: issue.created_at,
  };
}

/**
 * Normalizes one GitHub webhook delivery into at most one IntakeEvent.
 * Unmapped actions (opened, edited, ping, pull_request, ...) return null.
 */
export function mapGitHubWebhook(
  deliveryId: string,
  eventName: string | undefined,
  payload: unknown,
): IntakeEvent | null {
  if (eventName === "issues") {
    const parsed = issuesPayloadSchema.safeParse(payload);
    if (!parsed.success) return null;
    const data = parsed.data;
    const ticket = toTicket(data.issue, data.repository.full_name);
    const actor = data.sender.login.toLowerCase();
    if (data.action === "assigned" && data.assignee) {
      return {
        eventId: deliveryId,
        actor,
        kind: "ticket.assigned",
        ticket,
        assignee: data.assignee.login.toLowerCase(),
      };
    }
    if (data.action === "labeled" && data.label) {
      return { eventId: deliveryId, actor, kind: "ticket.labeled", ticket, label: data.label.name };
    }
    return null;
  }

  if (eventName === "issue_comment") {
    const parsed = issueCommentPayloadSchema.safeParse(payload);
    if (!parsed.success) return null;
    const data = parsed.data;
    if (data.action !== "created") return null;
    const ticket = toTicket(data.issue, data.repository.full_name);
    return {
      eventId: deliveryId,
      actor: data.sender.login.toLowerCase(),
      kind: "comment.created",
      comment: {
        ticketId: ticket.id,
        externalId: String(data.comment.id),
        author: data.comment.user.login.toLowerCase(),
        body: data.comment.body,
        createdAt: data.comment.created_at,
      },
    };
  }

  return null;
}

export function parseIssueRef(externalId: string): { owner: string; repo: string; number: number } {
  const match = /^([^/#]+)\/([^/#]+)#(\d+)$/.exec(externalId);
  if (!match) throw new Error(`malformed GitHub issue ref: ${externalId}`);
  return { owner: match[1]!, repo: match[2]!, number: Number(match[3]) };
}

export function parseRepoRef(repo: string): { owner: string; repo: string } {
  const match = /^([^/#\s]+)\/([^/#\s]+)$/.exec(repo);
  if (!match) throw new Error(`malformed repo ref: ${repo}`);
  return { owner: match[1]!, repo: match[2]! };
}

const searchItemSchema = z.object({
  number: z.number(),
  title: z.string(),
  body: z.string().nullish(),
  htmlUrl: z.string(),
  createdAt: z.string(),
  updatedAt: z.string(),
  authorLogin: z.string(),
  labels: z.array(z.string()).default([]),
  assigneeLogin: z.string().optional(),
});

export interface PollTarget {
  repo: string;
  assignees: string[];
  labels: string[];
}

/**
 * Maps polled issue snapshots to trigger events. Poll cannot know who assigned
 * or labeled, so `actor` falls back to the issue author; the engine's trigger
 * rules filter by assignee/label and event-id dedup keeps re-deliveries inert.
 */
export function mapPollIssue(item: SearchIssueItem, target: PollTarget): IntakeEvent[] {
  const parsed = searchItemSchema.safeParse(item);
  if (!parsed.success) return [];
  const data = parsed.data;
  const ticket: Ticket = {
    id: { connectorId: "github", externalId: `${target.repo}#${data.number}` },
    project: target.repo,
    title: data.title,
    body: data.body ?? "",
    author: data.authorLogin.toLowerCase(),
    labels: data.labels,
    url: data.htmlUrl,
    createdAt: data.createdAt,
  };

  const events: IntakeEvent[] = [];
  const assignee = data.assigneeLogin?.toLowerCase();
  if (assignee && target.assignees.some((a) => a.toLowerCase() === assignee)) {
    events.push({
      eventId: `poll:${target.repo}#${data.number}:${data.updatedAt}:assigned:${assignee}`,
      actor: ticket.author,
      kind: "ticket.assigned",
      ticket,
      assignee,
      pollDerived: true,
    });
  }
  for (const label of data.labels) {
    if (target.labels.includes(label)) {
      events.push({
        eventId: `poll:${target.repo}#${data.number}:${data.updatedAt}:labeled:${label}`,
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
