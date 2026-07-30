import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/services/io/wsl_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

RuntimeContext _wslContext() {
  return RuntimeContext(
    target: RuntimeTarget.wsl('Ubuntu'),
    filesystem: WslFilesystem(distro: 'Ubuntu'),
    home: '/home/ejoy',
    cwd: '/home/ejoy',
    appDataRoot: '/home/ejoy/.local/share/com.hhoa.teampilot',
    paths: AppPaths('/home/ejoy/.local/share/com.hhoa.teampilot'),
  );
}

void main() {
  test('cubitFor keeps a WSL posix root posix (no backslash rewrite)', () {
    final roots = <String>[];
    final store = GitRepoStore(
      cubitFactory: (root, workContext) {
        roots.add(root);
        return GitCubit(service: GitService());
      },
    );
    addTearDown(store.dispose);

    store.cubitFor('/home/ejoy/git/Nexterm', workContext: _wslContext());

    // Host is Windows; the default p.Context() would rewrite this to
    // `\home\ejoy\git\Nexterm`, which `git -C` inside WSL rejects.
    expect(roots.single, '/home/ejoy/git/Nexterm');
    expect(roots.single, isNot(contains('\\')));
  });

  test('cubitFor caches per normalized root and target', () {
    var built = 0;
    final store = GitRepoStore(
      cubitFactory: (root, workContext) {
        built++;
        return GitCubit(service: GitService());
      },
    );
    addTearDown(store.dispose);

    final ctx = _wslContext();
    store.cubitFor('/home/ejoy/git/Nexterm', workContext: ctx);
    store.cubitFor('/home/ejoy/git/Nexterm/', workContext: ctx);

    expect(built, 1);
  });
}
