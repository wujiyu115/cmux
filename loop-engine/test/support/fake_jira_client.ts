import type { JiraClient, JiraIssue } from "../../plugins/jira/client";

export class FakeJiraClient implements JiraClient {
  readonly comments: Array<{ issueKey: string; body: string }> = [];
  readonly transitionCalls: Array<{ issueKey: string; transitionId: string }> = [];
  transitionsByIssue: Record<string, Array<{ id: string; name: string }>> = {};
  searchJqls: string[] = [];
  searchResults: JiraIssue[] = [];
  accountId = "jira-bot";
  selfRequests = 0;

  async getSelfAccountId(): Promise<string> {
    this.selfRequests += 1;
    return this.accountId;
  }

  browseUrl(issueKey: string): string {
    return `https://x.atlassian.net/browse/${issueKey}`;
  }

  async addComment(issueKey: string, body: string): Promise<void> {
    this.comments.push({ issueKey, body });
  }

  async listTransitions(issueKey: string): Promise<Array<{ id: string; name: string }>> {
    return this.transitionsByIssue[issueKey] ?? [];
  }

  async transition(issueKey: string, transitionId: string): Promise<void> {
    this.transitionCalls.push({ issueKey, transitionId });
  }

  async searchIssues(jql: string): Promise<JiraIssue[]> {
    this.searchJqls.push(jql);
    return this.searchResults;
  }
}
