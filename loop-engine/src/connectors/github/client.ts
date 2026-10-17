import { Octokit } from "octokit";

export interface CreatePullRequestParams {
  title: string;
  head: string;
  base: string;
  body: string;
}

/** Normalized GitHub search-issue item (pull requests excluded). */
export interface SearchIssueItem {
  number: number;
  title: string;
  body: string;
  htmlUrl: string;
  createdAt: string;
  updatedAt: string;
  authorLogin: string;
  labels: string[];
  assigneeLogin?: string;
}

export interface GitHubPullRequestState {
  state: "open" | "closed";
  merged: boolean;
}

/** Minimal seam over the GitHub REST calls the connector needs. */
export interface GitHubClient {
  addLabels(owner: string, repo: string, issueNumber: number, labels: string[]): Promise<void>;
  removeLabel(owner: string, repo: string, issueNumber: number, name: string): Promise<void>;
  createComment(owner: string, repo: string, issueNumber: number, body: string): Promise<void>;
  createPullRequest(owner: string, repo: string, params: CreatePullRequestParams): Promise<{ url: string }>;
  getPullRequest(owner: string, repo: string, number: number): Promise<GitHubPullRequestState>;
  getAuthenticatedLogin(): Promise<string>;
  searchIssues(query: string): Promise<SearchIssueItem[]>;
}

export class OctokitGitHubClient implements GitHubClient {
  private readonly octokit: Octokit;

  constructor(token: string) {
    this.octokit = new Octokit({ auth: token });
  }

  async addLabels(owner: string, repo: string, issueNumber: number, labels: string[]): Promise<void> {
    await this.octokit.rest.issues.addLabels({ owner, repo, issue_number: issueNumber, labels });
  }

  async removeLabel(owner: string, repo: string, issueNumber: number, name: string): Promise<void> {
    await this.octokit.rest.issues.removeLabel({ owner, repo, issue_number: issueNumber, name });
  }

  async createComment(owner: string, repo: string, issueNumber: number, body: string): Promise<void> {
    await this.octokit.rest.issues.createComment({ owner, repo, issue_number: issueNumber, body });
  }

  async createPullRequest(owner: string, repo: string, params: CreatePullRequestParams): Promise<{ url: string }> {
    const res = await this.octokit.rest.pulls.create({ owner, repo, ...params });
    return { url: res.data.html_url };
  }

  async getPullRequest(owner: string, repo: string, number: number): Promise<GitHubPullRequestState> {
    const res = await this.octokit.rest.pulls.get({ owner, repo, pull_number: number });
    return { state: res.data.state, merged: res.data.merged };
  }

  async getAuthenticatedLogin(): Promise<string> {
    const res = await this.octokit.rest.users.getAuthenticated();
    return res.data.login;
  }

  async searchIssues(query: string): Promise<SearchIssueItem[]> {
    const res = await this.octokit.rest.search.issuesAndPullRequests({ q: query, per_page: 100 });
    return res.data.items
      .filter((item) => !("pull_request" in item) || item.pull_request === undefined)
      .map((item) => ({
        number: item.number,
        title: item.title,
        body: item.body ?? "",
        htmlUrl: item.html_url,
        createdAt: item.created_at,
        updatedAt: item.updated_at,
        authorLogin: item.user?.login ?? "",
        labels: (item.labels ?? [])
          .map((l) => (typeof l === "string" ? l : l.name ?? ""))
          .filter((name) => name !== ""),
        assigneeLogin: item.assignee?.login ?? undefined,
      }));
  }
}
