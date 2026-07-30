import 'dart:convert';
import 'dart:io';

import '../../utils/logging/logger.dart';

/// Launch env keys stamped per-pane so the shared global hook can attribute a
/// report to the right seat. [agentStatusUrlEnvKey] lives in
/// `member_agent_status_endpoint.dart`; these two are the identity companions.
const agentStatusSessionEnvKey = 'TEAMPILOT_SESSION';
const agentStatusMemberEnvKey = 'TEAMPILOT_MEMBER';

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
/// - **One global forwarder script** in app-data `agent-hooks/`, shared by every
///   pane. Seat identity is NOT baked into the command — it is read at run time
///   from the PTY env (`TEAMPILOT_AGENT_STATUS_URL` / `_SESSION` / `_MEMBER`,
///   stamped at connect). Env-absent → the script drains stdin and exits 0, so a
///   plain `claude` run outside TeamPilot is untouched.
/// - **Additive merge** into the user-level `~/.claude/settings.json` (respecting
///   `CLAUDE_CONFIG_DIR`). Our groups are tagged by the script path substring in
///   their command; a reinstall strips only those and re-appends, leaving the
///   user's own hooks (claude-toast / agent-deck / …) in place. Atomic
///   temp+rename write, pristine `.bak` kept on first touch.
///
/// The command runs the script through `sh` so no executable bit is required and
/// the same entry works on POSIX and on Windows (Claude Code hooks run under a
/// POSIX shell — Git Bash — where `sh` and `curl` are available).
class ClaudeHookInstaller {
  ClaudeHookInstaller({
    required this.scriptPath,
    required this.settingsPath,
  });

  /// Absolute path of the shared forwarder script (`…/agent-hooks/claude-hook.sh`).
  final String scriptPath;

  /// Absolute path of the user Claude `settings.json` to merge into.
  final String settingsPath;

  /// Builds an installer from the app-data root and the ambient Claude config
  /// location (`CLAUDE_CONFIG_DIR`, else `$HOME`/`$USERPROFILE` `/.claude`).
  static ClaudeHookInstaller? forEnvironment({required String appDataRoot}) {
    final configDir = resolveClaudeConfigDir();
    if (configDir == null || appDataRoot.trim().isEmpty) return null;
    final scriptDir = _join(appDataRoot, 'agent-hooks');
    return ClaudeHookInstaller(
      scriptPath: _join(scriptDir, 'claude-hook.sh'),
      settingsPath: _join(configDir, 'settings.json'),
    );
  }

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
    final file = File(scriptPath);
    await file.parent.create(recursive: true);
    if (await file.exists() && await file.readAsString() == _scriptBody) {
      return;
    }
    await file.writeAsString(_scriptBody, flush: true);
  }

  Future<void> _mergeSettings() async {
    final file = File(settingsPath);
    Map<String, Object?> root = {};
    if (await file.exists()) {
      final text = await file.readAsString();
      if (text.trim().isNotEmpty) {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          root = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      }
      // Keep a single pristine backup — only if none exists yet, so a reinstall
      // never overwrites the original with an already-merged copy.
      final backup = File('$settingsPath.bak');
      if (!await backup.exists()) {
        await backup.writeAsString(text, flush: true);
      }
    } else {
      await file.parent.create(recursive: true);
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

    final tmp = File('$settingsPath.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(root),
      flush: true,
    );
    await tmp.rename(settingsPath);
  }

  /// A hook group is ours iff any of its commands reference our script path.
  bool _groupIsManaged(Object? group) {
    if (group is! Map) return false;
    final entries = group['hooks'];
    if (entries is! List) return false;
    final needle = scriptPath.replaceAll('\\', '/');
    for (final entry in entries) {
      if (entry is Map) {
        final command = entry['command'];
        if (command is String &&
            command.replaceAll('\\', '/').contains(needle)) {
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

/// POSIX forwarder. Drains stdin and no-ops unless the pane was stamped with
/// TeamPilot seat identity, then streams the raw hook JSON to the gateway with
/// short timeouts and `|| true` so a slow/unreachable gateway never stalls or
/// fails the agent turn.
const _scriptBody = '''#!/bin/sh
# TeamPilot agent-status forwarder (managed — do not edit).
# Identity comes from the PTY env stamped at connect; absent env => no-op.
if [ -z "\$TEAMPILOT_AGENT_STATUS_URL" ] || [ -z "\$TEAMPILOT_SESSION" ] || [ -z "\$TEAMPILOT_MEMBER" ]; then
  cat >/dev/null 2>&1
  exit 0
fi
curl -sS --connect-timeout 1 --max-time 3 \\
  -H "X-Session: \$TEAMPILOT_SESSION" \\
  -H "X-Member: \$TEAMPILOT_MEMBER" \\
  -H "Content-Type: application/json" \\
  --data-binary @- \\
  "\$TEAMPILOT_AGENT_STATUS_URL" >/dev/null 2>&1 || true
exit 0
''';
