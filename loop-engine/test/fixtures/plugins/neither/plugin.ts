import { definePlugin } from "../../../../src/plugins/sdk";

// Implements neither intake nor reporter: the loader must reject it.
export default definePlugin({ id: "neither", version: "0.1.0" }, () => ({ id: "neither" }));
