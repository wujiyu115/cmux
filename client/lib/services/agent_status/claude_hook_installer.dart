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

/// Fixed file name of the managed forwarder, used both to build the script path
/// and to recognise our own hook groups. See [ClaudeHookInstaller._groupIsManaged].
const claudeHookScriptFileName = 'claude-hook.sh';

/// One Claude hook event the installer manages in the user's `settings.json`.
///
/// Tool-scoped events (`PreToolUse`/`PostToolUse`) carry a `matcher`; lifecycle
/// events (`Stop`, `PermissionRequest`, …) omit it.
class _ManagedHookEvent {
  const _ManagedHookEvent(this.name, {this.matcher});

  final String name;
  final String? matcher;

  Map<String, Object?> buildGroup(String command) => {
    if (matcher != null) 'matcher': matcher,
    'hooks': [
      {'type': 'command', 'command': command, 'timeout': 5},
    ],
  };
}

/// Events registered so every notify-worthy edge reaches the gateway, plus the
/// working-transition events (`UserPromptSubmit`/`PreToolUse`/`PostToolUse`) so
/// each turn's `Stop` is a fresh rising edge rather than a repeat of `done`.
///
/// Mirrors Orca's managed set; the per-CLI meaning is decoded downstream by
/// `AgentStatusNormalizer` — this installer stays CLI-shape-agnostic.
const _managedEvents = <_ManagedHookEvent>[
  _ManagedHookEvent('UserPromptSubmit'),
  _ManagedHookEvent('PreToolUse', matcher: '*'),
  _ManagedHookEvent('PostToolUse', matcher: '*'),
  _ManagedHookEvent('PermissionRequest'),
  _ManagedHookEvent('Stop'),
  _ManagedHookEvent('StopFailure'),
];

/// Installs a single shared Claude hook that forwards lifecycle events to the
/// in-app agent-status gateway.
///
/// Design (mirrors Orca):
/// - **One forwarder script per machine** in that machine's app-data
///   `agent-hooks/`, shared by every pane on it. Seat identity is NOT baked into
///   the command — it is read at run time from the PTY env
///   (`TEAMPILOT_AGENT_STATUS_URL` / `_SESSION` / `_MEMBER`, stamped at
///   connect). Env-absent → the script drains stdin and exits 0, so a plain
///   `claude` run outside TeamPilot is untouched.
/// - **Additive merge** into the user-level `~/.claude/settings.json` (respecting
///   `CLAUDE_CONFIG_DIR`). A reinstall strips only our groups and re-appends,
///   leaving the user's own hooks (claude-toast / agent-deck / …) in place.
///   Atomic temp+rename write, pristine `.bak` kept on first touch.
///
/// A WSL distro is a separate machine for this purpose: `claude` running inside
/// it reads the distro's own `settings.json` and cannot execute a Windows script
/// path, so it gets its own installation via [forWslDistro]. All IO goes through
/// [Filesystem] so the distro variant can write through `wsl.exe`.
///
/// The command runs the script through `sh` so no executable bit is required and
/// the same entry works on POSIX and on Windows (Claude Code hooks run under a
/// POSIX shell — Git Bash — where `sh` and `curl` are available).
class ClaudeHookInstaller {
  ClaudeHookInstaller({
    required this.scriptPath,
    required this.settingsPath,
    Filesystem? filesystem,
    String? scriptBody,
  }) : fs = filesystem ?? LocalFilesystem(),
       scriptBody = normalizeScriptEndings(
         scriptBody ?? claudeHookHostScriptBody,
       );

  /// Forces LF endings on the emitted script.
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

  /// Filesystem the two files are written through. Local for the host, a
  /// [WslFilesystem] for a distro.
  final Filesystem fs;

  /// Absolute path of the forwarder script (`…/agent-hooks/claude-hook.sh`).
  final String scriptPath;

  /// Absolute path of the user Claude `settings.json` to merge into.
  final String settingsPath;

  /// Body written to [scriptPath] — differs per machine because reaching the
  /// gateway from inside WSL needs Windows `curl.exe`.
  final String scriptBody;

