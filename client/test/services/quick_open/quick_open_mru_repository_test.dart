import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/quick_open/quick_open_mru_repository.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late QuickOpenMruRepository repo;

  setUp(() {
    fs = InMemoryFilesystem();
    fs.ensureDir('/repo');
    fs.ensureDir('/repo-a');
    fs.ensureDir('/repo-b');
    repo = QuickOpenMruRepository(fs: fs, path: '/quick-open-mru.json');
  });

  test('empty store loads empty list', () async {
    expect(await repo.load('/repo'), isEmpty);
  });

  test('touch moves to front and persists', () async {
    fs.files['/repo/a.dart'] = 'x';
    fs.files['/repo/b.dart'] = 'x';
    await repo.touch('/repo', '/repo/a.dart');
    await repo.touch('/repo', '/repo/b.dart');
    await repo.touch('/repo', '/repo/a.dart');
    expect(await repo.load('/repo'), ['/repo/a.dart', '/repo/b.dart']);
  });

  test('cap: oldest entries fall off', () async {
    for (var i = 0; i < QuickOpenMruRepository.cap + 5; i++) {
      fs.files['/repo/file$i.dart'] = 'x';
      await repo.touch('/repo', '/repo/file$i.dart');
    }
    final loaded = await repo.load('/repo');
    expect(loaded.length, QuickOpenMruRepository.cap);
    // Most recent touched is first.
    expect(loaded.first, '/repo/file${QuickOpenMruRepository.cap + 4}.dart');
  });

  test('roots are isolated from each other', () async {
    fs.files['/repo-a/x.dart'] = 'x';
    fs.files['/repo-b/y.dart'] = 'x';
    await repo.touch('/repo-a', '/repo-a/x.dart');
    await repo.touch('/repo-b', '/repo-b/y.dart');
    expect(await repo.load('/repo-a'), ['/repo-a/x.dart']);
    expect(await repo.load('/repo-b'), ['/repo-b/y.dart']);
  });

  test('missing files are dropped on load', () async {
    fs.files['/quick-open-mru.json'] = '''
{"version":1,"data":{"roots":{"/repo":["/repo/gone.dart","/repo/here.dart"]}}}
''';
    fs.files['/repo/here.dart'] = 'x';
    expect(await repo.load('/repo'), ['/repo/here.dart']);
  });

  test('corrupt file yields empty list, never throws', () async {
    fs.files['/quick-open-mru.json'] = 'not json at all';
    expect(await repo.load('/repo'), isEmpty);
  });
}
