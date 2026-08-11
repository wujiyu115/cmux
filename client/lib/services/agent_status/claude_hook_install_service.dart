import 'dart:async';
import 'dart:io';

import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'claude_hook_installer.dart';

/// In-distro `$HOME` and TeamPilot app-data root for a WSL distro.
typedef WslHookPaths = ({String home, String appDataRoot});

/// Decides *where* the shared Claude forwarder hook is installed.
///
/// `claude` running inside a WSL distro reads that distro's own
/// `~/.claude/settings.json` and cannot execute a Windows script path, so each
/// distro needs its own installation next to the host one.
///
/// Distro installs are **lazy**: the first time a pane launches into a distro.
/// Eager installation at boot would wake every registered distro on every app
/// start — probing `$HOME` alone measured ~2s cold — for distros the user may
/// never open. The trade-off is that a distro's very first pane can race the
/// install and miss the hook for that one session; the next one has it.
class ClaudeHookInstallService {
  ClaudeHookInstallService({
    required this.hostAppDataRoot,
    Future<WslHookPaths?> Function(String distro)? resolveWslPaths,
    Filesystem Function(String distro)? wslFilesystemFor,
    Filesystem? hostFilesystem,
    bool? supportsWsl,
  }) : _resolveWslPaths = resolveWslPaths,
       _wslFilesystemFor = wslFilesystemFor,
       _hostFilesystem = hostFilesystem,
       _supportsWsl = supportsWsl ?? Platform.isWindows;

  /// App-data root on the machine the app runs on. Must be the *host* path
  /// (`AppPathsBootstrapper.current.basePath`), not `AppStorage.appDataRoot` —
  /// the latter points inside the distro when the home target is WSL.
  final String hostAppDataRoot;

  final Future<WslHookPaths?> Function(String distro)? _resolveWslPaths;
  final Filesystem Function(String distro)? _wslFilesystemFor;
  final Filesystem? _hostFilesystem;
  final bool _supportsWsl;

  /// Distros already attempted this run; a failed attempt is removed so a later
  /// launch can retry (the distro may simply have been unavailable).
  final Set<String> _wslAttempted = {};

  /// Installs the host-side hook. Best-effort — [ClaudeHookInstaller.install]
  /// logs and swallows its own failures.
  Future<void> installHost() async {
    final installer = ClaudeHookInstaller.forHost(
      hostAppDataRoot: hostAppDataRoot,
      filesystem: _hostFilesystem,
    );
    if (installer == null) return;
    await installer.install();
  }

  /// Installs into [distro] the first time it is used. Fire-and-forget: the
  /// caller is a launch path and must not wait on `wsl.exe` round-trips.
  void ensureWslDistro(String distro) {
    final name = distro.trim();
    if (name.isEmpty || !_supportsWsl) return;
    if (_resolveWslPaths == null) return;
    if (!_wslAttempted.add(name)) return;
    unawaited(_installWslDistro(name));
  }

  Future<void> _installWslDistro(String distro) async {
    try {
      final paths = await _resolveWslPaths!(distro);
      final home = paths?.home.trim() ?? '';
      final appDataRoot = paths?.appDataRoot.trim() ?? '';
      if (home.isEmpty || appDataRoot.isEmpty) {
        _wslAttempted.remove(distro);
        return;
      }
      await ClaudeHookInstaller.forWslDistro(
        distro: distro,
        distroHome: home,
        distroAppDataRoot: appDataRoot,
        filesystem: _wslFilesystemFor?.call(distro),
      ).install();
      appLogger.i('[agent-status] Claude hook installed in wsl:$distro');
    } catch (e, st) {
      // Allow a retry on the next launch into this distro.
      _wslAttempted.remove(distro);
      appLogger.w(
        '[agent-status] Claude hook install failed for wsl:$distro: $e',
        error: e,
        stackTrace: st,
      );
    }
  }
}
