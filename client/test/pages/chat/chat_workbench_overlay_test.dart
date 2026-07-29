import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/chat_workbench_overlay.dart';

void main() {
  group('resolveChatWorkbenchOverlay', () {
    test('shows sessionStarting while connect is in progress', () {
      expect(
        resolveChatWorkbenchOverlay(
          sessionConnectInProgress: true,
          showRemoteProvision: false,
        ),
        ChatWorkbenchOverlay.sessionStarting,
      );
    });

    test('remote provision wins over the connect spinner', () {
      expect(
        resolveChatWorkbenchOverlay(
          sessionConnectInProgress: true,
          showRemoteProvision: true,
        ),
        ChatWorkbenchOverlay.remoteProvision,
      );
    });

    test('none when idle', () {
      expect(
        resolveChatWorkbenchOverlay(
          sessionConnectInProgress: false,
          showRemoteProvision: false,
        ),
        ChatWorkbenchOverlay.none,
      );
    });
  });
}
