import { definePlugin } from "../../../../src/plugins/sdk";

export default definePlugin({ id: "echo", name: "Echo", version: "0.1.0" }, () => ({
  id: "echo",
  intake: {
    handleWebhook: async () => [],
    selfIdentities: async () => [],
  },
}));
