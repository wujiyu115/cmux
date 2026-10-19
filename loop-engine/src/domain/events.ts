import type { Comment, Ticket } from "./ticket";

/** Marks poll-derived events: they observe state, not a write action, so the
 * self-loop guard does not apply (a maintainer who authors and self-assigns
 * their own issue is the common single-person setup). */
export interface PollDerived {
  /** True when the event was synthesized from a state poll, not a webhook. */
  pollDerived?: boolean;
}

/**
 * Normalized intake event. The engine never sees connector payloads.
 * `eventId` must be globally unique (at-least-once delivery dedup);
 * `actor` is the normalized account that caused the event (self-loop guard
 * skips poll-derived events — see PollDerived).
 */
export type IntakeEvent = PollDerived &
  (
    | { eventId: string; actor: string; kind: "ticket.assigned"; ticket: Ticket; assignee: string }
    | { eventId: string; actor: string; kind: "ticket.labeled"; ticket: Ticket; label: string }
    | { eventId: string; actor: string; kind: "comment.created"; comment: Comment }
  );
