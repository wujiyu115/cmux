import { afterEach, describe, expect, it, vi } from "vitest";

import { RestJiraClient, adfToText } from "../../../plugins/jira/client";

function mockFetch(responses: Array<{ status?: number; body: unknown }>) {
  const calls: Array<{ url: string; method?: string; body?: string; auth?: string }> = [];
  const impl = async (url: string | URL, init?: RequestInit): Promise<Response> => {
    calls.push({
      url: String(url),
      method: init?.method,
      body: typeof init?.body === "string" ? init.body : undefined,
      auth: (init?.headers as Record<string, string> | undefined)?.Authorization,
    });
    const next = responses.shift() ?? { status: 200, body: {} };
    const status = next.status ?? 200;
    // 204 responses must not carry a body (undici rejects them).
    return new Response(status === 204 ? null : JSON.stringify(next.body), {
      status,
      headers: { "content-type": "application/json" },
    });
  };
  vi.stubGlobal("fetch", vi.fn(impl));
  return calls;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

function makeClient(): RestJiraClient {
  return new RestJiraClient({ baseUrl: "https://x.atlassian.net/", email: "e@x.com", apiToken: "tok" });
}

const rawIssue = {
  key: "PROJ-1",
  fields: {
    project: { key: "PROJ" },
    summary: "Fix login",
    description: { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "steps" }] }] },
    labels: ["bug"],
    assignee: { accountId: "acc-a" },
    creator: { accountId: "acc-c" },
    created: "2026-01-01T00:00:00Z",
    updated: "2026-01-02T00:00:00Z",
  },
};

describe("RestJiraClient", () => {
  it("sends basic auth and normalizes search results", async () => {
    const calls = mockFetch([{ body: { issues: [rawIssue] } }]);
    const client = makeClient();
    const issues = await client.searchIssues('project = "PROJ"');
    expect(calls[0]!.url).toContain("https://x.atlassian.net/rest/api/3/search?");
    expect(calls[0]!.url).toContain("jql=project+%3D+%22PROJ%22");
    const expectedAuth = `Basic ${Buffer.from("e@x.com:tok").toString("base64")}`;
    expect(calls[0]!.auth).toBe(expectedAuth);
    expect(issues).toEqual([
      {
        key: "PROJ-1",
        projectKey: "PROJ",
        summary: "Fix login",
        descriptionText: "steps\n",
        creatorAccountId: "acc-c",
        labels: ["bug"],
        assigneeAccountId: "acc-a",
        url: "https://x.atlassian.net/browse/PROJ-1",
        created: "2026-01-01T00:00:00Z",
        updated: "2026-01-02T00:00:00Z",
      },
    ]);
  });

  it("posts comments as ADF documents", async () => {
    const calls = mockFetch([{ status: 201, body: {} }]);
    const client = makeClient();
    await client.addComment("PROJ-1", "hello");
    expect(calls[0]!.url).toBe("https://x.atlassian.net/rest/api/3/issue/PROJ-1/comment");
    expect(calls[0]!.method).toBe("POST");
    expect(JSON.parse(calls[0]!.body!)).toEqual({
      body: {
        type: "doc",
        version: 1,
        content: [{ type: "paragraph", content: [{ type: "text", text: "hello" }] }],
      },
    });
  });

  it("lists and applies transitions", async () => {
    const calls = mockFetch([
      { body: { transitions: [{ id: "11", name: "In Progress" }] } },
      { status: 204, body: {} },
    ]);
    const client = makeClient();
    const transitions = await client.listTransitions("PROJ-1");
    expect(transitions).toEqual([{ id: "11", name: "In Progress" }]);
    await client.transition("PROJ-1", "11");
    expect(calls[1]!.method).toBe("POST");
    expect(JSON.parse(calls[1]!.body!)).toEqual({ transition: { id: "11" } });
  });

  it("surfaces API errors with status and body", async () => {
    mockFetch([{ status: 401, body: { errorMessages: ["Unauthorized"] } }]);
    const client = makeClient();
    await expect(client.getSelfAccountId()).rejects.toThrow(/401/);
  });
});

describe("adfToText", () => {
  it("flattens nested documents and keeps paragraph breaks", () => {
    const doc = {
      type: "doc",
      content: [
        { type: "paragraph", content: [{ type: "text", text: "first" }] },
        { type: "paragraph", content: [{ type: "text", text: "second" }] },
      ],
    };
    expect(adfToText(doc)).toBe("first\nsecond\n");
  });

  it("passes through plain strings and nulls", () => {
    expect(adfToText("plain")).toBe("plain");
    expect(adfToText(null)).toBe("");
  });
});
