import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_open_request.dart';
import 'package:teampilot/cubits/chat/model/session_open_status.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/launch/session_launch_open_validator.dart';

void main() {
  final workspace = Workspace(
    workspaceId: 'ws-1',
    folders: [WorkspaceFolder(path: '/project')],
    createdAt: 0,
  );

  Workspace? workspaceById(String id) => id == 'ws-1' ? workspace : null;

  group('validateSessionOpenRequest', () {
    test('session requires workspace', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'missing',
        folders: workspace.folders,
        createdAt: 0,
      );
      final status = validateSessionOpenRequest(
        request: SessionOpenRequest(session: session),
        session: session,
        workspaceById: workspaceById,
      );
      expect(status, SessionOpenStatus.missingWorkspace);
    });

    test('request workspace overrides the index lookup', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'missing',
        folders: workspace.folders,
        createdAt: 0,
      );
      final status = validateSessionOpenRequest(
        request: SessionOpenRequest(session: session, workspace: workspace),
        session: session,
        workspaceById: workspaceById,
      );
      expect(status, isNull);
    });

    test('returns null when request is valid', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: workspace.workspaceId,
        folders: workspace.folders,
        createdAt: 0,
      );
      final status = validateSessionOpenRequest(
        request: SessionOpenRequest(session: session),
        session: session,
        workspaceById: workspaceById,
      );
      expect(status, isNull);
    });
  });
}
