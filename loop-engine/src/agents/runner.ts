import type { TodoItem } from "../domain/todo";

export interface AgentRunSpec {
  prompt: string;
  cwd: string;
  branch: string;
  timeoutMs: number;
}

export interface AgentRunResult {
  ok: boolean;
  summary: string;
  todos: TodoItem[];
  transcriptPath: string;
  usage: { inputTokens: number; outputTokens: number };
}

export interface AgentRunner {
  id: string;
  run(spec: AgentRunSpec): Promise<AgentRunResult>;
}
