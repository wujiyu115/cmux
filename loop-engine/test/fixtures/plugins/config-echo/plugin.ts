import { definePlugin } from "../../../../src/plugins/sdk";

export default definePlugin({ id: "config-echo", version: "0.1.0" }, (ctx) => ({
  id: "config-echo",
  intake: {
    handleWebhook: async () => [],
    selfIdentities: async () => (ctx.config["actors"] as string[] | undefined) ?? [],
  },
}));
