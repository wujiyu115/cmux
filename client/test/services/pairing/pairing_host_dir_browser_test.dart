import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/pairing/pairing_host_dir_browser.dart';

import '../../support/in_memory_filesystem.dart';

/// Builds a browser over one in-memory machine. [homes] maps a target id to the
/// home the host would report for it; a missing entry means "no home".
PairingHostDirBrowser _browser(
  Filesystem fs, {
  Map<String, String?> homes = const {},
  String defaultLocalRoot = '/docs/TeamPilot',
  Set<String> knownTargets = const {'wsl:Ubuntu', 'ssh:box'},
  List<String>? filesystemCalls,
  Duration? resolveTimeout,
}) {
  return PairingHostDirBrowser(
    resolveTargetId: (raw) async {
      final id = raw?.trim() ?? '';
      if (id.isEmpty || id == 'local') return id;
      if (!knownTargets.contains(id)) {
        throw ArgumentError('unknown runtime target: $id');
      }
      return id;
    },
    filesystemFor: (targetId) async {
      filesystemCalls?.add(targetId);
      return fs;
    },
    homeFor: (targetId) async => homes[targetId],
    defaultLocalRoot: () async => defaultLocalRoot,
    resolveTimeout: resolveTimeout ?? const Duration(seconds: 25),
  );
}

void main() {
  group('PairingHostDirBrowser', () {
    test('a local browse with no path starts at the default workspace root',
        () async {
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/docs/TeamPilot/proj');
      final listing = await _browser(fs).browse(null);

      expect(listing.path, '/docs/TeamPilot');
      expect(listing.dirs, ['proj']);
    });

    test('an empty targetId is the default plane, same as none', () async {
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/docs/TeamPilot');
      final calls = <String>[];
      await _browser(fs, filesystemCalls: calls).browse(null, targetId: '');

      expect(calls, ['']);
    });

    test('a remote browse with no path starts at that machine home', () async {
      // The regression this guards: resolveInitial(null) on a WSL target resolves
      // the *Windows* working directory translated to /mnt/c/..., so the phone
      // would land inside a mount of the drive it was trying to leave.
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/home/me/code');
      await fs.ensureDir('/mnt/c/Users');
      final listing = await _browser(
        fs,
        homes: const {'wsl:Ubuntu': '/home/me'},
      ).browse(null, targetId: 'wsl:Ubuntu');

      expect(listing.path, '/home/me');
      expect(listing.dirs, ['code']);
      expect(listing.path, isNot(startsWith('/mnt/')));
    });

    test('a remote machine with no home falls back to the root', () async {
      final fs = InMemoryFilesystem();
      // The fake only knows directories it was told about, root included.
      await fs.ensureDir('/');
      await fs.ensureDir('/srv');
      final listing = await _browser(fs).browse(null, targetId: 'ssh:box');

      expect(listing.path, '/');
      expect(listing.dirs, contains('srv'));
    });

    test('an explicit path wins over both defaults', () async {
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/home/me/code/app');
      await fs.ensureDir('/docs/TeamPilot');
      final listing = await _browser(
        fs,
        homes: const {'wsl:Ubuntu': '/home/me'},
      ).browse('/home/me/code', targetId: 'wsl:Ubuntu');

      expect(listing.path, '/home/me/code');
      expect(listing.dirs, ['app']);
    });

    test('a whitespace-only path counts as no path', () async {
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/docs/TeamPilot');
      final listing = await _browser(fs).browse('   ');

      expect(listing.path, '/docs/TeamPilot');
    });

    test('an unknown machine is rejected before any filesystem is touched',
        () async {
      // Without this the picker behind filesystemFor silently falls back to the
      // local machine, and the phone would be shown Windows while believing it
      // is looking at a distro.
      final fs = InMemoryFilesystem();
      final calls = <String>[];
      await expectLater(
        _browser(fs, filesystemCalls: calls).browse(null, targetId: 'wsl:Gone'),
        throwsA(isA<ArgumentError>()),
      );
      expect(calls, isEmpty);
    });

    test('a hanging machine resolve gives up instead of waiting forever',
        () async {
      // A cold SSH target connects, reads the remote home, then opens SFTP; a
      // blackholed host stalls all three. The host bound must fire so the phone
      // gets a named reason rather than its own generic timeout.
      final browser = PairingHostDirBrowser(
        resolveTargetId: (raw) async => raw ?? '',
        filesystemFor: (_) => Future.any([]),
        homeFor: (_) async => null,
        defaultLocalRoot: () async => '/docs',
        resolveTimeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        browser.browse(null, targetId: 'ssh:box'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
