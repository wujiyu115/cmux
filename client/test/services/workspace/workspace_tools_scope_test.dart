import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';

import '../../support/in_memory_filesystem.dart';

RuntimeContext _ctx(Filesystem fs) => RuntimeContext(
  target: RuntimeTarget.local(),
  filesystem: fs,
  home: '/',
  cwd: '/',
  appDataRoot: '/',
  paths: AppPaths('/'),
);

WorkspaceTargetSlice _slice(String targetId, Filesystem fs) =>
    WorkspaceTargetSlice(
      targetId: targetId,
      tools: WorkspaceToolsContext(targetId: targetId, context: _ctx(fs)),
      roots: const [],
    );

void main() {
  group('WorkspaceToolsScopeState.filesystemForTarget', () {
    test('returns the filesystem of the matching target slice', () {
      final local = InMemoryFilesystem();
      final wsl = InMemoryFilesystem();
      final state = WorkspaceToolsScopeState(
        targetSlices: [_slice('local', local), _slice('wsl:Ubuntu', wsl)],
        resolving: false,
      );

      expect(state.filesystemForTarget('local'), same(local));
      expect(state.filesystemForTarget('wsl:Ubuntu'), same(wsl));
    });

    test('returns null for a target that is not resolved', () {
      final state = WorkspaceToolsScopeState(
        targetSlices: [_slice('local', InMemoryFilesystem())],
        resolving: false,
      );

      expect(state.filesystemForTarget('ssh:down'), isNull);
    });

    test('returns null while nothing has resolved yet', () {
      const state = WorkspaceToolsScopeState();

      expect(state.filesystemForTarget('local'), isNull);
    });
  });

  group('WorkspaceToolsScopeState.runtimeContextForTarget', () {
    test('returns the context of the matching target slice', () {
      final localCtx = _ctx(InMemoryFilesystem());
      final wslCtx = _ctx(InMemoryFilesystem());
      final state = WorkspaceToolsScopeState(
        targetSlices: [
          WorkspaceTargetSlice(
            targetId: 'local',
            tools: WorkspaceToolsContext(targetId: 'local', context: localCtx),
            roots: const [],
          ),
          WorkspaceTargetSlice(
            targetId: 'wsl:Ubuntu',
            tools: WorkspaceToolsContext(
              targetId: 'wsl:Ubuntu',
              context: wslCtx,
            ),
            roots: const [],
          ),
        ],
        resolving: false,
      );

      expect(state.runtimeContextForTarget('local'), same(localCtx));
      expect(state.runtimeContextForTarget('wsl:Ubuntu'), same(wslCtx));
    });

    test('returns null for a target that is not resolved', () {
      final state = WorkspaceToolsScopeState(
        targetSlices: [
          WorkspaceTargetSlice(
            targetId: 'local',
            tools: WorkspaceToolsContext(
              targetId: 'local',
              context: _ctx(InMemoryFilesystem()),
            ),
            roots: const [],
          ),
        ],
        resolving: false,
      );

      expect(state.runtimeContextForTarget('ssh:down'), isNull);
    });
  });
}
