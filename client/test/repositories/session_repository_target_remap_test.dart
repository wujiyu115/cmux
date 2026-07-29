import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/workspace/target_liveness.dart';

class _FixedLiveness implements TargetLiveness {
  _FixedLiveness(this._alive);

  final Set<String> _alive;

  @override
  Future<bool> isAlive(String targetId) async => _alive.contains(targetId);
}

void main() {
  test('remapWorkspaceTarget throws when from target is unused', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_remap_unused_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/local'),
    ]);

    expect(
      () => repo.remapWorkspaceTarget(
        ws.workspaceId,
        fromTargetId: 'ssh:gone',
        toTargetId: 'ssh:new',
        liveness: _FixedLiveness({'ssh:new', 'local'}),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Nothing to remap for target "ssh:gone"',
        ),
      ),
    );
  });
}
