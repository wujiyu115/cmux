/// Builds `wsl.exe` argv prefixes shared by one-shot runners and filesystem IO.
abstract final class HostWslArgv {
  HostWslArgv._();

  static List<String> prefixDistro({
    String? distro,
    required List<String> command,
  }) {
    final trimmed = distro?.trim() ?? '';
    if (trimmed.isEmpty) return command;
    return ['-d', trimmed, ...command];
  }

  /// `wsl.exe [-d distro] [--cd cwd] --exec <executable> <args…>`.
  ///
  /// `--exec` consumes the rest of the argv, so `--cd` must precede it —
  /// `wsl --exec --cd X …` fails with `execvpe(--cd) failed` (wsl treats
  /// `--cd` as the executable). `--exec` also bypasses the distro's login
  /// shell, so argv reaches the executable untouched (no zsh glob expansion
  /// of rg's `!glob` patterns, no rc noise).
  static List<String> processInvocation({
    String? distro,
    String? workingDirectory,
    required String executable,
    required List<String> arguments,
  }) {
    final inner = <String>[];
    final cwd = workingDirectory?.trim() ?? '';
    if (cwd.isNotEmpty) {
      inner.addAll(['--cd', cwd]);
    }
    inner.addAll(['--exec', executable, ...arguments]);
    return prefixDistro(distro: distro, command: inner);
  }
}
