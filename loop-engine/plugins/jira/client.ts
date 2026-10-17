/** Normalized Jira issue snapshot, independent of the raw REST shape. */
export interface JiraIssue {
  key: string;
  projectKey: string;
  summary: string;
  descriptionText: string;
  creatorAccountId: string;
  labels: string[];
  assigneeAccountId?: string;
  url: string;
  created: string;
  updated: string;
}

/** Minimal seam over the Jira REST calls the connector needs. */
export interface JiraClient {
  getSelfAccountId(): Promise<string>;
  browseUrl(issueKey: string): string;
  addComment(issueKey: string, body: string): Promise<void>;
  listTransitions(issueKey: string): Promise<Array<{ id: string; name: string }>>;
  transition(issueKey: string, transitionId: string): Promise<void>;
  searchIssues(jql: string): Promise<JiraIssue[]>;
}

/** Best-effort ADF (Atlassian Document Format) to plain text. */
export function adfToText(node: unknown): string {
  if (node === null || node === undefined) return "";
  if (typeof node === "string") return node;
  if (Array.isArray(node)) return node.map(adfToText).join("");
  if (typeof node === "object") {
    const record = node as { type?: unknown; text?: unknown; content?: unknown };
    const own = typeof record.text === "string" ? record.text : "";
    const children = Array.isArray(record.content) ? record.content.map(adfToText).join("") : "";
    const isBlock = record.type === "paragraph" || record.type === "heading";
    return own + children + (isBlock ? "\n" : "");
  }
  return "";
}

function adfParagraph(text: string): unknown {
  return {
    type: "doc",
    version: 1,
    content: [{ type: "paragraph", content: [{ type: "text", text }] }],
  };
}

interface RawIssue {
  key: string;
  fields?: {
    project?: { key?: string };
    summary?: string;
    description?: unknown;
    labels?: string[];
    assignee?: { accountId?: string } | null;
    creator?: { accountId?: string };
    created?: string;
    updated?: string;
  };
}

export class RestJiraClient implements JiraClient {
  private readonly baseUrl: string;
  private readonly authHeader: string;

  constructor(options: { baseUrl: string; email: string; apiToken: string }) {
    this.baseUrl = options.baseUrl.replace(/\/+$/, "");
    const credentials = Buffer.from(`${options.email}:${options.apiToken}`).toString("base64");
    this.authHeader = `Basic ${credentials}`;
  }

  private async api<T>(path: string, init?: RequestInit): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      ...init,
      headers: {
        Authorization: this.authHeader,
        "Content-Type": "application/json",
        ...(init?.headers ?? {}),
      },
    });
    if (!res.ok) {
      const detail = await res.text().catch(() => "");
      throw new Error(`Jira API ${path} failed: ${res.status} ${detail.slice(0, 200)}`);
    }
    if (res.status === 204) return undefined as T;
    return (await res.json()) as T;
  }

  async getSelfAccountId(): Promise<string> {
    const data = await this.api<{ accountId: string }>("/rest/api/3/myself");
    return data.accountId;
  }

  browseUrl(issueKey: string): string {
    return `${this.baseUrl}/browse/${issueKey}`;
  }

  async addComment(issueKey: string, body: string): Promise<void> {
    await this.api(`/rest/api/3/issue/${issueKey}/comment`, {
      method: "POST",
      body: JSON.stringify({ body: adfParagraph(body) }),
    });
  }

  async listTransitions(issueKey: string): Promise<Array<{ id: string; name: string }>> {
    const data = await this.api<{ transitions?: Array<{ id: string; name: string }> }>(
      `/rest/api/3/issue/${issueKey}/transitions`,
    );
    return (data.transitions ?? []).map((t) => ({ id: t.id, name: t.name }));
  }

  async transition(issueKey: string, transitionId: string): Promise<void> {
    await this.api(`/rest/api/3/issue/${issueKey}/transitions`, {
      method: "POST",
      body: JSON.stringify({ transition: { id: transitionId } }),
    });
  }

  async searchIssues(jql: string): Promise<JiraIssue[]> {
    const params = new URLSearchParams({
      jql,
      maxResults: "100",
      fields: "summary,description,labels,assignee,creator,created,updated,project",
    });
    const data = await this.api<{ issues?: RawIssue[] }>(`/rest/api/3/search?${params.toString()}`);
    return (data.issues ?? []).map((issue) => this.normalizeIssue(issue));
  }

  private normalizeIssue(raw: RawIssue): JiraIssue {
    const fields = raw.fields ?? {};
    return {
      key: raw.key,
      projectKey: fields.project?.key ?? "",
      summary: fields.summary ?? "",
      descriptionText: adfToText(fields.description),
      creatorAccountId: fields.creator?.accountId ?? "",
      labels: fields.labels ?? [],
      assigneeAccountId: fields.assignee?.accountId,
      url: this.browseUrl(raw.key),
      created: fields.created ?? "",
      updated: fields.updated ?? "",
    };
  }
}
