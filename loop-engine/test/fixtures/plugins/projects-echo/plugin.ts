import { definePlugin } from "../../../../src/plugins/sdk";
import type { IntakeEvent } from "../../../../src/domain/events";

let seenProjects: Array<{ project: string }> = [];

export default definePlugin({ id: "projects-echo", name: "Projects Echo", version: "0.1.0" }, (ctx) => {
  seenProjects = ctx.projects;
  return {
    id: "projects-echo",
    intake: {
      handleWebhook: async (): Promise<IntakeEvent[]> => [],
      selfIdentities: async () => seenProjects.map((p) => p.project),
    },
  };
});
