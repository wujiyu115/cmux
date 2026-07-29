import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_topology.dart';

void main() {
  group('workspaceTopologyOf', () {
    test('empty defaults to local', () {
      expect(workspaceTopologyOf(const []), WorkspaceTopology.local);
    });

    test('all local folders', () {
      expect(
        workspaceTopologyOf([
          const WorkspaceFolder(path: '/a'),
          const WorkspaceFolder(path: '/b'),
        ]),
        WorkspaceTopology.local,
      );
    });

    test('all same ssh target is remote', () {
      expect(
        workspaceTopologyOf([
          const WorkspaceFolder(path: '/a', targetId: 'ssh:p1'),
          const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
        ]),
        WorkspaceTopology.remote,
      );
    });

    test('distinct targets is mixed', () {
      expect(
        workspaceTopologyOf([
          const WorkspaceFolder(path: '/a'),
          const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
        ]),
        WorkspaceTopology.mixed,
      );
    });

    test('same path on local and remote disambiguates via target id', () {
      const folders = [
        WorkspaceFolder(path: '/repo'),
        WorkspaceFolder(path: '/repo', targetId: 'ssh:p1'),
      ];
      expect(
        memberWorkDirsForTarget(folders, 'ssh:p1').workingDirectory,
        '/repo',
      );
      expect(
        memberWorkDirsForTarget(folders, 'local').workingDirectory,
        '/repo',
      );
    });

    test('personalWorkDirsForPrimaryPath keeps add-dirs on same target only', () {
      const folders = [
        WorkspaceFolder(path: '/local', targetId: 'local'),
        WorkspaceFolder(path: '/local-extra', targetId: 'local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ];
      final local = personalWorkDirsForPrimaryPath(folders, '/local');
      expect(local.workingDirectory, '/local');
      expect(local.addDirs, ['/local-extra']);

      final remote = personalWorkDirsForPrimaryPath(folders, '/remote');
      expect(remote.workingDirectory, '/remote');
      expect(remote.addDirs, isEmpty);
    });
  });
}
