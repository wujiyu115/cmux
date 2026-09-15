import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_index_dirs.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/quick_open/quick_open_index.dart';
import 'package:teampilot/services/quick_open/quick_open_prewarm.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

RuntimeContext _ctx(Filesystem fs) => RuntimeContext(
  target: RuntimeTarget.local(),
  filesystem: fs,
  home: '/',
  cwd: '/',
  appDataRoot: '/',
  paths: AppPaths('/'),
);

WorkspaceToolsScopeState _state({
  required String targetId,
  required Filesystem fs,
  List<String> roots = const [],
}) {
  final tools = WorkspaceToolsContext(targetId: targetId, context: _ctx(fs));
  return WorkspaceToolsScopeState(
    tools: tools,
    roots: roots,
    targetSlices: [
      WorkspaceTargetSlice(targetId: targetId, tools: tools, roots: roots),
    ],
    resolving: false,
  );
}

Workspace _workspace({
  List<WorkspaceFolder> folders = const [],
  WorkspaceIndexDirs indexDirRules = const WorkspaceIndexDirs.empty(),
}) => Workspace(
  workspaceId: 'w',
  folders: folders,
  createdAt: 0,
  indexDirRules: indexDirRules,
);

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('resolveQuickOpenPlane', () {
    test('unions target folders and scope roots, drops others and nested', () {
      final localFs = InMemoryFilesystem();
      final state = _state(targetId: 'local', fs: localFs, roots: ['/repo/lib']);
      final workspace = _workspace(folders: [
        WorkspaceFolder(path: '/repo'),
        WorkspaceFolder(path: '/other', targetId: 'wsl:Ubuntu'),
        WorkspaceFolder(path: '  '),
      ]);

      final plane = resolveQuickOpenPlane(
        workspace: workspace,
        scopeState: state,
      );

      expect(plane.activeTargetId, 'local');
      expect(plane.targetContext, isNotNull);
      expect(plane.filesystem, same(localFs));
      // '/repo/lib' nests inside folder '/repo', so it collapses away.
      expect(plane.indexRoots, ['/repo']);
    });

    test('falls back to the first folder target when tools is null', () {
      final wslFs = InMemoryFilesystem();
      final state = WorkspaceToolsScopeState(
        targetSlices: [
          WorkspaceTargetSlice(
            targetId: 'wsl:Ubuntu',
            tools: WorkspaceToolsContext(
              targetId: 'wsl:Ubuntu',
              context: _ctx(wslFs),
            ),
            roots: const [],
          ),
        ],
        resolving: true,
      );
      final workspace = _workspace(folders: [
        WorkspaceFolder(path: '/repo', targetId: 'wsl:Ubuntu'),
      ]);

      final plane = resolveQuickOpenPlane(
        workspace: workspace,
        scopeState: state,
      );

      expect(plane.activeTargetId, 'wsl:Ubuntu');
      expect(plane.filesystem, same(wslFs));
      expect(plane.targetContext, isNotNull);
      expect(plane.indexRoots, ['/repo']);
    });

    test('no folders and no tools falls back to the local AppStorage plane', () {
      final plane = resolveQuickOpenPlane(
        workspace: _workspace(),
        scopeState: const WorkspaceToolsScopeState(),
      );

      expect(plane.activeTargetId, 'local');
      expect(plane.targetContext, isNull);
      expect(plane.filesystem, same(AppStorage.fs));
      expect(plane.indexRoots, isEmpty);
    });

    test('empty roots fall back to the workspace first folder path', () {
      final wslFs = InMemoryFilesystem();
      // Active plane switched to wsl while the only folder is local.
      final state = _state(targetId: 'wsl:Ubuntu', fs: wslFs);
      final workspace = _workspace(folders: [WorkspaceFolder(path: '/repo')]);

      final plane = resolveQuickOpenPlane(
        workspace: workspace,
        scopeState: state,
      );

      expect(plane.indexRoots, ['/repo']);
    });
  });

  group('prewarmQuickOpenIndex', () {
    test('lists each root once with the workspace dir rules', () async {
      final repo = p.join(AppStorage.cwd, 'repo');
      final wt = p.join(AppStorage.cwd, 'wt');
      await AppStorage.fs.ensureDir(repo);
      await AppStorage.fs.ensureDir(wt);

      var listings = 0;
      final listedRoots = <String>[];
      final registry = QuickOpenIndexRegistry(
        lister: (path) {
          listings++;
          listedRoots.add(path);
          return Future.value([
            FsDirEntry(name: 'README.md', isDirectory: false),
            FsDirEntry(name: 'lib/main.dart', isDirectory: false),
          ]);
        },
      );
      // Tools resolved but the target context is not (unreachable-target
      // shape): the plane falls back to AppStorage.fs and installs no git
      // runner, so the listing stays fully in-memory.
      final state = WorkspaceToolsScopeState(
        tools: WorkspaceToolsContext(
          targetId: 'local',
          context: _ctx(InMemoryFilesystem()),
        ),
        roots: [repo, wt],
        resolving: false,
      );
      final workspace = _workspace(
        folders: [WorkspaceFolder(path: repo), WorkspaceFolder(path: wt)],
        indexDirRules: WorkspaceIndexDirs(excluded: ['lib']),
      );

      await prewarmQuickOpenIndex(
        workspace: workspace,
        scopeState: state,
        registry: registry,
      );

      expect(listings, 2);
      expect(listedRoots, containsAll([repo, wt]));
      expect(registry.gitRunner, isNull);
      final index = await registry.latestIndex(
        AppStorage.fs,
        repo,
        dirs: WorkspaceIndexDirs(excluded: ['lib']),
      );
      expect(index!.files.map((e) => e.relativePath), ['README.md']);
    });

    test('points the registry runner at the active plane', () async {
      final localFs = InMemoryFilesystem();
      final state = _state(targetId: 'local', fs: localFs);
      final registry = QuickOpenIndexRegistry();

      // Folderless workspace: nothing to warm, but the runner still follows
      // the plane.
      await prewarmQuickOpenIndex(
        workspace: _workspace(),
        scopeState: state,
        registry: registry,
      );

      expect(registry.gitRunner, isA<LocalGitCommandRunner>());
    });

    test('is a no-op before the tools plane resolves', () async {
      var listings = 0;
      final registry = QuickOpenIndexRegistry(
        lister: (path) {
          listings++;
          return Future.value(const <FsDirEntry>[]);
        },
      );
      final workspace = _workspace(folders: [WorkspaceFolder(path: '/repo')]);

      await prewarmQuickOpenIndex(
        workspace: workspace,
        scopeState: const WorkspaceToolsScopeState(resolving: true),
        registry: registry,
      );

      expect(listings, 0);
      expect(registry.gitRunner, isNull);
    });

    test('listing failures are swallowed per root', () async {
      final repo = p.join(AppStorage.cwd, 'repo');
      final wt = p.join(AppStorage.cwd, 'wt');
      await AppStorage.fs.ensureDir(repo);
      await AppStorage.fs.ensureDir(wt);

      var listings = 0;
      final registry = QuickOpenIndexRegistry(
        lister: (path) {
          listings++;
          throw StateError('boom');
        },
      );
      final state = WorkspaceToolsScopeState(
        tools: WorkspaceToolsContext(
          targetId: 'local',
          context: _ctx(InMemoryFilesystem()),
        ),
        roots: [repo, wt],
        resolving: false,
      );
      final workspace = _workspace(folders: [
        WorkspaceFolder(path: repo),
        WorkspaceFolder(path: wt),
      ]);

      await prewarmQuickOpenIndex(
        workspace: workspace,
        scopeState: state,
        registry: registry,
      );

      // Both roots were attempted despite the first one failing.
      expect(listings, 2);
    });
  });
}
