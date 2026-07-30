import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/workspace_accent.dart';
import 'package:teampilot/models/workspace_group.dart';
import 'package:teampilot/services/home_workspace/workspace_groups_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory tempDir;
  late LocalFilesystem fs;
  late String path;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wsgroups_test_');
    fs = LocalFilesystem();
    path = p.join(tempDir.path, 'ui', 'workspace-groups.json');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  WorkspaceGroupsStore store() => WorkspaceGroupsStore(fs: fs, path: path);

  test('missing file loads as empty', () async {
    expect(await store().load(), isEmpty);
  });

  test('save then load round-trips and sorts by order', () async {
    await store().save([
      const WorkspaceGroup(id: 'b', name: 'Beta', order: 2),
      WorkspaceGroup(
        id: 'a',
        name: 'Alpha',
        order: 1,
        collapsed: true,
        accent: const WorkspaceAccentPreset(4),
      ),
    ]);
    final loaded = await store().load();
    expect(loaded.map((g) => g.id), ['a', 'b']);
    expect(loaded.first.collapsed, isTrue);
    expect(loaded.first.accent, const WorkspaceAccentPreset(4));
    expect(loaded.last.name, 'Beta');
  });
}
