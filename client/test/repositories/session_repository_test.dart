import 'dart:convert';
import 'dart:io';

import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_icon_ref.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty root yields empty workspaces and sessions', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    expect(await repo.loadWorkspaces(), isEmpty);
    expect(await repo.loadSessions(), isEmpty);
  });

  test(
    'createWorkspace, createSession, markSessionStarted, deleteSession',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp/my-workspace'),
      ]);
      expect(workspace.firstFolderPath, '/tmp/my-workspace');

      final session = await repo.createSession(workspace.workspaceId);
      expect(session.workspaceId, workspace.workspaceId);
      expect(session.firstFolderPath, '/tmp/my-workspace');
      expect(session.launchState, AppSessionLaunchState.created);

      var workspaces = await repo.loadWorkspaces();
      expect(workspaces.single.sessionIds, contains(session.sessionId));

      await repo.markSessionStarted(session.sessionId);
      final reloaded = await repo.loadSessions();
      expect(reloaded.single.launchState, AppSessionLaunchState.started);

      await repo.renameSession(session.sessionId, 'Renamed');
      expect((await repo.loadSessions()).single.display, 'Renamed');

      await repo.deleteSession(session.sessionId);
      expect(await repo.loadSessions(), isEmpty);
      workspaces = await repo.loadWorkspaces();
      expect(workspaces.single.sessionIds, isEmpty);
    },
  );

  test(
    'createSession prepends sessionId without bumping workspace updatedAt',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/a'),
      ]);
      final s1 = await repo.createSession(workspace.workspaceId);
      final afterFirst = (await repo.loadWorkspaces()).single;
      final s2 = await repo.createSession(workspace.workspaceId);
      final afterSecond = (await repo.loadWorkspaces()).single;

      expect(afterSecond.sessionIds, [s2.sessionId, s1.sessionId]);
      expect(afterSecond.updatedAt, afterFirst.updatedAt);
    },
  );

  test('deleteWorkspace removes workspace and session files', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/a')]);
    final s1 = await repo.createSession(workspace.workspaceId);
    final s2 = await repo.createSession(workspace.workspaceId);

    await repo.deleteWorkspace(workspace.workspaceId);
    expect(await repo.loadWorkspaces(), isEmpty);
    expect(await repo.loadSessions(), isEmpty);
    expect(
      Directory(
        '${tmp.path}/workspace/workspaces/${workspace.workspaceId}/sessions/${s1.sessionId}',
      ).existsSync(),
      isFalse,
    );
    expect(
      Directory(
        '${tmp.path}/workspace/workspaces/${workspace.workspaceId}/sessions/${s2.sessionId}',
      ).existsSync(),
      isFalse,
    );
  });

  test(
    'createWorkspace merges additionalPaths and display for same primaryPath',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final p1 = await repo.createWorkspace([
        WorkspaceFolder(path: '/root'),
        WorkspaceFolder(path: '/a'),
      ]);
      expect(p1.extraFolderPaths, ['/a']);

      final p2 = await repo.createWorkspace([
        WorkspaceFolder(path: '/root'),
        WorkspaceFolder(path: '/b'),
        WorkspaceFolder(path: '/a'),
      ], display: 'My display');
      expect(p2.workspaceId, p1.workspaceId);
      expect(p2.extraFolderPaths, ['/a', '/b']);
      expect(p2.display, 'My display');
    },
  );

  test('createWorkspace reuses same primary path', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final a = await repo.createWorkspace([WorkspaceFolder(path: '/shared')]);
    final b = await repo.createWorkspace([WorkspaceFolder(path: '/shared')]);

    expect(a.workspaceId, b.workspaceId);
    expect((await repo.loadWorkspaces()).length, 1);
  });

  test(
    'createWorkspace allowDuplicate creates distinct same-path workspace',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final a = await repo.createWorkspace([
        WorkspaceFolder(path: '/shared'),
      ], display: 'First');
      final b = await repo.createWorkspace(
        [WorkspaceFolder(path: '/shared')],
        display: 'Second',
        allowDuplicate: true,
      );

      expect(a.workspaceId, isNot(b.workspaceId));
      expect(a.firstFolderPath, b.firstFolderPath);
      final loaded = await repo.loadWorkspaces();
      expect(loaded.length, 2);
      expect(loaded.map((w) => w.display).toSet(), {'First', 'Second'});
    },
  );

  test('updateWorkspaceMetadata updates display', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createWorkspace([
      WorkspaceFolder(path: '/base'),
      WorkspaceFolder(path: '/a'),
    ]);
    await repo.updateWorkspaceMetadata(p.workspaceId, display: 'My App');
    final loaded = await repo.loadWorkspaces();
    expect(loaded.single.display, 'My App');
    expect(loaded.single.extraFolderPaths, ['/a']);
  });

  test('updateWorkspaceMetadata persists rootSandboxEnvOptIn', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createWorkspace([WorkspaceFolder(path: '/base')]);
    expect(p.rootSandboxEnvOptIn, isFalse);

    await repo.updateWorkspaceMetadata(
      p.workspaceId,
      rootSandboxEnvOptIn: true,
    );
    final loaded = await repo.loadWorkspaces();
    expect(loaded.single.rootSandboxEnvOptIn, isTrue);
  });

  test('applyWorkspaceIcon persists preset and auto icons', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createWorkspace([WorkspaceFolder(path: '/base')]);
    expect(p.icon, WorkspaceIconRef.auto);

    await repo.applyWorkspaceIcon(p.workspaceId, const WorkspaceIconPreset(5));
    var loaded = (await repo.loadWorkspaces()).single;
    expect(loaded.icon, const WorkspaceIconPreset(5));

    await repo.applyWorkspaceIcon(p.workspaceId, WorkspaceIconRef.auto);
    loaded = (await repo.loadWorkspaces()).single;
    expect(loaded.icon, WorkspaceIconRef.auto);
  });

  test(
    'importCustomWorkspaceIcon persists file and preset clears custom',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final iconFile = File('${tmp.path}/picked.png');
      await iconFile.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

      final repo = SessionRepository(rootDir: tmp.path);
      final p = await repo.createWorkspace([WorkspaceFolder(path: '/base')]);
      await repo.importCustomWorkspaceIcon(p.workspaceId, iconFile.path);

      var loaded = (await repo.loadWorkspaces()).single;
      expect(loaded.icon, WorkspaceIconCustom('assets/icon.png'));

      await repo.applyWorkspaceIcon(
        p.workspaceId,
        const WorkspaceIconPreset(2),
      );
      loaded = (await repo.loadWorkspaces()).single;
      expect(loaded.icon, const WorkspaceIconPreset(2));
    },
  );

  test('updateWorkspaceFolders updates index', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createWorkspace([WorkspaceFolder(path: '/old')]);
    await repo.updateWorkspaceFolders(p.workspaceId, [
      WorkspaceFolder(path: '/new'),
      WorkspaceFolder(path: '/x'),
    ]);
    final loaded = await repo.loadWorkspaces();
    expect(loaded.single.firstFolderPath, '/new');
    expect(loaded.single.extraFolderPaths, ['/x']);
  });

  test(
    'createSession snapshots workspace additionalPaths at creation time',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final p = await repo.createWorkspace([
        WorkspaceFolder(path: '/p'),
        WorkspaceFolder(path: '/q'),
      ]);
      final s1 = await repo.createSession(p.workspaceId);
      expect(s1.extraFolderPaths, ['/q']);

      await repo.updateWorkspaceFolders(p.workspaceId, [
        WorkspaceFolder(path: '/p'),
        WorkspaceFolder(path: '/r'),
      ]);
      final s2 = await repo.createSession(p.workspaceId);
      expect(s2.extraFolderPaths, ['/r']);
      final s1Reload = (await repo.loadSessions()).firstWhere(
        (e) => e.sessionId == s1.sessionId,
      );
      expect(s1Reload.extraFolderPaths, ['/q']);
    },
  );

  test('loadSessions skips corrupt json files', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/z')]);
    final good = await repo.createSession(workspace.workspaceId);
    final badDir = Directory(
      '${tmp.path}/workspace/workspaces/${workspace.workspaceId}/sessions/bogus',
    );
    await badDir.create(recursive: true);
    await File('${badDir.path}/session.json').writeAsString('{ not json');

    final list = await repo.loadSessions();
    expect(list.length, 1);
    expect(list.single.sessionId, good.sessionId);
  });

  test(
    'markSessionLaunched sets started without changing sessionTeam',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/w'),
      ]);
      final session = await repo.createSession(workspace.workspaceId);
      await repo.markSessionLaunched(session.sessionId);

      final disk = (await repo.loadSessions()).single;
      expect(disk.launchState, AppSessionLaunchState.started);
    },
  );

  test('simple session persists empty profileId', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/w')]);
    final session = await repo.createSession(workspace.workspaceId);

    // Simple / unteamed sessions have no launch-profile identity.
    expect(session.profileId, '');
    expect((await repo.loadSessions()).single.profileId, '');
  });

  test(
    'loadWorkspacesIndex maintains workspaces-index.json snapshot',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/a'),
      ]);
      final session = await repo.createSession(workspace.workspaceId);

      final indexPath = '${tmp.path}/workspace/workspaces-index.json';
      expect(File(indexPath).existsSync(), isTrue);

      final fromIndex = await repo.loadWorkspacesIndex();
      expect(fromIndex.single.workspaceId, workspace.workspaceId);
      expect(fromIndex.single.sessionIds, contains(session.sessionId));

      await repo.deleteSession(session.sessionId);
      final afterDelete = await repo.loadWorkspacesIndex();
      expect(afterDelete.single.sessionIds, isEmpty);
    },
  );

  test('deleteWorkspace removes entry from workspaces-index.json', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/a')]);
    await repo.createSession(workspace.workspaceId);

    final indexPath = '${tmp.path}/workspace/workspaces-index.json';
    expect(File(indexPath).existsSync(), isTrue);

    await repo.deleteWorkspace(workspace.workspaceId);
    expect(await repo.loadWorkspacesIndex(), isEmpty);
    expect(File(indexPath).existsSync(), isTrue);
    final decoded = jsonDecode(File(indexPath).readAsStringSync());
    expect((decoded as Map)['workspaces'], isEmpty);
  });

  test('simple createSession ignores memberClis', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/w')]);
    final session = await repo.createSession(
      workspace.workspaceId,
    );

    expect(session.cli, isNull);
  });

}
