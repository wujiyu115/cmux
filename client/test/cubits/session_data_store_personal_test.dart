import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  late Directory tmp;
  late SessionRepository sessionRepo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('session_data_personal_');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
    sessionRepo = SessionRepository();
  });

  tearDown(() {
    AppStorage.resetForTesting();
    tmp.deleteSync(recursive: true);
  });

  test(
    'createWorkspace writes the workspace and no session record',
    () async {
      const primaryPath = '/tmp/personal-workspace';
      final store = SessionDataStore();

      final result = await store.createWorkspace(
        [WorkspaceFolder(path: primaryPath)],
        sessionRepo,
      );

      // Terminals are materialised by the workspace terminal registry on open,
      // so a fresh workspace carries no session.json.
      final sessions = result.snapshot.sessions
          .where((s) => s.workspaceId == result.workspaceId)
          .toList();
      expect(sessions, isEmpty);
      expect(
        Directory(
          '${tmp.path}/workspace/workspaces/${result.workspaceId}/sessions',
        ).existsSync(),
        isFalse,
      );

      final workspaces = result.snapshot.workspaces
          .where((p) => p.workspaceId == result.workspaceId)
          .toList();
      expect(workspaces, hasLength(1));
      expect(
        File(
          '${tmp.path}/workspace/workspaces/${result.workspaceId}/profile.json',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'createWorkspace keeps every folder of a mixed-target workspace',
    () async {
      final store = SessionDataStore();

      final result = await store.createWorkspace(
        const [
          WorkspaceFolder(path: '/local'),
          WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
        ],
        sessionRepo,
      );

      final workspaces = result.snapshot.workspaces
          .where((p) => p.workspaceId == result.workspaceId)
          .toList();
      expect(workspaces, hasLength(1));
      expect(workspaces.first.folders, hasLength(2));

      final sessions = result.snapshot.sessions
          .where((s) => s.workspaceId == result.workspaceId)
          .toList();
      expect(sessions, isEmpty);
    },
  );
}
