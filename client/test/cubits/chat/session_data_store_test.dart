import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  test('unscoped snapshot exposes all', () {
    final store = SessionDataStore();
    final workspaces = [
      Workspace(
        workspaceId: 'p',
        folders: [WorkspaceFolder(path: '/p')],
        createdAt: 0,
      ),
    ];
    final sessions = [
      AppSession(
        sessionId: 's',
        workspaceId: 'p',
        folders: [WorkspaceFolder(path: '/p')],
        createdAt: 0,
      ),
    ];
    final snap = store.deriveSnapshot(
      workspaces: workspaces,
      sessions: sessions,
    );
    expect(snap.visibleSessions, sessions);
    expect(snap.visibleWorkspaces, workspaces);
  });
}
