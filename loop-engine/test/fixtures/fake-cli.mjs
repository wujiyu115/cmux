// Fake agent CLI for tests: reads the prompt from stdin and prints a
// Claude-Code-shaped JSON result. Flags: --fail, --sleep=<ms>
import { readFileSync } from "node:fs";

const flags = process.argv.slice(2);

let stdin = "";
try {
  stdin = readFileSync(0, "utf8");
} catch {
  // stdin may already be closed
}

const sleepMs = Number(flags.find((f) => f.startsWith("--sleep="))?.slice("--sleep=".length) ?? 0);
if (sleepMs > 0) {
  await new Promise((resolve) => setTimeout(resolve, sleepMs));
}

if (flags.includes("--fail")) {
  console.error("fake cli failure");
  process.exit(1);
}

const isPlanner = stdin.includes("Break the ticket down");
const result = isPlanner
  ? 'Here is the plan.\n```json\n{"todos": [{"text": "repro the bug", "status": "pending"}, {"text": "fix it", "status": "pending"}]}\n```'
  : "Worked through the todos and committed everything.";

process.stdout.write(
  JSON.stringify({
    type: "result",
    subtype: "success",
    is_error: false,
    result,
    usage: { input_tokens: 12, output_tokens: 34 },
  }),
);
