import 'dart:io';

import 'package:teampilot/services/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('basePath throws before init', () {
    AppPathsBootstrapper.resetForTesting();
    expect(
      () => AppPathsBootstrapper.current.basePath,
      throwsA(isA<StateError>()),
    );
  });

  group('initialized paths', () {
    late Directory appDataRoot;

    setUp(() async {
      appDataRoot = await Directory.systemTemp.createTemp('app_storage_test_');
      AppPathsBootstrapper.setCurrentForTesting(AppPaths(appDataRoot.path));
    });

    tearDown(() async {
      AppPathsBootstrapper.resetForTesting();
      if (await appDataRoot.exists()) {
        await appDataRoot.delete(recursive: true);
      }
    });

    test('launchProfilesDir sits next to basePath', () {
      expect(
        AppPathsBootstrapper.current.launchProfilesDir,
        p.join(appDataRoot.path, 'launch-profiles'),
      );
    });

    test('cliDefaultsDir sits under basePath', () {
      expect(
        AppPathsBootstrapper.current.cliDefaultsDir,
        p.join(appDataRoot.path, 'cli-defaults'),
      );
    });

    test('workspaceDir sits under basePath', () {
      expect(
        AppPathsBootstrapper.current.workspaceDir,
        p.join(appDataRoot.path, 'workspace'),
      );
    });

    test('teamPilot teampilotRoot helpers join under root', () {
      const root = '/remote/.local/share/com.hhoa.teampilot';
      expect(
        AppPaths.launchProfilesDirForTeampilotRoot(root),
        '$root/launch-profiles',
      );
      expect(AppPaths.workspaceDirForTeampilotRoot(root), '$root/workspace');
      expect(
        AppPaths.cliDefaultsDirForTeampilotRoot(root),
        '$root/cli-defaults',
      );
      expect(
        AppPaths.homeWorkspaceOpenWorkspacesJsonForTeampilotRoot(root),
        '$root/ui/open-workspace-tabs.json',
      );
    });

    test(
      'defaultTeampilotAppDataDirForHome uses POSIX separators for WSL home',
      () {
        expect(
          AppPaths.defaultTeampilotAppDataDirForHome('/home/hhoa'),
          '/home/hhoa/.local/share/com.hhoa.teampilot',
        );
        expect(
          AppPaths.defaultTeampilotAppDataDirForHome('/home/hhoa'),
          isNot(contains(r'\')),
        );
      },
    );
  });
}
