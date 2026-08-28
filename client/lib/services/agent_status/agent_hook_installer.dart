import 'dart:convert';
import 'dart:io';

import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import '../io/wsl_filesystem.dart';

/// Launch env keys stamped per-pane so the shared global hook can attribute a
/// report to the right seat. [agentStatusUrlEnvKey] lives in
/// `member_agent_status_endpoint.dart`; these two are the identity companions.
const agentStatusSessionEnvKey = 'TEAMPILOT_SESSION';
const agentStatusMemberEnvKey = 'TEAMPILOT_MEMBER';

/// Fixed file name of the managed forwarder, used both to build the script
/// path and to recognise our own hook groups. The name is historical — it
/// predates the Qoder/Codex targets, which share this one script — and MUST
/// stay `claude-hook.sh`: [AgentHookInstaller._groupIsManaged] recognises
/// every deployed generation of our entries by it.
const agentHookScriptFileName = 'claude-hook.sh';

/// Windows cmd forwarder for CLIs that execute Windows hook commands through
/// `cmd.exe` (Codex `commandWindows`). Same contract as the sh script.
const codexHookCmdFileName = 'codex-hook.cmd';

/// Agent CLIs the installer manages hooks for.
///
/// All three report Claude-Code-shaped payloads on stdin (`hook_event_name`,
/// `tool_name`, `is_interrupt`, …), so [AgentStatusNormalizer] decodes them
/// through a single Claude-family path — no per-target normalization.
enum AgentHookTarget { claude, qoder, codex }

/// One hook event the installer manages in the target CLI's settings file.
///
/// Tool-scoped events (`PreToolUse`/`PostToolUse`) carry a matcher where the
/// CLI supports one; lifecycle events (`Stop`, `PermissionRequest`, …) omit it.
class _ManagedHookEvent {
  const _ManagedHookEvent(this.name, {this.toolMatcher});

  final String name;

  /// Wildcard matcher for tool-scoped events; null for lifecycle events.
  final String? toolMatcher;
}

/// Events registered so every notify-worthy edge reaches the gateway, plus the
/// working-transition events (`UserPromptSubmit`/`PreToolUse`/`PostToolUse`) so
/// each turn's `Stop` is a fresh rising edge rather than a repeat of `done`.
const _managedEvents = <_ManagedHookEvent>[
  _ManagedHookEvent('UserPromptSubmit'),
  _ManagedHookEvent('PreToolUse', toolMatcher: '*'),
  _ManagedHookEvent('PostToolUse', toolMatcher: '*'),
  _ManagedHookEvent('PermissionRequest'),
  _ManagedHookEvent('Stop'),
  _ManagedHookEvent('StopFailure'),
];

/// Installs a single shared agent hook that forwards CLI lifecycle events to
/// the in-app agent-status gateway.
///
/// Design (mirrors Orca):
/// - **One forwarder script per machine** in that machine's app-data
///   `agent-hooks/`, shared by every pane AND every [AgentHookTarget] on it.
///   Seat identity is NOT baked into the command — it is read at run time from
///   the PTY env (`TEAMPILOT_AGENT_STATUS_URL` / `_SESSION` / `_MEMBER`,
///   stamped at connect). Env-absent → the script drains stdin and exits 0, so
///   a plain `claude` / `qoder` / `codex` run outside TeamPilot is untouched.
/// - **Additive merge** into each CLI's own settings file — Claude
///   `~/.claude/settings.json`, Qoder `~/.qoder/settings.json`, Codex
///   `~/.codex/hooks.json` — respecting `CLAUDE_CONFIG_DIR` / `CODEX_HOME`. A
///   reinstall strips only our groups and re-appends, leaving the user's own
///   hooks (claude-toast, Orca, …) in place. Atomic temp+rename write,
///   pristine `.bak` kept on first touch.
/// - **Per-target entry shape**: Claude and Qoder run hooks through a POSIX
///   shell (even on Windows — Git Bash), so their command is `sh "<script>"`
///   with wildcard matchers. Codex additionally reads `commandWindows` and runs
///   it through `cmd.exe`, so that key points at a generated
///   `codex-hook.cmd` twin; Codex matchers are regexes, so tool events omit the
///   matcher entirely.
///
/// A WSL distro is a separate machine for this purpose: a CLI running inside
/// it reads the distro's own settings files and cannot execute a Windows
/// script path, so it gets its own installation via [forWslDistro]. All IO
/// goes through [Filesystem] so the distro variant can write through
/// `wsl.exe`.
class AgentHookInstaller {
  AgentHookInstaller({
    required this.target,
    required this.scriptPath,
    required this.settingsPath,
    this.windowsScriptPath,
    Filesystem? filesystem,
    String? scriptBody,
  }) : fs = filesystem ?? LocalFilesystem(),
       scriptBody = AgentHookInstaller.normalizeScriptEndings(
         scriptBody ?? agentHookHostScriptBody,
       );

