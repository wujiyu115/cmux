import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

void main() {
  late Directory tmp;
  late TargetsRepository targetsRepo;
  late SshProfileRepository sshRepo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt_registry_');
    final fs = LocalFilesystem();
    targetsRepo = TargetsRepository(rootDir: tmp.path, fs: fs);
    sshRepo = SshProfileRepository(rootDir: tmp.path, fs: fs);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  RuntimeTargetRegistry build({
    bool isWindows = false,
    bool isAndroid = false,
    List<String> wslDistros = const [],
  }) => RuntimeTargetRegistry(
    repo: targetsRepo,
    sshProfileRepo: sshRepo,
    isWindows: isWindows,
    isAndroid: isAndroid,
    listWslDistros: () async => wslDistros,
  );

  SshProfile profile(String id) =>
      SshProfile(id: id, name: 'name-$id', host: 'h', username: 'u');

  test('listTargets always includes implicit local first', () async {
    final reg = build();
    final targets = await reg.listTargets();
    expect(targets.first.id, 'local');
  });

  test(
    'listTargets injects implicit wsl on Windows when distro given',
    () async {
      final reg = build(isWindows: true);
      final ids = (await reg.listTargets(wslDistro: 'Ubuntu')).map((t) => t.id);
      expect(ids, contains('wsl:Ubuntu'));
    },
  );

  test('listTargets enumerates one target per installed wsl distro', () async {
    final reg = build(
      isWindows: true,
      wslDistros: ['Ubuntu-24.04', 'Debian'],
    );
    final ids = (await reg.listTargets()).map((t) => t.id).toList();
    expect(ids, containsAll(['wsl:Ubuntu-24.04', 'wsl:Debian']));
  });

  test('listTargets merges selected distro with enumerated list once', () async {
    final reg = build(isWindows: true, wslDistros: ['Ubuntu-24.04']);
    final ids = (await reg.listTargets(wslDistro: 'Ubuntu-24.04'))
        .map((t) => t.id)
        .where((id) => id == 'wsl:Ubuntu-24.04')
        .toList();
    expect(ids, ['wsl:Ubuntu-24.04']); // no duplicate
  });

  test('listTargets omits wsl targets off Windows', () async {
    final reg = build(wslDistros: ['Ubuntu']);
    final ids = (await reg.listTargets()).map((t) => t.id);
    expect(ids.where((id) => id.startsWith('wsl:')), isEmpty);
  });

  test('reconcile: new ssh profile appears; deleted profile pruned', () async {
    await targetsRepo.save(
      TargetsRegistryFile(
        targets: [
          RuntimeTarget.ssh('p1', label: 'old'),
          RuntimeTarget.ssh('p3', label: 'gone'),
        ],
      ),
    );
    await sshRepo.saveAll([profile('p1'), profile('p2')]);
    final reg = build();
    final ids = (await reg.listTargets()).map((t) => t.id).toSet();
    expect(ids.contains('ssh:p1'), isTrue);
    expect(ids.contains('ssh:p2'), isTrue); // newly added & written back
    expect(ids.contains('ssh:p3'), isFalse); // orphan pruned
    final persisted = (await targetsRepo.load()).targets
        .map((t) => t.id)
        .toSet();
    expect(persisted, {'ssh:p1', 'ssh:p2'});
  });
}
