import 'dart:io';

/// Enumerates installed WSL distributions on Windows via `wsl.exe -l -q`.
///
/// Off Windows (or when WSL is absent / errors) this yields an empty list — the
/// caller simply omits WSL entries from the launch catalog.
abstract final class WslDistroLookup {
  WslDistroLookup._();

  /// Distro names (e.g. `Ubuntu`, `Debian`), in `wsl.exe` registration order.
  static Future<List<String>> list() async {
    if (!Platform.isWindows) return const [];
    try {
      // `-l -q` prints one distro name per line. wsl.exe emits UTF-16LE with a
      // trailing NUL per code unit; read raw bytes and drop the zero bytes.
      final result = await Process.run(
        'wsl.exe',
        const ['-l', '-q'],
        stdoutEncoding: null,
      );
      if (result.exitCode != 0) return const [];
      final bytes = (result.stdout as List<int>)
          .where((b) => b != 0)
          .toList(growable: false);
      final text = String.fromCharCodes(bytes);
      return text
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }
}
