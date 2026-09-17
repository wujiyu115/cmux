import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_changes_visible_rows.dart';

void main() {
  test('visibleGitChangesRows nests files under expanded folders', () {
    const changes = [
      GitFileChange(
        path: 'src/utils/foo.dart',
        kind: GitChangeKind.modified,
        staged: false,
      ),
      GitFileChange(
        path: 'readme.md',
        kind: GitChangeKind.modified,
        staged: false,
      ),
    ];

    final rows = visibleGitChangesRows(
      changes: changes,
      expandedFolderPaths: {'src', 'src/utils'},
    );

    expect(
      rows.map((r) => r.isFolder ? 'D:${r.name}' : 'F:${r.change!.path}'),
      ['D:src', 'D:utils', 'F:src/utils/foo.dart', 'F:readme.md'],
    );
  });

  test('visibleGitChangesRows hides nested files when folder collapsed', () {
    const changes = [
      GitFileChange(
        path: 'src/main.dart',
        kind: GitChangeKind.modified,
        staged: false,
      ),
    ];

    final rows = visibleGitChangesRows(
      changes: changes,
      expandedFolderPaths: {},
    );

    expect(rows, [
      isA<GitChangesVisibleRow>().having((r) => r.isFolder, 'folder', isTrue),
    ]);
  });

  test('gitChangesMinContentWidth accounts for depth and trailing actions', () {
    const fileStyle = TextStyle(fontSize: 12);
    const folderStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
    final rows = [
      const GitChangesVisibleRow.folder(
        folderPath: 'src',
        name: 'src',
        depth: 0,
      ),
      GitChangesVisibleRow.file(
        change: const GitFileChange(
          path: 'src/very-long-filename.dart',
          kind: GitChangeKind.modified,
          staged: false,
        ),
        depth: 1,
      ),
    ];

    final width = gitChangesMinContentWidth(
      rows: rows,
      fileLabelStyle: fileStyle,
      folderLabelStyle: folderStyle,
    );
    expect(width, greaterThan(200));
  });

  test('gitChangesDefaultExpandedFolders includes all directory prefixes', () {
    const changes = [
      GitFileChange(
        path: 'src/utils/foo.dart',
        kind: GitChangeKind.modified,
        staged: false,
      ),
    ];

    expect(gitChangesDefaultExpandedFolders(changes), {'src', 'src/utils'});
  });

  test('visibleGitChangesTreeViewData splits staged and unstaged rows', () {
    const staged = [
      GitFileChange(
        path: 'lib/a.dart',
        kind: GitChangeKind.modified,
        staged: true,
      ),
    ];
    const unstaged = [
      GitFileChange(
        path: 'lib/b.dart',
        kind: GitChangeKind.modified,
        staged: false,
      ),
    ];

    final data = visibleGitChangesTreeViewData(
      staged: staged,
      unstaged: unstaged,
      expandedFolderPaths: const {'lib'},
    );

    expect(data.stagedRows.any((r) => r.change?.path == 'lib/a.dart'), isTrue);
    expect(
      data.unstagedRows.any((r) => r.change?.path == 'lib/b.dart'),
      isTrue,
    );
  });

  test('gitChangesMinContentWidth samples rows on large trees', () {
    const fileStyle = TextStyle(fontSize: 12);
    const folderStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
    final rows = [
      for (var i = 0; i < 64; i++)
        GitChangesVisibleRow.file(
          change: GitFileChange(
            path: 'dir/file_$i.txt',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          depth: 1,
        ),
      const GitChangesVisibleRow.file(
        change: GitFileChange(
          path: 'dir/zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz.dart',
          kind: GitChangeKind.modified,
          staged: false,
        ),
        depth: 1,
      ),
    ];

    final width = gitChangesMinContentWidth(
      rows: rows,
      fileLabelStyle: fileStyle,
      folderLabelStyle: folderStyle,
    );
    expect(width, greaterThan(300));
  });

  test('visibleGitChangesFlatViewData emits depth-0 file rows sorted by path', () {
    const changes = [
      GitFileChange(
        path: 'src/utils/foo.dart',
        kind: GitChangeKind.modified,
        staged: false,
      ),
      GitFileChange(
        path: 'readme.md',
        kind: GitChangeKind.modified,
        staged: false,
      ),
      GitFileChange(
        path: 'src/alpha.dart',
        kind: GitChangeKind.modified,
        staged: false,
      ),
    ];

    final data = visibleGitChangesFlatViewData(
      staged: const [],
      unstaged: changes,
    );

    expect(
      data.unstagedRows.map((r) => (r.change!.path, r.depth, r.isFolder)),
      [
        ('readme.md', 0, false),
        ('src/alpha.dart', 0, false),
        ('src/utils/foo.dart', 0, false),
      ],
    );
    expect(data.stagedRows, isEmpty);
  });

  test('visibleGitChangesFlatViewData sorts staged and unstaged separately', () {
    const staged = [
      GitFileChange(path: 'lib/b.dart', kind: GitChangeKind.modified, staged: true),
      GitFileChange(path: 'lib/a.dart', kind: GitChangeKind.modified, staged: true),
    ];
    const unstaged = [
      GitFileChange(path: 'lib/d.dart', kind: GitChangeKind.modified, staged: false),
      GitFileChange(path: 'lib/c.dart', kind: GitChangeKind.modified, staged: false),
    ];

    final data = visibleGitChangesFlatViewData(staged: staged, unstaged: unstaged);

    expect(data.stagedRows.map((r) => r.change!.path), [
      'lib/a.dart',
      'lib/b.dart',
    ]);
    expect(data.unstagedRows.map((r) => r.change!.path), [
      'lib/c.dart',
      'lib/d.dart',
    ]);
  });

  test('gitChangesMinContentWidth measures full paths when fullPaths is true', () {
    const fileStyle = TextStyle(fontSize: 12);
    const folderStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
    final rows = [
      GitChangesVisibleRow.file(
        change: const GitFileChange(
          path: 'src/very/deep/long-name.dart',
          kind: GitChangeKind.modified,
          staged: false,
        ),
        depth: 0,
      ),
    ];

    final basenameWidth = gitChangesMinContentWidth(
      rows: rows,
      fileLabelStyle: fileStyle,
      folderLabelStyle: folderStyle,
    );
    final fullPathWidth = gitChangesMinContentWidth(
      rows: rows,
      fileLabelStyle: fileStyle,
      folderLabelStyle: folderStyle,
      fullPaths: true,
    );

    expect(fullPathWidth, greaterThan(basenameWidth));
  });
}
