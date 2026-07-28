import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/io/versioned_json_store.dart';

class _Doc {
  const _Doc(this.name, this.count);

  final String name;
  final int count;
}

void main() {
  late Directory tempDir;
  late LocalFilesystem fs;
  late String path;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vjson_test_');
    fs = LocalFilesystem();
    path = p.join(tempDir.path, 'doc.json');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  VersionedJsonStore<_Doc> makeStore({
    int currentVersion = 1,
    Map<int, JsonMigration> migrations = const {},
    DateTime Function()? now,
  }) {
    return VersionedJsonStore<_Doc>(
      fs: fs,
      path: path,
      currentVersion: currentVersion,
      migrations: migrations,
      now: now ?? DateTime.now,
      decode: (data) => _Doc(data['name'] as String, data['count'] as int),
      encode: (value) => {'name': value.name, 'count': value.count},
    );
  }

  test('read on a missing file reports missing', () async {
    final result = await makeStore().read();
    expect(result.status, VersionedReadStatus.missing);
    expect(result.data, isNull);
  });

  test('write then read round trips', () async {
    final store = makeStore();
    await store.write(const _Doc('alpha', 3));
    final result = await store.read();
    expect(result.status, VersionedReadStatus.ok);
    expect(result.data!.name, 'alpha');
    expect(result.data!.count, 3);
  });

  test('second write backs up the first payload to -previous', () async {
    final store = makeStore();
    await store.write(const _Doc('first', 1));
    await store.write(const _Doc('second', 2));

    expect(File(store.previousPath).existsSync(), isTrue);
    final backup =
        jsonDecode(File(store.previousPath).readAsStringSync()) as Map;
    expect((backup['data'] as Map)['name'], 'first');
    expect((backup['data'] as Map)['count'], 1);

    final primary = jsonDecode(File(store.path).readAsStringSync()) as Map;
    expect((primary['data'] as Map)['name'], 'second');
  });

  test('corrupt primary with valid backup recovers from backup', () async {
    final store = makeStore();
    await store.write(const _Doc('good', 7));
    // Second write rotates the 'good' payload into -previous, then writes
    // 'newer' to the primary.
    await store.write(const _Doc('newer', 8));
    // Corrupt the primary; the backup still holds the 'good' payload.
    File(store.path).writeAsStringSync('{not valid json');

    final result = await store.read();
    expect(result.status, VersionedReadStatus.recoveredFromBackup);
    expect(result.data!.name, 'good');
    expect(result.data!.count, 7);
    expect(result.error, isNotNull);
  });

  test('corrupt primary and corrupt backup quarantines primary', () async {
    final store = makeStore();
    await store.write(const _Doc('x', 1));
    File(store.previousPath).writeAsStringSync('also broken');
    const badPrimary = '{"version": 1, "data": "not a map"}';
    File(store.path).writeAsStringSync(badPrimary);

    final result = await store.read();
    expect(result.status, VersionedReadStatus.quarantined);
    expect(result.data, isNull);
    expect(result.quarantinePath, isNotNull);
    expect(File(result.quarantinePath!).readAsStringSync(), badPrimary);
    expect(File(store.path).existsSync(), isFalse);
  });

  test('corrupt primary with no backup quarantines', () async {
    final store = makeStore();
    File(store.path).writeAsStringSync('garbage');

    final result = await store.read();
    expect(result.status, VersionedReadStatus.quarantined);
    expect(result.quarantinePath, isNotNull);
    expect(File(store.path).existsSync(), isFalse);
  });

  test('quarantine filename uses injected timestamp', () async {
    final fixed = DateTime.fromMillisecondsSinceEpoch(123456);
    final store = makeStore(now: () => fixed);
    File(store.path).writeAsStringSync('garbage');

    final result = await store.read();
    expect(result.quarantinePath, p.join(tempDir.path, 'doc.corrupt-123456.json'));
  });

  test('migrates an old file up to the current version', () async {
    // Write a version-1 envelope by hand.
    File(path).writeAsStringSync(
      jsonEncode({
        'version': 1,
        'data': {'name': 'old', 'count': 1},
      }),
    );
    final store = makeStore(
      currentVersion: 3,
      migrations: {
        1: (data) => {...data, 'count': (data['count'] as int) + 10},
        2: (data) => {...data, 'name': '${data['name']}-v3'},
      },
    );
    final result = await store.read();
    expect(result.status, VersionedReadStatus.ok);
    expect(result.data!.name, 'old-v3');
    expect(result.data!.count, 11);
  });

  test('missing migration step falls through to quarantine', () async {
    File(path).writeAsStringSync(
      jsonEncode({
        'version': 1,
        'data': {'name': 'old', 'count': 1},
      }),
    );
    // currentVersion 3 but only a migration for step 2 registered.
    final store = makeStore(
      currentVersion: 3,
      migrations: {2: (data) => data},
    );
    final result = await store.read();
    expect(result.status, VersionedReadStatus.quarantined);
    expect(File(store.path).existsSync(), isFalse);
  });

  test('version newer than current is treated as corrupt', () async {
    File(path).writeAsStringSync(
      jsonEncode({
        'version': 9,
        'data': {'name': 'future', 'count': 1},
      }),
    );
    final result = await makeStore(currentVersion: 1).read();
    expect(result.status, VersionedReadStatus.quarantined);
  });

  test('decode throwing is treated as corrupt', () async {
    // Valid envelope but data missing the required int field.
    File(path).writeAsStringSync(
      jsonEncode({
        'version': 1,
        'data': {'name': 'partial'},
      }),
    );
    final result = await makeStore().read();
    expect(result.status, VersionedReadStatus.quarantined);
  });
}
