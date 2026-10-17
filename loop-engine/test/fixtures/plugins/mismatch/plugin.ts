import { definePlugin } from "../../../../src/plugins/sdk";

// Manifest id differs from the created connector id: the loader must reject it.
export default definePlugin({ id: "manifest-a", version: "0.1.0" }, () => ({
  id: "connector-b",
  intake: {
    handleWebhook: async () => [],
    selfIdentities: async () => [],
  },
}));