  /// The CLI whose settings file this installer merges into.
  final AgentHookTarget target;

  /// Filesystem the files are written through. Local for the host, a
  /// [WslFilesystem] for a distro.
  final Filesystem fs;

  /// Absolute path of the sh forwarder (`…/agent-hooks/claude-hook.sh`).
  final String scriptPath;

  /// Absolute path of the CLI's settings file to merge into.
  final String settingsPath;

  /// Absolute path of the Windows cmd forwarder
  /// (`…/agent-hooks/codex-hook.cmd`). Null when the install never runs under
  /// `cmd.exe` — Claude/Qoder always, Codex inside a distro.
  final String? windowsScriptPath;

  /// Body written to [scriptPath] — differs per machine because reaching the
  /// gateway from inside WSL needs Windows `curl.exe`.
  final String scriptBody;

  /// Forces LF endings on the emitted sh script.
  ///
  /// The bodies below are Dart string literals, so with `core.autocrlf=true`
  /// (this repo's checkout on Windows) their newlines ARE `\r\n`. That breaks
  /// the script in two ways under `sh` — and `/bin/sh` is `dash` in a typical
  /// distro, which is stricter than bash:
  ///   * `curl -sS \` + CR: the backslash escapes the CR, so `\r` becomes an
  ///     extra argument and every following `-H …` line is parsed as its own
  ///     command (`-H: command not found`);
  ///   * `then\r` / `fi\r` stop being reserved words.
  /// Normalising at write time keeps the output correct no matter how the Dart
  /// source was checked out.
  static String normalizeScriptEndings(String body) =>
      body.replaceAll('\r\n', '\n');

  /// Forces CRLF endings on the emitted `.cmd` script — the cmd.exe batch
  /// convention; lone LF lines can bleed into parsed arguments.
  static String normalizeCmdScriptEndings(String body) =>
      body.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');

  /// Installer for the machine the app itself runs on.
  ///
  /// [hostAppDataRoot] must be the *host* app-data dir — pass
  /// `AppPathsBootstrapper.current.basePath`, NOT `AppStorage.appDataRoot`:
  /// with a WSL home target the latter is already an in-distro POSIX path, and
  /// writing it through the local filesystem would create `/home/<u>/…` on the
  /// Windows drive.
  static AgentHookInstaller? forHost({
    required AgentHookTarget target,
    required String hostAppDataRoot,
    Filesystem? filesystem,
  }) {
    if (hostAppDataRoot.trim().isEmpty) return null;
    final settingsPath = switch (target) {
      AgentHookTarget.claude => _joinOrNull(
        resolveClaudeConfigDir(),
        'settings.json',
      ),
      AgentHookTarget.qoder => _joinOrNull(_qoderHostDir(), 'settings.json'),
      AgentHookTarget.codex => _joinOrNull(_codexHomeDir(), 'hooks.json'),
    };
    if (settingsPath == null) return null;
    final scriptDir = _join(hostAppDataRoot, 'agent-hooks');
    return AgentHookInstaller(
      target: target,
      scriptPath: _join(scriptDir, agentHookScriptFileName),
      windowsScriptPath:
          target == AgentHookTarget.codex && Platform.isWindows
          ? _join(scriptDir, codexHookCmdFileName)
          : null,
      settingsPath: settingsPath,
      filesystem: filesystem,
      scriptBody: agentHookHostScriptBody,
    );
  }

  /// Installer targeting a WSL distro's own CLI settings files.
  ///
  /// [distroHome] and [distroAppDataRoot] are in-distro POSIX paths (see
  /// `RuntimeContextRegistry.forTarget`). Writes go through `wsl.exe`.
  static AgentHookInstaller forWslDistro({
    required AgentHookTarget target,
    required String distro,
    required String distroHome,
    required String distroAppDataRoot,
    Filesystem? filesystem,
  }) {
    final settingsPath = switch (target) {
      AgentHookTarget.claude => '$distroHome/.claude/settings.json',
      AgentHookTarget.qoder => '$distroHome/.qoder/settings.json',
      AgentHookTarget.codex => '$distroHome/.codex/hooks.json',
    };
    return AgentHookInstaller(
      target: target,
      scriptPath: '$distroAppDataRoot/agent-hooks/$agentHookScriptFileName',
      settingsPath: settingsPath,
      filesystem: filesystem ?? WslFilesystem(distro: distro),
      scriptBody: agentHookWslScriptBody,
    );
  }

  /// `CLAUDE_CONFIG_DIR` if set, else `<home>/.claude`; null when no home.
  static String? resolveClaudeConfigDir() {
    final override = Platform.environment['CLAUDE_CONFIG_DIR']?.trim();
    if (override != null && override.isNotEmpty) return override;
    final home = _homeDir();
    return home == null ? null : _join(home, '.claude');
  }

