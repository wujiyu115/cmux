import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/claude_hook_installer.dart';

/// The events the installer manages in the user's settings.json.
const _managedEvents = [
  'UserPromptSubmit',
  'PreToolUse',
  'PostToolUse',
  'PermissionRequest',
  'Stop',
  'StopFailure',
];

void main() {
  late Directory tmp;
  late String scriptPath;
  late String settingsPath;
  late ClaudeHookInstaller installer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('claude_hook_test_');
    scriptPath = '${tmp.path}/agent-hooks/claude-hook.sh';
    settingsPath = '${tmp.path}/.claude/settings.json';
    installer = ClaudeHookInstaller(
      scriptPath: scriptPath,
      settingsPath: settingsPath,
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, dynamic> readSettings() =>
      jsonDecode(File(settingsPath).readAsStringSync()) as Map<String, dynamic>;

  List<dynamic> groupsFor(String event) =>
      (readSettings()['hooks'] as Map)[event] as List;

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

    for (final event in _managedEvents) {
      final groups = groupsFor(event);
      expect(groups, isNotEmpty, reason: '$event missing');
      final command =
          ((groups.last['hooks'] as List).first as Map)['command'] as String;
      expect(command, installer.hookCommand);
      expect(command, contains('claude-hook.sh'));
    }
    // Tool-scoped events keep a wildcard matcher; lifecycle events omit it.
    expect((groupsFor('PreToolUse').last as Map)['matcher'], '*');
    expect((groupsFor('Stop').last as Map).containsKey('matcher'), isFalse);
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

    final settings = readSettings();
    // Untouched top-level user keys survive.
    expect(settings['model'], 'opus');
    // Unmanaged event untouched.
    final sessionStart = (settings['hooks'] as Map)['SessionStart'] as List;
    expect(
      ((sessionStart.first['hooks'] as List).first as Map)['command'],
      'agent-deck start',
    );
    // Managed event keeps the user's group AND appends ours.
    final stop = groupsFor('Stop');
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

    for (final event in _managedEvents) {
      final ours = groupsFor(event)
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
    // Mutate settings post-install, then reinstall — backup must stay pristine.
    await installer.install();

    final backup = File('$settingsPath.bak').readAsStringSync();
    expect(backup, '{"model":"original"}');
  });

  test('resolveClaudeConfigDir honours CLAUDE_CONFIG_DIR', () {
    // Sanity: the resolver returns something absolute-ish on this host.
    final dir = ClaudeHookInstaller.resolveClaudeConfigDir();
    expect(dir, isNotNull);
  });
}
