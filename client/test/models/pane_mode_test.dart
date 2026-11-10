import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/pane_mode.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/services/terminal/workspace_terminal_session_ops.dart';

void main() {
  group('PaneMode', () {
    test('parses its own wire form', () {
      expect(PaneMode.parse('chat'), PaneMode.chat);
      expect(PaneMode.parse(' CHAT '), PaneMode.chat);
      expect(PaneMode.parse('terminal'), PaneMode.terminal);
      expect(PaneMode.chat.wire, 'chat');
    });

    test('unknown or missing values fall back to terminal', () {
      // A setting the app cannot read must never start an agent on its own.
      expect(PaneMode.parse(null), PaneMode.terminal);
      expect(PaneMode.parse(''), PaneMode.terminal);
      expect(PaneMode.parse(7), PaneMode.terminal);
      expect(PaneMode.parse('conversation'), PaneMode.terminal);
    });
  });

  group('new-pane settings', () {
    test('default to a terminal window running claude', () {
      final prefs = SessionPreferences();
      expect(prefs.newPaneMode, PaneMode.terminal);
      expect(
        prefs.chatAgentCommand,
        SessionPreferences.defaultChatAgentCommand,
      );
    });

    test('survive a JSON round trip', () {
      final prefs = SessionPreferences().copyWith(
        newPaneMode: PaneMode.chat,
        chatAgentCommand: 'pi --session-id x',
      );

      final restored = SessionPreferences.fromJson(prefs.toJson());

      expect(restored.newPaneMode, PaneMode.chat);
      expect(restored.chatAgentCommand, 'pi --session-id x');
    });

    test('an empty command falls back to the default', () {
      final restored = SessionPreferences.fromJson({
        'newPaneMode': 'chat',
        'chatAgentCommand': '   ',
      });
      expect(
        restored.chatAgentCommand,
        SessionPreferences.defaultChatAgentCommand,
      );
    });
  });

  group('chatAgentLaunchLine', () {
    test('types the configured command into a chat pane', () {
      expect(
        chatAgentLaunchLine(mode: PaneMode.chat, command: '  claude  '),
        'claude\r',
      );
      expect(
        chatAgentLaunchLine(
          mode: PaneMode.chat,
          command: 'pi --session-id abc',
        ),
        'pi --session-id abc\r',
      );
    });

    test('a terminal pane starts nothing', () {
      expect(
        chatAgentLaunchLine(mode: PaneMode.terminal, command: 'claude'),
        isNull,
      );
    });

    test('a chat pane with no command starts nothing', () {
      expect(chatAgentLaunchLine(mode: PaneMode.chat, command: '  '), isNull);
    });
  });
}
