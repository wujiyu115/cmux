export interface TicketId {
  /** Which connector owns this ticket, e.g. "github". Reporter routing key. */
  connectorId: string;
  /** Connector-local identity, e.g. "owner/repo#123". */
  externalId: string;
}

export interface Ticket {
  id: TicketId;
  /** Config lookup key, e.g. "owner/repo" (GitHub) or "PROJ" (Jira). */
  project: string;
  title: string;
  body: string;
  /** Normalized account identifier of the ticket author. */
  author: string;
  labels: string[];
  url: string;
  createdAt: string;
}

export interface Comment {
  ticketId: TicketId;
  externalId: string;
  author: string;
  body: string;
  createdAt: string;
}
