import type { TicketId } from "../domain/ticket";
import type { WorkRecord } from "../domain/work";
import { ACTIONABLE_STATUSES, ACTIVE_STATUSES } from "../domain/work";
import type { PollCursor } from "../connectors/connector";

export interface WorkStore {
  create(record: WorkRecord): Promise<void>;
  update(record: WorkRecord): Promise<void>;
  get(id: string): Promise<WorkRecord | undefined>;
  list(): Promise<WorkRecord[]>;
  findActiveByTicket(ticketId: TicketId): Promise<WorkRecord | undefined>;
  nextActionable(): Promise<WorkRecord | undefined>;
  listAwaitingReview(): Promise<WorkRecord[]>;
  hasEvent(eventId: string): Promise<boolean>;
  markEvent(eventId: string): Promise<void>;
  getPollCursor(connectorId: string): Promise<PollCursor | null>;
  savePollCursor(connectorId: string, cursor: PollCursor): Promise<void>;
}

/** Phase 0 store; SQLite implementation lands with Phase 1 persistence. */
export class InMemoryWorkStore implements WorkStore {
  private readonly records = new Map<string, WorkRecord>();
  private readonly seenEvents = new Set<string>();
  private readonly cursors = new Map<string, string>();

  async create(record: WorkRecord): Promise<void> {
    this.records.set(record.id, { ...record });
  }

  async update(record: WorkRecord): Promise<void> {
    this.records.set(record.id, { ...record });
  }

  async get(id: string): Promise<WorkRecord | undefined> {
    const record = this.records.get(id);
    return record ? { ...record } : undefined;
  }

  async list(): Promise<WorkRecord[]> {
    return [...this.records.values()].map((r) => ({ ...r }));
  }

  async findActiveByTicket(ticketId: TicketId): Promise<WorkRecord | undefined> {
    const found = [...this.records.values()].find(
      (r) =>
        r.ticket.id.connectorId === ticketId.connectorId &&
        r.ticket.id.externalId === ticketId.externalId &&
        ACTIVE_STATUSES.includes(r.status),
    );
    return found ? { ...found } : undefined;
  }

  async nextActionable(): Promise<WorkRecord | undefined> {
    const found = [...this.records.values()].find((r) => ACTIONABLE_STATUSES.includes(r.status));
    return found ? { ...found } : undefined;
  }

  async listAwaitingReview(): Promise<WorkRecord[]> {
    return [...this.records.values()]
      .filter((r) => r.status === "awaiting_review")
      .map((r) => ({ ...r }));
  }

  async hasEvent(eventId: string): Promise<boolean> {
    return this.seenEvents.has(eventId);
  }

  async markEvent(eventId: string): Promise<void> {
    this.seenEvents.add(eventId);
  }

  async getPollCursor(connectorId: string): Promise<PollCursor | null> {
    const at = this.cursors.get(connectorId);
    return at ? { at } : null;
  }

  async savePollCursor(connectorId: string, cursor: PollCursor): Promise<void> {
    this.cursors.set(connectorId, cursor.at);
  }
}
