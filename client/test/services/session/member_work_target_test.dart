import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';


WorkspaceLaunchContext _ctx(
  AppSession session, {
  List<WorkspaceFolder>? workspaceFolders,
}) => WorkspaceLaunchContext(
  session: session,
  workspace: Workspace(
    workspaceId: session.workspaceId,
    folders: workspaceFolders ?? session.folders,
    createdAt: 0,
  ),
);

void main() {
  test('personal session launchWorkTarget uses workspace session target', () {
    final lifecycle = SessionLifecycleService();
    final session = AppSession(
      sessionId: 's-personal',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/root/hhoa', targetId: 'ssh:p1')],
      createdAt: 1,
    );

    expect(lifecycle.launchWorkTarget(_ctx(session)).id, 'ssh:p1');
  });

  test('personal session workDirs on mixed workspace filters add-dirs by target', () {
    final session = AppSession(
      sessionId: 's-personal',
      workspaceId: 'w1',
      folders: const [
        WorkspaceFolder(path: '/local', targetId: 'local'),
        WorkspaceFolder(path: '/local-extra', targetId: 'local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ],
      createdAt: 1,
    );
    final dirs = session.workDirsForMember(null, folders: session.folders);
    expect(dirs.workingDirectory, '/local');
    expect(dirs.addDirs, ['/local-extra']);
  });
}
