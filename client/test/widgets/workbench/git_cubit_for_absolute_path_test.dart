import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/widgets/workbench/file_diff_surface_toggle.dart';

/// Mirrors SftpFilesystem / WslFilesystem: always posix.
class _PosixFs implements Filesystem {
  @override
  final p.Context pathContext = p.Context(style: p.Style.posix);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Mirrors LocalFilesystem: host-default path context (windows on Windows).
class _HostFs implements Filesystem {
  @override
  final p.Context pathContext = p.context;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RuntimeContext _ctx(Filesystem fs, RuntimeTarget target) => RuntimeContext(
  target: target,
  filesystem: fs,
  home: '/home',
  cwd: '/home',
  appDataRoot: '/home/.local/share/com.hhoa.teampilot',
  paths: AppPaths('/home/.local/share/com.hhoa.teampilot'),
);

/// Probe widget: resolves the cubit for [path]; resolution is proven by which
/// roots the recording factory below received (the cubit itself stays inert —
/// resolution never triggers a git subprocess).
class _Probe extends StatelessWidget {
  const _Probe({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    gitCubitForAbsolutePath(context, path);
    return const SizedBox.shrink();
  }
}

Widget _shell(WorkspaceToolsScopeState scope, String path) {
  return RepositoryProvider<GitRepoStore>(
    create: (_) => GitRepoStore(cubitFactory: (root, workContext) {
      roots.add(root);
      return GitCubit(service: GitService());
    }),
    child: WorkspaceToolsScope(
      state: scope,
      child: MaterialApp(home: Scaffold(body: _Probe(path: path))),
    ),
  );
}

late List<String> roots;

void main() {
  // Regression: on a Windows host the old host-default p.Context() rewrote
  // posix SSH/WSL roots to `\home\…`, which remote `git -C` rejects — the
  // blame toggle then toasted "not a Git repository" for a real repo.

  testWidgets('ssh posix root reaches the cubit unmangled', (tester) async {
    roots = <String>[];
    await tester.pumpWidget(
      _shell(
        WorkspaceToolsScopeState(
          tools: WorkspaceToolsContext(
            targetId: 'ssh:p1',
            context: _ctx(_PosixFs(), RuntimeTarget.ssh('p1', label: 'box')),
          ),
          roots: const ['/home/ejoy/work/2003VB12'],
          resolving: false,
        ),
        '/home/ejoy/work/2003VB12/lualib/activity_api.lua',
      ),
    );

    expect(roots, ['/home/ejoy/work/2003VB12']);
  });

  testWidgets('windows-style root still resolves on a native target',
      (tester) async {
    roots = <String>[];
    await tester.pumpWidget(
      _shell(
        WorkspaceToolsScopeState(
          tools: WorkspaceToolsContext(
            targetId: 'local',
            context: _ctx(_HostFs(), RuntimeTarget.local()),
          ),
          // A native Windows target carries windows-style roots
          // (LocalFilesystem.pathContext == host default).
          roots: const [r'D:\git\teampilot'],
          resolving: false,
        ),
        r'D:\git\teampilot\client\lib\main.dart',
      ),
    );

    expect(roots, [r'D:\git\teampilot']);
  });

  testWidgets('longest containing root wins (posix nesting)', (tester) async {
    roots = <String>[];
    await tester.pumpWidget(
      _shell(
        WorkspaceToolsScopeState(
          tools: WorkspaceToolsContext(
            targetId: 'ssh:p1',
            context: _ctx(_PosixFs(), RuntimeTarget.ssh('p1', label: 'box')),
          ),
          roots: const ['/home/ejoy/work', '/home/ejoy/work/2003VB12'],
          resolving: false,
        ),
        '/home/ejoy/work/2003VB12/lualib/a.lua',
      ),
    );

    expect(roots, ['/home/ejoy/work/2003VB12']);
  });

  testWidgets('path outside every root resolves to no cubit', (tester) async {
    roots = <String>[];
    await tester.pumpWidget(
      _shell(
        WorkspaceToolsScopeState(
          tools: WorkspaceToolsContext(
            targetId: 'ssh:p1',
            context: _ctx(_PosixFs(), RuntimeTarget.ssh('p1', label: 'box')),
          ),
          roots: const ['/home/ejoy/other'],
          resolving: false,
        ),
        '/home/ejoy/work/2003VB12/lualib/a.lua',
      ),
    );

    expect(roots, isEmpty);
  });
}
