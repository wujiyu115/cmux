import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/vcs/vcs_detector.dart';

import '../../support/in_memory_filesystem.dart';

/// Builds the 2003VB12-style layout: a git repo whose `common/` is a
/// `.svn` one level deeper).
InMemoryFilesystem _nestedLayout() {
  final fs = InMemoryFilesystem();
  void dir(String path) => fs.directories.add(path);
  // git repo root + content (parent chain included so listDir sees them)
  dir('/work/2003VB12/.git');
  dir('/work/2003VB12/3rd');
  fs.files['/work/2003VB12/Makefile'] = 'all:';
  // svn working copy under common/
  dir('/work/2003VB12/common');
  dir('/work/2003VB12/common/.svn');
  dir('/work/2003VB12/common/convertor');
  fs.files['/work/2003VB12/common/XmlParser.lua'] = 'return 1';
  // svn externals: own .svn inside convertor
  dir('/work/2003VB12/common/convertor/SpriteData');
  dir('/work/2003VB12/common/convertor/SpriteData/.svn');
  return fs;
}

InMemoryFilesystem _deepSvnLayout() {
  final fs = InMemoryFilesystem();
  void dir(String path) => fs.directories.add(path);
  dir('/repo');
  dir('/repo/.git');
  dir('/repo/a');
  dir('/repo/a/b');
  dir('/repo/a/b/c');
  // Deeper levels are added per-test: depth 2 (a/b) is the last scanned
  // level with the default maxSvnScanDepth of 2.
  return fs;
}

InMemoryFilesystem _windowsNestedLayout() {
  final fs = InMemoryFilesystem(
    pathContext: p.Context(style: p.Style.windows),
  );
  void dir(String path) => fs.directories.add(path);
  dir(r'D:\proj');
  dir(r'D:\proj\.git');
  dir(r'D:\proj\common');
  dir(r'D:\proj\common\.svn');
  return fs;
}

void main() {
  group('VcsDetector.probe', () {
    test('nested svn-in-git yields both areas, svn deeper', () async {
      final fs = _nestedLayout();
      final result = await VcsDetector().probe('/work/2003VB12', fs);

      expect(result.areas, hasLength(2));
      expect(
        result.areas.first,
        const VcsArea(kind: VcsKind.git, root: '/work/2003VB12'),
      );
      expect(
        result.areas.last,
        const VcsArea(kind: VcsKind.svn, root: '/work/2003VB12/common'),
      );
    });

    test('externals dirs are not separate areas', () async {
      final fs = _nestedLayout();
      final result = await VcsDetector().probe('/work/2003VB12', fs);
      // SpriteData/.svn exists but must fold into the common area, not add
      // a third one.
      expect(result.areas.where((a) => a.kind == VcsKind.svn), hasLength(1));
    });

    test('pure git folder yields one git area', () async {
      final fs = InMemoryFilesystem();
      fs.directories
        ..add('/repo/.git')
        ..add('/repo/lib');
      final result = await VcsDetector().probe('/repo', fs);
      expect(
        result.areas,
        [const VcsArea(kind: VcsKind.git, root: '/repo')],
      );
    });

    test('pure svn folder yields one svn area', () async {
      final fs = InMemoryFilesystem();
      fs.directories
        ..add('/work/common_master/.svn')
        ..add('/work/common_master/convertor');
      final result = await VcsDetector().probe('/work/common_master', fs);
      expect(
        result.areas,
        [const VcsArea(kind: VcsKind.svn, root: '/work/common_master')],
      );
    });

    test('workspace folder inside a subdirectory still finds the repo', () async {
      final fs = InMemoryFilesystem();
      fs.directories
        ..add('/repo/.git')
        ..add('/repo/client/lib');
      final result = await VcsDetector().probe('/repo/client/lib', fs);
      expect(
        result.areas,
        [const VcsArea(kind: VcsKind.git, root: '/repo')],
      );
    });

    test('git worktree .git file marker is accepted', () async {
      final fs = InMemoryFilesystem();
      fs.directories.add('/wt');
      fs.files['/wt/.git'] = 'gitdir: /repo/.git/worktrees/wt';
      final result = await VcsDetector().probe('/wt', fs);
      expect(
        result.areas,
        [const VcsArea(kind: VcsKind.git, root: '/wt')],
      );
    });

    test('no VCS markers yields empty result', () async {
      final fs = InMemoryFilesystem();
      fs.directories.add('/plain/dir');
      final result = await VcsDetector().probe('/plain/dir', fs);
      expect(result.isEmpty, isTrue);
    });

    test('svn checkout below the max scan depth is not found', () async {
      final fs = _deepSvnLayout();
      // 3 levels deep (a/b/c) with default maxSvnScanDepth 2: `a` is
      // scanned, its children are beyond the boundary.
      fs.directories
        ..add('/repo/a/b')
        ..add('/repo/a/b/c')
        ..add('/repo/a/b/c/.svn');
      final result = await VcsDetector().probe('/repo', fs);
      expect(result.areas, [const VcsArea(kind: VcsKind.git, root: '/repo')]);
    });

    test('svn checkout exactly at the max scan depth is found', () async {
      final fs = _deepSvnLayout();
      // a/b is depth 2 — the last scanned level.
      fs.directories
        ..add('/repo/a/b')
        ..add('/repo/a/b/.svn');
      final result = await VcsDetector().probe('/repo', fs);
      expect(
        result.areas,
        contains(const VcsArea(kind: VcsKind.svn, root: '/repo/a/b')),
      );
    });

    test('windows-style paths resolve through the path context', () async {
      final fs = _windowsNestedLayout();
      final result = await VcsDetector().probe(r'D:\proj', fs);
      expect(result.areas, hasLength(2));
      expect(
        result.areaForPath(r'D:\proj\common\cfg.lua')?.kind,
        VcsKind.svn,
      );
      expect(result.areaForPath(r'D:\proj\main.dart')?.kind, VcsKind.git);
    });
  });

  group('VcsProbeResult.areaForPath', () {
    test('nested layout routes common files to svn, others to git', () async {
      final fs = _nestedLayout();
      final result = await VcsDetector().probe('/work/2003VB12', fs);

      expect(
        result.areaForPath('/work/2003VB12/Makefile'),
        const VcsArea(kind: VcsKind.git, root: '/work/2003VB12'),
      );
      expect(
        result.areaForPath('/work/2003VB12/common/XmlParser.lua'),
        const VcsArea(kind: VcsKind.svn, root: '/work/2003VB12/common'),
      );
      // External content still routes to the enclosing svn area.
      expect(
        result.areaForPath(
          '/work/2003VB12/common/convertor/SpriteData/x.png',
        )?.root,
        '/work/2003VB12/common',
      );
      expect(result.areaForPath('/outside/file.txt'), isNull);
      expect(result.areaForPath('/work/2003VB12')?.kind, VcsKind.git);
    });
  });
}
