import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/vcs/vcs_detector.dart';

/// Mirrors the shell-backed bulk primitive (SftpFilesystem/WslFilesystem):
/// `findNestedDirsNamed` answers from a canned `find -L` result and stat
/// follows links — the semantics the real backends have. The 2003VB12
/// layout: `/work/2003VB12/common` is a symlink to `../common_master`,
/// whose `.svn` is the svn working copy (plus externals below it).
class _BulkFindFs implements Filesystem {
  @override
  final pathContext = p.Context(style: p.Style.posix);

  final dirs = <String>{
    '/work/2003VB12/.git',
    '/work/2003VB12/lualib',
    '/work/common_master/.svn',
    '/work/common_master/convertor/SpriteData/.svn',
  };
  final links = <String, String>{
    '/work/2003VB12/common': '../common_master',
  };

  /// What `find -L /work/2003VB12 -name .svn -type d -prune -print` prints.
  List<String> get findResult => [
        '/work/2003VB12/common/.svn',
        '/work/2003VB12/common/convertor/SpriteData/.svn',
      ];

  @override
  Future<List<String>?> findNestedDirsNamed(String root, String name) async =>
      root == '/work/2003VB12' && name == '.svn' ? findResult : null;

  @override
  Future<FsStat> stat(String path) async {
    var cur = path;
    final rest = <String>[];
    while (cur != '/' && cur.isNotEmpty) {
      if (dirs.contains(cur)) return const FsStat(kind: FsEntityKind.directory);
      final link = links[cur];
      if (link != null) {
        final base = pathContext.dirname(cur);
        final target = pathContext.normalize(pathContext.join(base, link));
        final tail = rest.reversed.join('/');
        return stat(tail.isEmpty ? target : '$target/$tail');
      }
      rest.add(pathContext.basename(cur));
      cur = pathContext.dirname(cur);
    }
    return const FsStat(kind: FsEntityKind.notFound);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('bulk find path discovers the symlinked svn wc at the link path',
      () async {
    final fs = _BulkFindFs();
    final result = await VcsDetector().probe('/work/2003VB12', fs);

    expect(
      result.areas,
      [
        const VcsArea(kind: VcsKind.git, root: '/work/2003VB12'),
        const VcsArea(kind: VcsKind.svn, root: '/work/2003VB12/common'),
      ],
    );
  });

  test('svn files under the link route to the svn area', () async {
    final fs = _BulkFindFs();
    final result = await VcsDetector().probe('/work/2003VB12', fs);

    expect(
      result.areaForPath('/work/2003VB12/common/convertor/x.lua')?.kind,
      VcsKind.svn,
    );
    expect(
      result.areaForPath('/work/2003VB12/lualib/a.lua')?.kind,
      VcsKind.git,
    );
  });
}
