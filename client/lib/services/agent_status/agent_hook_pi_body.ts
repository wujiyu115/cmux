// TeamPilot agent-status forwarder for raw pi (managed — do not edit).
// Reference copy of `agentHookPiScriptBody` in agent_hook_installer.dart —
// pi (badlogic/pi-mono) auto-discovers this module from
// ~/.pi/agent/extensions/ (or <PI_CODING_AGENT_DIR>/extensions/) and binds the
// default export's pi.on handlers (jiti — no build step). Seat identity comes
// from the PTY env stamped at connect; absent env => registers nothing, so a
// plain `pi` run outside TeamPilot is untouched.
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

	// Fire-and-forget: pi awaits handler returns, so post is sync and never
	// blocks the agent on status delivery. On WSL the curl.exe launch crosses
	// Win32 interop — bounded for HTTP by --max-time, but the launch itself can
	// stall for seconds under load, so it is detached + unref'd (orphans curl,
	// the request still lands after the CLI exits) and never awaited. Same
	// bridge as the Orca forwarder.
	const spawn = require("node:child_process").spawn;
	const post = (body) => {
		const payload = JSON.stringify(body);
		try {
			if (curl) {
				const child = spawn(curl, [
					"-sS", "--connect-timeout", "1", "--max-time", "3",
					"-H", `X-Session: ${seatSession}`,
					"-H", `X-Member: ${seatMember}`,
					"-H", "Content-Type: application/json",
					"--data-binary", payload, url,
				], { detached: true, stdio: "ignore" });
				child.on("error", () => {});
				child.unref();
			} else {
				fetch(url, {
					method: "POST",
					headers: {
						"X-Session": seatSession,
						"X-Member": seatMember,
						"Content-Type": "application/json",
					},
					body: payload,
					signal: AbortSignal.timeout(3000),
				}).catch(() => {});
			}
		} catch {}
	};

	// pi event -> Claude-Code-shaped payload the TeamPilot normalizer reads.
	// Raw pi has no omp-style session_stop and no approval event; agent_settled
	// is the sole terminal edge — retries, compaction, and queued continuations
	// are all exhausted by the time it fires.
	pi.on("agent_start", () => post({ hook_event_name: "UserPromptSubmit" }));
	pi.on("tool_call", (event) => post({
		hook_event_name: "PreToolUse",
		// Nested executeTool calls carry parentToolCallId; they forward too —
		// still activity in the same run, so the seat stays working.
		tool_name: event?.toolName,
		tool_input: event?.input,
		tool_use_id: event?.toolCallId,
	}));
	pi.on("tool_result", (event) => post({
		hook_event_name: "PostToolUse",
		tool_name: event?.toolName,
		tool_input: event?.input,
		tool_use_id: event?.toolCallId,
	}));
	// Escape-style cancels report `aborted`; the normalizer reads the Claude
	// Stop `is_interrupt` flag to mark the turn interrupted, not finished.
	pi.on("agent_settled", (event) => post({
		hook_event_name: "Stop",
		is_interrupt: event?.aborted === true,
	}));
}
