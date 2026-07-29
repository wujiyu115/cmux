import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat/session_launch_retry.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';

AppSession _simpleSession() => AppSession(
  sessionId: 's1',
  workspaceId: 'w1',
  folders: const [WorkspaceFolder(path: '/w')],
  cli: CliTool.claude,
  provider: 'anthropic',
  model: 'claude-sonnet',
  effort: 'high',
  createdAt: 1,
  updatedAt: 1,
);

void main() {
  test('session preserves workbench view by default', () {
    final req = buildRetryExistingSessionConnect(session: _simpleSession());
    expect(req, isA<ExistingSessionConnect>());
    expect(req.preserveWorkbenchView, isTrue);
  });

  test('toggle path can force preserveWorkbenchView false', () {
    final req = buildRetryExistingSessionConnect(
      session: _simpleSession(),
      preserveWorkbenchView: false,
    );
    expect(req.preserveWorkbenchView, isFalse);
  });
}