  /// `CODEX_HOME` if set, else `<home>/.codex`; null when no home.
  static String? _codexHomeDir() {
    final override = Platform.environment['CODEX_HOME']?.trim();
    if (override != null && override.isNotEmpty) return override;
    final home = _homeDir();
    return home == null ? null : _join(home, '.codex');
  }

  /// `<home>/.qoder`; null when no home.
  static String? _qoderHostDir() {
    final home = _homeDir();
    return home == null ? null : _join(home, '.qoder');
  }

  static String? _homeDir() {
    final home =
        Platform.environment['HOME']?.trim() ??
        Platform.environment['USERPROFILE']?.trim();
    return (home == null || home.isEmpty) ? null : home;
  }

  static String? _joinOrNull(String? dir, String child) =>
      (dir == null || dir.trim().isEmpty) ? null : _join(dir, child);

  /// Command string written into every managed hook entry. Runs the forwarder
  /// through `sh`; forward-slashed + quoted so Git Bash accepts the Windows path.
  String get hookCommand => 'sh "${scriptPath.replaceAll('\\', '/')}"';

  /// Idempotent: (re)writes the forwarder script(s) and merges the managed
  /// hook groups into the CLI settings. Best-effort — logs and swallows
  /// failures so a bootstrap can never be blocked by a missing/locked settings
  /// file.
  Future<void> install() async {
    try {
      await _writeFile(scriptPath, scriptBody);
      final cmdPath = windowsScriptPath;
      if (cmdPath != null) {
        await _writeFile(cmdPath, normalizeCmdScriptEndings(codexHookCmdBody));
      }
      await _mergeSettings();
    } catch (e, st) {
      appLogger.w(
        '[agent-status] ${target.name} hook install failed: $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _writeFile(String path, String body) async {
    await fs.ensureDir(fs.pathContext.dirname(path));
    if (await fs.readString(path) == body) return;
    await fs.writeString(path, body);
  }

  Future<void> _mergeSettings() async {
    Map<String, Object?> root = {};
    final text = await fs.readString(settingsPath);
    if (text != null) {
      if (text.trim().isNotEmpty) {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          root = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      }
      // Keep a single pristine backup — only if none exists yet, so a reinstall
      // never overwrites the original with an already-merged copy.
      final backupPath = '$settingsPath.bak';
      if (!(await fs.stat(backupPath)).exists) {
        await fs.writeString(backupPath, text);
      }
    } else {
      await fs.ensureDir(fs.pathContext.dirname(settingsPath));
    }

    final hooks = <String, Object?>{};
    final existing = root['hooks'];
    if (existing is Map) {
      existing.forEach((k, v) => hooks[k.toString()] = v);
    }

    for (final event in _eventsFor(target)) {
      final groups = <Object?>[
        ...(hooks[event.name] is List
            ? (hooks[event.name] as List)
            : const <Object?>[]),
      ];
      // Strip only our own prior managed groups; leave user groups untouched.
      groups.removeWhere(_groupIsManaged);
      groups.add(_buildGroup(event));
      hooks[event.name] = groups;
    }
    root['hooks'] = hooks;

    await fs.atomicWrite(
      settingsPath,
      const JsonEncoder.withIndent('  ').convert(root),
    );
  }

  /// Codex has no `StopFailure` event (its event set otherwise maps 1:1).
  static List<_ManagedHookEvent> _eventsFor(AgentHookTarget target) =>
      switch (target) {
        AgentHookTarget.claude || AgentHookTarget.qoder => _managedEvents,
        AgentHookTarget.codex => _managedEvents
            .where((event) => event.name != 'StopFailure')
            .toList(),
      };

  Map<String, Object?> _buildGroup(_ManagedHookEvent event) {
    final group = <String, Object?>{
      'hooks': [_buildEntry()],
    };
    // Codex matchers are regexes — a bare `*` would be invalid, so tool events
    // there omit the matcher and simply match every tool.
    if (event.toolMatcher != null && target != AgentHookTarget.codex) {
      group['matcher'] = event.toolMatcher;
    }
    return group;
  }

  Map<String, Object?> _buildEntry() {
    final entry = <String, Object?>{
      'type': 'command',
      'command': hookCommand,
      'timeout': 5,
    };
    final cmdPath = windowsScriptPath;
    if (cmdPath != null) {
      entry['commandWindows'] = '"$cmdPath"';
    }
    return entry;
  }

  /// A hook group is ours iff any of its commands references the managed sh
  /// script *file name*.
  ///
  /// Deliberately not the full [scriptPath]: the app-data root moves (host vs
  /// distro, and a changed home target rewrites it), and a path-exact needle
  /// would fail to recognise entries an earlier install wrote — leaving stale
  /// duplicates to pile up in the settings file forever. Matching the fixed
  /// file name recognises every generation of our own entries. An explicit
  /// marker key would not help here: the entries that need cleaning up predate
  /// it.
  ///
  /// The needle is the sh script name only — never `codex-hook.cmd`, which
  /// Orca's own Codex wiring also uses; recognising it would strip the user's
  /// Orca entries. Our Codex entries always carry the sh command in `command`,
  /// so they stay recognisable through it.
  bool _groupIsManaged(Object? group) {
    if (group is! Map) return false;
    final entries = group['hooks'];
    if (entries is! List) return false;
    for (final entry in entries) {
      if (entry is! Map) continue;
      for (final command in [entry['command'], entry['commandWindows']]) {
        if (command is String &&
            command.replaceAll('\\', '/').contains(agentHookScriptFileName)) {
          return true;
        }
      }
    }
    return false;
  }

  static String _join(String a, String b) {
    final sep = a.contains('\\') && !a.contains('/') ? '\\' : '/';
    final trimmed = a.endsWith('/') || a.endsWith('\\')
        ? a.substring(0, a.length - 1)
        : a;
    return '$trimmed$sep$b';
  }
}

/// Shared prologue: drain stdin and no-op unless the pane was stamped with
/// TeamPilot seat identity.
const _scriptPrologue = '''#!/bin/sh
# TeamPilot agent-status forwarder (managed — do not edit).
# Identity comes from the PTY env stamped at connect; absent env => no-op.
if [ -z "\$TEAMPILOT_AGENT_STATUS_URL" ] || [ -z "\$TEAMPILOT_SESSION" ] || [ -z "\$TEAMPILOT_MEMBER" ]; then
  cat >/dev/null 2>&1
  exit 0
fi
''';

/// Shared request: stream the raw hook JSON to the gateway with short timeouts
/// and `|| true` so a slow/unreachable gateway never stalls or fails the turn.
const _scriptRequest = ''' -sS --connect-timeout 1 --max-time 3 \\
  -H "X-Session: \$TEAMPILOT_SESSION" \\
  -H "X-Member: \$TEAMPILOT_MEMBER" \\
  -H "Content-Type: application/json" \\
  --data-binary @- \\
  "\$TEAMPILOT_AGENT_STATUS_URL" >/dev/null 2>&1 || true
exit 0
''';

/// Forwarder for the machine the app runs on — plain `curl` on the same host as
/// the gateway.
const agentHookHostScriptBody = '$_scriptPrologue'
    'curl$_scriptRequest';

/// Forwarder for inside a WSL distro.
///
/// The gateway listens on the Windows loopback, which a WSL2 NAT network cannot
/// reach — the distro's own `127.0.0.1` is a different stack, and the host is
/// not listening on the vEthernet address. Windows `curl.exe`, invoked through
/// WSL interop, performs the request on the *host* network stack and reaches it.
/// This keeps the gateway bound to loopback only; exposing it on `0.0.0.0` would
/// publish an unauthenticated endpoint to the whole LAN.
///
/// Falls back to the distro's `curl` when interop is disabled or the Windows
/// path is absent — status then cannot reach the gateway, but the hook stays
/// silent instead of erroring on every event.
const agentHookWslScriptBody =
    '$_scriptPrologue'
    'CURL=/mnt/c/Windows/System32/curl.exe\n'
    '[ -x "\$CURL" ] || CURL=curl\n'
    '"\$CURL"$_scriptRequest';

/// Windows cmd twin of the sh forwarder, run by Codex's `commandWindows` path.
///
/// Same contract: unstamped panes drain stdin and exit 0 so a plain `codex`
/// run outside TeamPilot is untouched. `curl.exe` is invoked by absolute path —
/// hook commands run outside our shell environment assumptions, and `curl`
/// could resolve to an alias or a missing binary. The script always exits 0:
/// codex surfaces failing hooks to the user, and a stopped TeamPilot gateway is
/// not their problem.
const codexHookCmdBody = r'''@echo off
setlocal
if "%TEAMPILOT_AGENT_STATUS_URL%"=="" goto teampilot_drain
if "%TEAMPILOT_SESSION%"=="" goto teampilot_drain
if "%TEAMPILOT_MEMBER%"=="" goto teampilot_drain
"%SystemRoot%\System32\curl.exe" -sS --connect-timeout 1 --max-time 3 -H "X-Session: %TEAMPILOT_SESSION%" -H "X-Member: %TEAMPILOT_MEMBER%" -H "Content-Type: application/json" --data-binary @- "%TEAMPILOT_AGENT_STATUS_URL%" >nul 2>&1
exit /b 0
:teampilot_drain
"%SystemRoot%\System32\more.com" >nul 2>&1
exit /b 0
''';
