import type {
  CreatePullRequestParams,
  GitHubClient,
  GitHubPullRequestState,
  SearchIssueItem,
} from "../../src/connectors/github/client";

export class FakeGitHubClient implements GitHubClient {
  readonly labelCalls: Array<{ owner: string; repo: string; number: number; labels: string[] }> = [];
  readonly removedLabels: Array<{ owner: string; repo: string; number: number; name: string }> = [];
  readonly comments: Array<{ owner: string; repo: string; number: number; body: string }> = [];
  readonly pullRequests: Array<{ owner: string; repo: string; params: CreatePullRequestParams }> = [];
  searchQueries: string[] = [];
  searchResults: SearchIssueItem[] = [];
  pullRequestStates: Record<string, GitHubPullRequestState> = {};
  loginRequests = 0;

  async addLabels(owner: string, repo: string, number: number, labels: string[]): Promise<void> {
    this.labelCalls.push({ owner, repo, number, labels });
  }

  async removeLabel(owner: string, repo: string, number: number, name: string): Promise<void> {
    this.removedLabels.push({ owner, repo, number, name });
  }

  async createComment(owner: string, repo: string, number: number, body: string): Promise<void> {
    this.comments.push({ owner, repo, number, body });
  }

  async createPullRequest(
    owner: string,
    repo: string,
    params: CreatePullRequestParams,
  ): Promise<{ url: string }> {
    this.pullRequests.push({ owner, repo, params });
    return { url: "https://github.com/owner/repo/pull/9" };
  }

  async getPullRequest(owner: string, repo: string, number: number): Promise<GitHubPullRequestState> {
    return this.pullRequestStates[`${owner}/${repo}#${number}`] ?? { state: "open", merged: false };
  }

  async getAuthenticatedLogin(): Promise<string> {
    this.loginRequests += 1;
    return "Loop-Bot";
  }

  async searchIssues(query: string): Promise<SearchIssueItem[]> {
    this.searchQueries.push(query);
    return this.searchResults;
  }
}
