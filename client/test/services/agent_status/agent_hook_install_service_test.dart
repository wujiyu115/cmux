import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_hook_install_service.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  const distroPaths = (
    home: '/home/u',
    appDataRoot: '/home/u/.local/share/com.hhoa.teampilot',
  );
  const distroScript =
      '/home/u/.local/share/com.hhoa.teampilot/agent-hooks/claude-hook.sh';

  test('installs into a distro on first launch', () async {
    final fs = InMemoryFilesystem();
    final service = AgentHookInstallService(
      hostAppDataRoot: '/host/app',
      supportsWsl: true,
      resolveWslPaths: (_) async => distroPaths,
      wslFilesystemFor: (_) => fs,
    );

    service.ensureWslDistro('Ubuntu');
    await pumpEventQueue();

    // One shared forwarder script plus each target's own settings file.
    expect(fs.files[distroScript], isNotNull);
    expect(fs.files['/home/u/.claude/settings.json'], isNotNull);
    expect(fs.files['/home/u/.qoder/settings.json'], isNotNull);
    expect(fs.files['/home/u/.codex/hooks.json'], isNotNull);
    // A distro is POSIX — no Windows cmd forwarder there.
    expect(
      fs.files.containsKey('/home/u/.local/share/com.hhoa.teampilot/'
          'agent-hooks/codex-hook.cmd'),
      isFalse,
    );
  });

  test('installs a distro only once across repeated launches', () async {
    var resolves = 0;
    final service = AgentHookInstallService(
      hostAppDataRoot: '/host/app',
      supportsWsl: true,
      resolveWslPaths: (_) async {
        resolves++;
        return distroPaths;
      },
      wslFilesystemFor: (_) => InMemoryFilesystem(),
    );

    service.ensureWslDistro('Ubuntu');
    service.ensureWslDistro('Ubuntu');
    await pumpEventQueue();
    service.ensureWslDistro('Ubuntu');
    await pumpEventQueue();

    expect(resolves, 1);
  });

  test('tracks distros independently', () async {
    final seen = <String>[];
    final service = AgentHookInstallService(
      hostAppDataRoot: '/host/app',
      supportsWsl: true,
      resolveWslPaths: (d) async {
        seen.add(d);
        return distroPaths;
      },
      wslFilesystemFor: (_) => InMemoryFilesystem(),
    );

    service.ensureWslDistro('Ubuntu');
    service.ensureWslDistro('Debian');
    await pumpEventQueue();

    expect(seen, ['Ubuntu', 'Debian']);
  });

  test('a failed attempt is retried on the next launch', () async {
    var calls = 0;
    final service = AgentHookInstallService(
      hostAppDataRoot: '/host/app',
      supportsWsl: true,
      resolveWslPaths: (_) async {
        calls++;
        if (calls == 1) throw StateError('distro unavailable');
        return distroPaths;
      },
      wslFilesystemFor: (_) => InMemoryFilesystem(),
    );

    // Must not throw out of the fire-and-forget call.
    service.ensureWslDistro('Ubuntu');
    await pumpEventQueue();
    expect(calls, 1);

    service.ensureWslDistro('Ubuntu');
    await pumpEventQueue();
    expect(calls, 2);
  });

  test('blank resolved paths are skipped and left retryable', () async {
    var calls = 0;
    final service = AgentHookInstallService(
      hostAppDataRoot: '/host/app',
      supportsWsl: true,
      resolveWslPaths: (_) async {
        calls++;
        return (home: '', appDataRoot: '');
      },
      wslFilesystemFor: (_) => InMemoryFilesystem(),
    );

    service.ensureWslDistro('Ubuntu');
    await pumpEventQueue();
    service.ensureWslDistro('Ubuntu');
    await pumpEventQueue();

    expect(calls, 2);
  });

  test('does nothing when WSL is unsupported', () async {
    var resolves = 0;
    final service = AgentHookInstallService(
      hostAppDataRoot: '/host/app',
      supportsWsl: false,
      resolveWslPaths: (_) async {
        resolves++;
        return distroPaths;
      },
      wslFilesystemFor: (_) => InMemoryFilesystem(),
    );

    service.ensureWslDistro('Ubuntu');
    await pumpEventQueue();

    expect(resolves, 0);
  });

  test('ignores a blank distro name', () async {
    var resolves = 0;
    final service = AgentHookInstallService(
      hostAppDataRoot: '/host/app',
      supportsWsl: true,
      resolveWslPaths: (_) async {
        resolves++;
        return distroPaths;
      },
      wslFilesystemFor: (_) => InMemoryFilesystem(),
    );

    service.ensureWslDistro('   ');
    await pumpEventQueue();

    expect(resolves, 0);
  });

  test('installHost writes the forwarder under the host app-data root',
      () async {
    final fs = InMemoryFilesystem();
    await AgentHookInstallService(
      hostAppDataRoot: '/host/app',
      hostFilesystem: fs,
    ).installHost();

    // Host body talks to the gateway with plain curl — it runs on the same
    // machine as the listener.
    final script = fs.files['/host/app/agent-hooks/claude-hook.sh'];
    expect(script, isNotNull);
    expect(script, isNot(contains('curl.exe')));
  });
}
