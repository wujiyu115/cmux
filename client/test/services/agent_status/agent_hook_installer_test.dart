import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_hook_installer.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../support/in_memory_filesystem.dart';

/// Managed event set for Claude and Qoder. Codex has no StopFailure event.
const _fullEvents = [
  'UserPromptSubmit',
  'PreToolUse',
  'PostToolUse',
  'PermissionRequest',
  'Stop',
  'StopFailure',
];

const _codexEvents = [
  'UserPromptSubmit',
  'PreToolUse',
  'PostToolUse',
  'PermissionRequest',
  'Stop',
];

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('agent_hook_test_');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  AgentHookInstaller installerFor(
    AgentHookTarget target, {
    String? settingsPath,
    String? scriptPath,
    String? windowsScriptPath,
    Filesystem? filesystem,
  }) =>
      AgentHookInstaller(
        target: target,
        scriptPath: scriptPath ?? '${tmp.path}/agent-hooks/claude-hook.sh',
        windowsScriptPath: windowsScriptPath,
        settingsPath:
            settingsPath ??
            switch (target) {
              AgentHookTarget.claude => '${tmp.path}/.claude/settings.json',
              AgentHookTarget.qoder => '${tmp.path}/.qoder/settings.json',
              AgentHookTarget.codex => '${tmp.path}/.codex/hooks.json',
            },
        filesystem: filesystem,
      );

  Map<String, dynamic> readSettings(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  List<dynamic> groupsFor(String settingsPath, String event) =>
      ((readSettings(settingsPath)['hooks'] as Map)[event] ?? []) as List;

  group('claude target — behaviour unchanged', () {
    late String scriptPath;
    late String settingsPath;
    late AgentHookInstaller installer;

    setUp(() {
      scriptPath = '${tmp.path}/agent-hooks/claude-hook.sh';
      settingsPath = '${tmp.path}/.claude/settings.json';
      installer = installerFor(AgentHookTarget.claude);
    });

    test('writes the forwarder script guarded by seat identity env', () async {
      await installer.install();

      final body = File(scriptPath).readAsStringSync();
      expect(body, contains('TEAMPILOT_AGENT_STATUS_URL'));
      expect(body, contains('TEAMPILOT_SESSION'));
      expect(body, contains('TEAMPILOT_MEMBER'));
      expect(body, contains('--data-binary @-'));
      expect(body, contains('X-Session'));
      expect(body, contains('X-Member'));
    });

    test('registers a managed command for every managed event', () async {
      await installer.install();

      for (final event in _fullEvents) {
        final groups = groupsFor(settingsPath, event);
        expect(groups, isNotEmpty, reason: '$event missing');
        final command =
            ((groups.last['hooks'] as List).first as Map)['command'] as String;
        expect(command, installer.hookCommand);
        expect(command, contains('claude-hook.sh'));
      }
      // Tool-scoped events keep a wildcard matcher; lifecycle events omit it.
      expect(
        (groupsFor(settingsPath, 'PreToolUse').last as Map)['matcher'],
        '*',
      );
      expect(
        (groupsFor(settingsPath, 'Stop').last as Map).containsKey('matcher'),
        isFalse,
      );
    });

    test('preserves the user\'s own hooks and unmanaged events', () async {
      File(settingsPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'model': 'opus',
            'hooks': {
              'Stop': [
                {
                  'hooks': [
                    {'type': 'command', 'command': 'claude-toast.sh done'},
                  ],
                },
              ],
              'SessionStart': [
                {
                  'hooks': [
                    {'type': 'command', 'command': 'agent-deck start'},
                  ],
                },
              ],
            },
          }),
        );

      await installer.install();

      final settings = readSettings(settingsPath);
      expect(settings['model'], 'opus');
      final sessionStart = (settings['hooks'] as Map)['SessionStart'] as List;
      expect(
        ((sessionStart.first['hooks'] as List).first as Map)['command'],
        'agent-deck start',
      );
      final stop = groupsFor(settingsPath, 'Stop');
      final commands = stop
          .expand((g) => (g['hooks'] as List))
          .map((h) => (h as Map)['command'] as String)
          .toList();
      expect(commands, contains('claude-toast.sh done'));
      expect(commands.where((c) => c == installer.hookCommand), hasLength(1));
    });

    test('reinstall is idempotent — no duplicate managed groups', () async {
      await installer.install();
      await installer.install();
      await installer.install();

      for (final event in _fullEvents) {
        final ours = groupsFor(settingsPath, event)
            .where(
              (g) => (g['hooks'] as List).any(
                (h) => (h as Map)['command'] == installer.hookCommand,
              ),
            )
            .toList();
        expect(ours, hasLength(1), reason: '$event duplicated');
      }
    });

    test('keeps a single pristine .bak of the original settings', () async {
      File(settingsPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('{"model":"original"}');

      await installer.install();
      await installer.install();

      final backup = File('$settingsPath.bak').readAsStringSync();
      expect(backup, '{"model":"original"}');
    });

    test('resolveClaudeConfigDir honours CLAUDE_CONFIG_DIR', () {
      expect(AgentHookInstaller.resolveClaudeConfigDir(), isNotNull);
    });
  });

  group('qoder target', () {
    test('registers the full event set in ~/.qoder/settings.json', () async {
      final installer = installerFor(AgentHookTarget.qoder);
      await installer.install();

      final settingsPath = '${tmp.path}/.qoder/settings.json';
      for (final event in _fullEvents) {
        expect(groupsFor(settingsPath, event), isNotEmpty,
            reason: '$event missing');
      }
      final entry = ((groupsFor(settingsPath, 'PreToolUse').last['hooks']
              as List)
          .first) as Map;
      expect(entry['command'], installer.hookCommand);
      expect(entry.containsKey('commandWindows'), isFalse);
      expect(
        (groupsFor(settingsPath, 'PreToolUse').last as Map)['matcher'],
        '*',
      );
    });

    test('merges additively beside the user\'s own qoder hooks', () async {
      final settingsPath = '${tmp.path}/.qoder/settings.json';
      File(settingsPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'enabledPlugins': {'superpowers': true},
            'hooks': {
              'PermissionRequest': [
                {
                  'matcher': '*',
                  'hooks': [
                    {
                      'type': 'command',
                      'command': '~/.qoder/hooks/notify.sh',
                      'timeout': 5,
                    },
                  ],
                },
              ],
            },
          }),
        );

      await installerFor(AgentHookTarget.qoder).install();

      final settings = readSettings(settingsPath);
      expect((settings['enabledPlugins'] as Map)['superpowers'], true);
      final commands = groupsFor(settingsPath, 'PermissionRequest')
          .expand((g) => (g['hooks'] as List))
          .map((h) => (h as Map)['command'] as String)
          .toList();
      expect(commands, contains('~/.qoder/hooks/notify.sh'));
      expect(commands.where((c) => c.contains('claude-hook.sh')), hasLength(1));
    });
  });

  group('codex target', () {
    test('omits StopFailure and matchers, adds a Windows command', () async {
      final cmdPath = '${tmp.path}/agent-hooks/codex-hook.cmd';
      final installer = installerFor(
        AgentHookTarget.codex,
        windowsScriptPath: cmdPath,
      );
      await installer.install();

      final settingsPath = '${tmp.path}/.codex/hooks.json';
      final hooks = readSettings(settingsPath)['hooks'] as Map;
      for (final event in _codexEvents) {
        expect(hooks[event], isNotEmpty, reason: '$event missing');
      }
      expect(hooks.containsKey('StopFailure'), isFalse);

      final preToolUse = (hooks['PreToolUse'] as List).last as Map;
      // Codex matchers are regexes — a bare `*` would be invalid.
      expect(preToolUse.containsKey('matcher'), isFalse);

      final entry = (preToolUse['hooks'] as List).first as Map;
      expect(entry['command'], installer.hookCommand);
      expect(entry['commandWindows'], '"$cmdPath"');
      expect(entry['timeout'], 5);
    });

    test('writes the codex-hook.cmd forwarder with CRLF endings', () async {
      final cmdPath = '${tmp.path}/agent-hooks/codex-hook.cmd';
      await installerFor(
        AgentHookTarget.codex,
        windowsScriptPath: cmdPath,
      ).install();

      final body = File(cmdPath).readAsStringSync();
      // cmd.exe batch convention — CRLF, never a bare LF or lone CR.
      expect(body, contains('\r\n'));
      expect(body.replaceAll('\r\n', ''), isNot(contains('\r')));
      // Same no-op-without-identity contract as the sh script.
      expect(body, contains('TEAMPILOT_AGENT_STATUS_URL'));
      expect(body, contains('TEAMPILOT_SESSION'));
      expect(body, contains('TEAMPILOT_MEMBER'));
      expect(body, contains('X-Session'));
      expect(body, contains('X-Member'));
      expect(body, contains('--data-binary @-'));
      expect(body, contains('curl.exe'));
      // Drains stdin when unstamped so a plain codex run never stalls.
      expect(body, contains('more.com'));
      expect(body, contains('exit /b 0'));
    });

    test('POSIX-only install (WSL distro) omits commandWindows', () async {
      final installer = installerFor(AgentHookTarget.codex);
      await installer.install();

      final settingsPath = '${tmp.path}/.codex/hooks.json';
      final entry =
          (((readSettings(settingsPath)['hooks'] as Map)['Stop'] as List)
                  .last['hooks'] as List)
              .first as Map;
      expect(entry['command'], installer.hookCommand);
      expect(entry.containsKey('commandWindows'), isFalse);
      // The .cmd forwarder is host-only; a distro never gets one.
      expect(
        File('${tmp.path}/agent-hooks/codex-hook.cmd').existsSync(),
        isFalse,
      );
    });

    test('an Orca-style codex entry is left untouched', () async {
      // Orca also ships a `codex-hook.cmd`; ours must be recognisable by the
      // shared sh script referenced in `command`, never by the cmd file name —
      // otherwise the install would strip the user's Orca wiring.
      final settingsPath = '${tmp.path}/.codex/hooks.json';
      File(settingsPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'hooks': {
              'Stop': [
                {
                  'hooks': [
                    {
                      'type': 'command',
                      'command': r'C:\Users\u\.orca\agent-hooks\codex-hook.cmd',
                      'timeout': 10,
                    },
                  ],
                },
              ],
            },
          }),
        );

      await installerFor(
        AgentHookTarget.codex,
        windowsScriptPath: '${tmp.path}/agent-hooks/codex-hook.cmd',
      ).install();

      final commands = groupsFor(settingsPath, 'Stop')
          .expand((g) => (g['hooks'] as List))
          .map((h) => (h as Map)['command'] as String)
          .toList();
      expect(
        commands,
        contains(r'C:\Users\u\.orca\agent-hooks\codex-hook.cmd'),
      );
      expect(commands.where((c) => c.contains('claude-hook.sh')), hasLength(1));
    });
  });

  group('forWslDistro', () {
    test(
        'writes each target\'s settings inside the distro via the injected fs',
        () async {
      final fs = InMemoryFilesystem();
      const appDataRoot = '/home/u/.local/share/com.hhoa.teampilot';
      const script = '$appDataRoot/agent-hooks/claude-hook.sh';

      for (final target in AgentHookTarget.values) {
        await AgentHookInstaller.forWslDistro(
          target: target,
          distro: 'Ubuntu',
          distroHome: '/home/u',
          distroAppDataRoot: appDataRoot,
          filesystem: fs,
        ).install();
      }

      expect(fs.files[script], isNotNull);
      expect(fs.files['/home/u/.claude/settings.json'], isNotNull);
      expect(fs.files['/home/u/.qoder/settings.json'], isNotNull);
      expect(fs.files['/home/u/.codex/hooks.json'], isNotNull);

      // The command must be a POSIX path valid *inside* the distro, and a
      // distro never needs the Windows cmd forwarder.
      final codexRoot =
          jsonDecode(fs.files['/home/u/.codex/hooks.json']!) as Map;
      final entry =
          ((((codexRoot['hooks'] as Map)['Stop'] as List).last as Map)['hooks']
                  as List)
              .first as Map;
      expect(entry['command'], 'sh "$script"');
      expect(entry.containsKey('commandWindows'), isFalse);
    });

    test('distro body reaches the host gateway through Windows curl.exe', () {
      // WSL2 NAT: the distro's own 127.0.0.1 is not the host's, and the gateway
      // deliberately binds loopback only. Interop curl.exe runs on the Windows
      // network stack, so it can reach it.
      expect(
        agentHookWslScriptBody,
        contains('/mnt/c/Windows/System32/curl.exe'),
      );
      expect(agentHookWslScriptBody, contains('CURL=curl'));
      expect(agentHookHostScriptBody, isNot(contains('curl.exe')));
    });
  });

  group('forHost', () {
    test('resolves each target to its own settings file', () {
      final byTarget = <AgentHookTarget, AgentHookInstaller?>{};
      for (final target in AgentHookTarget.values) {
        byTarget[target] = AgentHookInstaller.forHost(
          target: target,
          hostAppDataRoot: '/host/app',
        );
      }

      expect(
        byTarget[AgentHookTarget.claude]?.settingsPath,
        endsWith('.claude${Platform.pathSeparator}settings.json'),
      );
      expect(
        byTarget[AgentHookTarget.qoder]?.settingsPath,
        endsWith('.qoder${Platform.pathSeparator}settings.json'),
      );
      expect(
        byTarget[AgentHookTarget.codex]?.settingsPath,
        endsWith('.codex${Platform.pathSeparator}hooks.json'),
      );

      for (final installer in byTarget.values) {
        expect(installer, isNotNull);
        expect(
          installer!.scriptPath,
          contains('/host/app/agent-hooks/claude-hook.sh'),
        );
        // Claude and Qoder never need a Windows forwarder; codex only on a
        // Windows host.
        if (installer.target == AgentHookTarget.codex) {
          expect(
            installer.windowsScriptPath,
            Platform.isWindows ? isNotNull : isNull,
          );
        } else {
          expect(installer.windowsScriptPath, isNull);
        }
      }
    });

    test('returns null for a blank app-data root', () {
      expect(
        AgentHookInstaller.forHost(
          target: AgentHookTarget.claude,
          hostAppDataRoot: '  ',
        ),
        isNull,
      );
    });
  });

  group('script line endings', () {
    test('emits LF even when the body literal arrives as CRLF', () async {
      final fs = InMemoryFilesystem();
      final crlf = AgentHookInstaller(
        target: AgentHookTarget.claude,
        scriptPath: '/app/agent-hooks/claude-hook.sh',
        settingsPath: '/home/u/.claude/settings.json',
        filesystem: fs,
        scriptBody: 'if [ -z "\$X" ]; then\r\n  exit 0\r\nfi\r\n',
      );
      await crlf.install();

      final written = fs.files['/app/agent-hooks/claude-hook.sh'];
      expect(written, isNotNull);
      // `sh` (dash in a distro) fails on `then\r`, and a `\` before CR breaks
      // line continuation — turning the curl invocation into separate commands.
      expect(written, isNot(contains('\r')));
      expect(written, 'if [ -z "\$X" ]; then\n  exit 0\nfi\n');
    });

    test('shipped bodies are CR-free after normalisation', () {
      for (final body in [agentHookHostScriptBody, agentHookWslScriptBody]) {
        expect(
          AgentHookInstaller.normalizeScriptEndings(body),
          isNot(contains('\r')),
        );
      }
    });
  });

  test('strips managed groups written under a different app-data root',
      () async {
    // Regression: the needle used to be the full scriptPath, so entries from an
    // earlier root were never recognised and piled up on every reinstall.
    final fs = InMemoryFilesystem();
    fs.files['/home/u/.claude/settings.json'] = jsonEncode({
      'hooks': {
        'Stop': [
          {
            'hooks': [
              {
                'type': 'command',
                'command': 'sh "D:/old/root/agent-hooks/claude-hook.sh"',
                'timeout': 5,
              },
            ],
          },
          {
            'hooks': [
              {'type': 'command', 'command': 'my-own-hook', 'timeout': 5},
            ],
          },
        ],
      },
    });

    await AgentHookInstaller(
      target: AgentHookTarget.claude,
      scriptPath: '/new/root/agent-hooks/claude-hook.sh',
      settingsPath: '/home/u/.claude/settings.json',
      filesystem: fs,
    ).install();

    final root = jsonDecode(fs.files['/home/u/.claude/settings.json']!) as Map;
    final stop = (root['hooks'] as Map)['Stop'] as List;
    final commands = stop
        .map((g) => ((g as Map)['hooks'] as List).first as Map)
        .map((h) => h['command'] as String)
        .toList();

    expect(commands, contains('my-own-hook'));
    expect(commands.where((c) => c.contains('D:/old/root')), isEmpty);
    expect(commands.where((c) => c.contains('claude-hook.sh')), hasLength(1));
  });

  test('reinstall replaces our codex commandWindows entry, not duplicates it',
      () async {
    final cmdPath = '${tmp.path}/agent-hooks/codex-hook.cmd';
    final installer = installerFor(
      AgentHookTarget.codex,
      windowsScriptPath: cmdPath,
    );
    await installer.install();
    await installer.install();

    final settingsPath = '${tmp.path}/.codex/hooks.json';
    final entries = groupsFor(settingsPath, 'Stop')
        .expand((g) => (g['hooks'] as List))
        .map((h) => h as Map)
        .toList();
    expect(
      entries.where((e) => (e['command'] as String).contains('claude-hook.sh')),
      hasLength(1),
    );
    expect(
      entries.where((e) => e['commandWindows'] == '"$cmdPath"'),
      hasLength(1),
    );
  });
}