  /// Installer for the machine the app itself runs on.
  ///
  /// [hostAppDataRoot] must be the *host* app-data dir — pass
  /// `AppPathsBootstrapper.current.basePath`, NOT `AppStorage.appDataRoot`:
  /// with a WSL home target the latter is already an in-distro POSIX path, and
  /// writing it through the local filesystem would create `/home/<u>/…` on the
  /// Windows drive.
  static ClaudeHookInstaller? forHost({
    required String hostAppDataRoot,
    Filesystem? filesystem,
  }) {
    final configDir = resolveClaudeConfigDir();
    if (configDir == null || hostAppDataRoot.trim().isEmpty) return null;
    final scriptDir = _join(hostAppDataRoot, 'agent-hooks');
    return ClaudeHookInstaller(
      scriptPath: _join(scriptDir, claudeHookScriptFileName),
      settingsPath: _join(configDir, 'settings.json'),
      filesystem: filesystem,
      scriptBody: claudeHookHostScriptBody,
    );
  }

  /// Installer targeting a WSL distro's own `~/.claude/settings.json`.
  ///
  /// [distroHome] and [distroAppDataRoot] are in-distro POSIX paths (see
  /// `RuntimeContextRegistry.forTarget`). Writes go through `wsl.exe`.
  static ClaudeHookInstaller forWslDistro({
    required String distro,
    required String distroHome,
    required String distroAppDataRoot,
    Filesystem? filesystem,
  }) => ClaudeHookInstaller(
    scriptPath: '$distroAppDataRoot/agent-hooks/$claudeHookScriptFileName',
    settingsPath: '$distroHome/.claude/settings.json',
    filesystem: filesystem ?? WslFilesystem(distro: distro),
    scriptBody: claudeHookWslScriptBody,
  );

  /// `CLAUDE_CONFIG_DIR` if set, else `<home>/.claude`; null when no home.
  static String? resolveClaudeConfigDir() {
    final override = Platform.environment['CLAUDE_CONFIG_DIR']?.trim();
    if (override != null && override.isNotEmpty) return override;
    final home =
        Platform.environment['HOME']?.trim() ??
        Platform.environment['USERPROFILE']?.trim();
    if (home == null || home.isEmpty) return null;
    return _join(home, '.claude');
  }

  /// Command string written into every managed hook entry. Runs the forwarder
  /// through `sh`; forward-slashed + quoted so Git Bash accepts the Windows path.
  String get hookCommand => 'sh "${scriptPath.replaceAll('\\', '/')}"';

  /// Idempotent: (re)writes the forwarder script and merges the managed hook
  /// groups into the user settings. Best-effort — logs and swallows failures so
  /// a bootstrap can never be blocked by a missing/locked settings file.
  Future<void> install() async {
    try {
      await _writeScript();
      await _mergeSettings();
    } catch (e, st) {
      appLogger.w(
        '[agent-status] Claude hook install failed: $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _writeScript() async {
    await fs.ensureDir(fs.pathContext.dirname(scriptPath));
    if (await fs.readString(scriptPath) == scriptBody) return;
    await fs.writeString(scriptPath, scriptBody);
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

    for (final event in _managedEvents) {
      final groups = <Object?>[
        ...(hooks[event.name] is List
            ? (hooks[event.name] as List)
            : const <Object?>[]),
      ];
      // Strip only our own prior managed groups; leave user groups untouched.
      groups.removeWhere(_groupIsManaged);
      groups.add(event.buildGroup(hookCommand));
      hooks[event.name] = groups;
    }
    root['hooks'] = hooks;

    await fs.atomicWrite(
      settingsPath,
      const JsonEncoder.withIndent('  ').convert(root),
    );
  }

  /// A hook group is ours iff any of its commands references the managed script
  /// *file name*.
  ///
  /// Deliberately not the full [scriptPath]: the app-data root moves (host vs
  /// distro, and a changed home target rewrites it), and a path-exact needle
  /// would fail to recognise entries an earlier install wrote — leaving stale
  /// duplicates to pile up in `settings.json` forever. Matching the fixed file
  /// name recognises every generation of our own entries. An explicit marker key
  /// would not help here: the entries that need cleaning up predate it.
  bool _groupIsManaged(Object? group) {
    if (group is! Map) return false;
    final entries = group['hooks'];
    if (entries is! List) return false;
    for (final entry in entries) {
      if (entry is Map) {
        final command = entry['command'];
        if (command is String &&
            command.replaceAll('\\', '/').contains(claudeHookScriptFileName)) {
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
const claudeHookHostScriptBody = '$_scriptPrologue'
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
const claudeHookWslScriptBody =
    '$_scriptPrologue'
    'CURL=/mnt/c/Windows/System32/curl.exe\n'
    '[ -x "\$CURL" ] || CURL=curl\n'
    '"\$CURL"$_scriptRequest';
