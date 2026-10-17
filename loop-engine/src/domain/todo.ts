export type TodoStatus = "pending" | "in_progress" | "done";

export interface TodoItem {
  text: string;
  status: TodoStatus;
}
