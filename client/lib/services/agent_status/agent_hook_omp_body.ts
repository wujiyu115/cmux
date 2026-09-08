// TeamPilot agent-status forwarder for oh-my-pi (managed — do not edit).
// Reference copy of `agentHookOmpScriptBody` in agent_hook_installer.dart —
// omp discovers this module from ~/.omp/agent/hooks/pre/ and binds the default
// export's pi.on handlers to the runtime event bus. Seat identity comes from
// the PTY env stamped at connect; absent env => registers nothing, so a plain
// `omp` run outside TeamPilot is untouched.
const url = process.env.TEAMPILOT_AGENT_STATUS_URL;
const seatSession = process.env.TEAMPILOT_SESSION;
const seatMember = process.env.TEAMPILOT_MEMBER;

export default function (pi) {
	if (!url || !seatSession || !seatMember) return;

	// WSL2 NAT cannot reach the Windows loopback gateway. Windows curl.exe,
	// invoked through WSL interop, performs the request on the host network
	// stack — same trick as the sh forwarder in claude-hook.sh.
	let curl = null;
	try {
		const exe = "/mnt/c/Windows/System32/curl.exe";
		if (process.platform === "linux" && require("node:fs").existsSync(exe)) curl = exe;
	} catch {}

	const post = async (body) => {
		const payload = JSON.stringify(body);
		try {
			if (curl) {
				// Awaited: a fire-and-forget spawn dies with the omp process before
				// the request completes (seen with real omp).
				const p = Bun.spawn({
					cmd: [
						curl, "-sS", "--connect-timeout", "1", "--max-time", "3",
						"-H", `X-Session: ${seatSession}`,
						"-H", `X-Member: ${seatMember}`,
						"-H", "Content-Type: application/json",
						"--data-binary", payload, url,
					],
					stdout: "ignore",
					stderr: "ignore",
				});
				await p.exited;
			} else {
				await fetch(url, {
					method: "POST",
					headers: {
						"X-Session": seatSession,
						"X-Member": seatMember,
						"Content-Type": "application/json",
					},
					body: payload,
					signal: AbortSignal.timeout(3000),
				});
			}
		} catch {}
	};

	// omp event -> Claude-Code-shaped payload the TeamPilot normalizer reads.
	pi.on("agent_start", () => post({ hook_event_name: "UserPromptSubmit" }));
	pi.on("tool_call", (event) => post({
		hook_event_name: "PreToolUse",
		// omp's clarifying-question tool is `ask`; the normalizer only
		// recognizes the Claude name.
		tool_name: event?.toolName === "ask" ? "AskUserQuestion" : event?.toolName,
		tool_input: event?.input,
		tool_use_id: event?.toolCallId,
	}));
	pi.on("tool_result", (event) => post({
		hook_event_name: "PostToolUse",
		tool_name: event?.toolName,
		tool_input: event?.input,
		tool_use_id: event?.toolCallId,
	}));
	pi.on("tool_approval_requested", (event) => post({
		hook_event_name: "PermissionRequest",
		tool_name: event?.toolName,
		tool_use_id: event?.toolCallId,
	}));
	// Main-agent settle; subagents never fire session_stop.
	pi.on("session_stop", () => post({ hook_event_name: "Stop" }));
	// Interrupt coverage: an aborted turn settles without session_stop, but the
	// root agent_end still fires. willContinue marks a scheduled continuation,
	// and subagent bindings are recognized by their session file living inside
	// a parent artifacts dir (<parent>.jsonl -> <parent>/<child>.jsonl).
	pi.on("agent_end", (event, ctx) => {
		if (event?.willContinue) return;
		try {
			const file = ctx?.sessionManager?.getSessionFile?.();
			if (file && require("node:fs").existsSync(require("node:path").dirname(file) + ".jsonl")) return;
		} catch {}
		post({ hook_event_name: "Stop" });
	});
}
