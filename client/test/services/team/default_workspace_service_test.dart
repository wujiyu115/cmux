import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/team/default_workspace_service.dart';
import 'package:teampilot/utils/workspace/workspace_path_utils.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late Directory base;

  setUp(() async {
    setUpTestAppStorage();
    base = Directory.systemTemp.createTempSync('default_workspace_');
    DefaultWorkspaceDirectory.setForTesting(p.join(base.path, 'Documents'));
  });

  tearDown(() {
    tearDownTestAppStorage();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  test('seed creates the Default workspace with one session', () async {
    final repo = SessionRepository();

    final workspace = await DefaultWorkspaceService.seed(repo);

    expect(workspace.display, DefaultWorkspaceService.defaultDisplay);
    expect(
      workspace.firstFolderPath,
      normalizeWorkspacePath(p.join(base.path, 'Documents', 'TeamPilot')),
    );
    expect(workspace.defaultProfileId, isEmpty);

    final sessions = await repo.loadSessions();
    final workspaceSessions = sessions
        .where((s) => s.workspaceId == workspace.workspaceId)
        .toList();
    expect(workspaceSessions, hasLength(1));
    expect(workspaceSessions.single.profileId, isEmpty);
  });

  test('seed is idempotent', () async {
    final repo = SessionRepository();

    await DefaultWorkspaceService.seed(repo);
    await DefaultWorkspaceService.seed(repo);

    final workspaces = await repo.loadWorkspaces();
    expect(workspaces, hasLength(1));
    final sessions = await repo.loadSessions();
    expect(
      sessions.where((s) => s.workspaceId == workspaces.single.workspaceId),
      hasLength(1),
    );
  });

  test('ensureDefault is idempotent and reports no mutation', () async {
    final repo = SessionRepository();

    final first = await DefaultWorkspaceService.ensureDefault(repo);
    expect(first, isTrue);

    final workspaces = await repo.loadWorkspaces();
    final again = await DefaultWorkspaceService.ensureDefault(
      repo,
      knownWorkspaces: workspaces,
    );
    expect(again, isFalse);
  });
}
