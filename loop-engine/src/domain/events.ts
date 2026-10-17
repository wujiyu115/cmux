import type { Comment, Ticket } from "./ticket";

/**
 * Normalized intake event. The engine never sees connector payloads.
 * `eventId` must be globally unique (at-least-once delivery dedup);
 * `actor` is the normalized account that caused the event (self-loop guard).
 */
export type IntakeEvent =
  | { eventId: string; actor: string; kind: "ticket.assigned"; ticket: Ticket; assignee: string }
  | { eventId: string; actor: string; kind: "ticket.labeled"; ticket: Ticket; label: string }
  | { eventId: string; actor: string; kind: "comment.created"; comment: Comment };
