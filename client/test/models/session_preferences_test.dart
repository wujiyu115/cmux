import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_preferences.dart';

void main() {
  group('SessionPreferences', () {
    test('defaults are empty path with session scoping on', () {
      final prefs = SessionPreferences();
      expect(prefs.cliExecutablePathFor('flashskyai'), '');
      expect(prefs.defaultSshWorkingDirectory, '');
      expect(prefs.sshUseLoginShell, false);
      expect(prefs.openExistingSessionStartsTerminal, false);
      expect(prefs.simpleModeDefaultFullAccess, true);
    });

    test('toJson/fromJson round-trips', () {
      final prefs = SessionPreferences(
        cliExecutablePaths: const {
          'flashskyai': '/opt/bin/flashskyai',
          'claude': '/opt/bin/claude',
          'codex': '/opt/bin/codex',
        },
        defaultSshWorkingDirectory: '~/work',
        sshUseLoginShell: true,
        openExistingSessionStartsTerminal: true,
        simpleModeDefaultFullAccess: false,
      );
      final restored = SessionPreferences.fromJson(prefs.toJson());
      expect(restored.cliExecutablePaths, {
        'flashskyai': '/opt/bin/flashskyai',
        'claude': '/opt/bin/claude',
        'codex': '/opt/bin/codex',
      });
      expect(restored.defaultSshWorkingDirectory, '~/work');
      expect(restored.sshUseLoginShell, true);
      expect(restored.openExistingSessionStartsTerminal, true);
      expect(restored.simpleModeDefaultFullAccess, false);
    });

    test('toJson is free of legacy runtime knobs', () {
      final json = SessionPreferences().toJson();
      expect(json.containsKey('connectionMode'), isFalse);
      expect(json.containsKey('windowsStorageBackend'), isFalse);
    });

    test('fromJson falls back to defaults when keys are missing', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{});
      expect(restored.cliExecutablePaths, isEmpty);
      expect(restored.defaultSshWorkingDirectory, '');
      expect(restored.sshUseLoginShell, false);
      expect(restored.openExistingSessionStartsTerminal, false);
      expect(restored.simpleModeDefaultFullAccess, true);
    });

    test('copyWith updates only specified fields', () {
      final prefs = SessionPreferences();
      final next = prefs.copyWith(
        cliExecutablePaths: const {'flashskyai': '/a/b', 'claude': '/c/d'},
        openExistingSessionStartsTerminal: true,
        simpleModeDefaultFullAccess: false,
      );
      expect(next.cliExecutablePathFor('flashskyai'), '/a/b');
      expect(next.cliExecutablePaths, {'flashskyai': '/a/b', 'claude': '/c/d'});
      expect(next.defaultSshWorkingDirectory, '');
      expect(next.sshUseLoginShell, false);
      expect(next.openExistingSessionStartsTerminal, true);
      expect(next.simpleModeDefaultFullAccess, false);
    });

    test('simpleModeDefaultFullAccess defaults true', () {
      expect(SessionPreferences().simpleModeDefaultFullAccess, isTrue);
    });

    test('simpleModeDefaultFullAccess JSON round-trip', () {
      final prefs = SessionPreferences(simpleModeDefaultFullAccess: false);
      final again = SessionPreferences.fromJson(prefs.toJson());
      expect(again.simpleModeDefaultFullAccess, isFalse);
    });

    test('fromJson defaults simpleModeDefaultFullAccess when key missing', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{});
      expect(restored.simpleModeDefaultFullAccess, isTrue);
    });

    test('notifyWhileWatching defaults true', () {
      expect(SessionPreferences().notifyWhileWatching, isTrue);
    });

    test('notifyWhileWatching JSON round-trip', () {
      final prefs = SessionPreferences(notifyWhileWatching: false);
      final again = SessionPreferences.fromJson(prefs.toJson());
      expect(again.notifyWhileWatching, isFalse);
    });

    test('fromJson defaults notifyWhileWatching when key missing', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{});
      expect(restored.notifyWhileWatching, isTrue);
    });

    test('notifyOnPtyIdle defaults false', () {
      // The PTY-output heuristic is opt-in: it cannot tell a finished turn from
      // a long build, so it must not fire for anyone who did not ask for it.
      expect(SessionPreferences().notifyOnPtyIdle, isFalse);
    });

    test('notifyOnPtyIdle JSON round-trip', () {
      final prefs = SessionPreferences(notifyOnPtyIdle: true);
      final again = SessionPreferences.fromJson(prefs.toJson());
      expect(again.notifyOnPtyIdle, isTrue);
    });

    test('fromJson defaults notifyOnPtyIdle when key missing', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{});
      expect(restored.notifyOnPtyIdle, isFalse);
    });

    test('fromJson ignores non-string cli executable path entries', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{
        'cliExecutablePaths': {
          'claude': '/opt/bin/claude',
          'codex': 42,
          '': '/bad',
          'flashskyai': '   ',
        },
      });

      expect(restored.cliExecutablePaths, {'claude': '/opt/bin/claude'});
    });
  });
}
