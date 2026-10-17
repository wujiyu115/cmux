import type { Ticket } from "../domain/ticket";
import type { TodoItem } from "../domain/todo";

export function buildPlannerPrompt(ticket: Ticket, failureContext?: string): string {
  const sections = [
    "# Ticket",
    `Title: ${ticket.title}`,
    `URL: ${ticket.url}`,
    `Labels: ${ticket.labels.join(", ") || "none"}`,
    `Author: ${ticket.author}`,
    "",
    "## Description",
    ticket.body || "(empty)",
  ];
  if (failureContext) {
    sections.push("", "## Previous attempt failed with", failureContext, "", "Take this into account and adjust the plan.");
  }
  sections.push(
    "",
    "# Task",
    "Break the ticket down into a short, verifiable todo list. Prefer steps that map to observable checks.",
    "",
    "End your reply with exactly one fenced json block in this shape:",
    "```json",
    '{"todos": [{"text": "short imperative step", "status": "pending"}]}',
    "```",
    "Keep each todo text under 100 characters.",
  );
  return sections.join("\n");
}

export function buildExecutorPrompt(ticket: Ticket, todos: TodoItem[], failureContext?: string): string {
  const sections = [
    "# Ticket",
    `${ticket.title} (${ticket.url})`,
    "",
    "## Todos",
    ...todos.map((t) => `- [${t.status}] ${t.text}`),
  ];
  if (failureContext) {
    sections.push("", "## Previous attempt failed with", failureContext);
  }
  sections.push(
    "",
    "# Task",
    "Work through the todos in the repository at the current working directory, then commit all changes to the current branch with a clear message.",
  );
  return sections.join("\n");
}
