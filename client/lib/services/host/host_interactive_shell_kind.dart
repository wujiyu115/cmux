/// Interactive PTY shell family (not agent CLIs, not installer script dialect).
enum HostInteractiveShellKind {
  bash,
  gitbash,
  zsh,
  fish,
  powershell,
  pwsh,
  cmd,
  unknown;

  static HostInteractiveShellKind fromExecutable(String executable) {
    final full = executable.trim().toLowerCase();
    var name = full;
    final slash = name.lastIndexOf(RegExp(r'[/\\]'));
    if (slash >= 0) {
      name = name.substring(slash + 1);
    }
    if (name.endsWith('.exe')) {
      name = name.substring(0, name.length - 4);
    }
    return switch (name) {
      // Git for Windows ships bash.exe under a `Git` install tree.
      'bash' when RegExp(r'[/\\]git[/\\]').hasMatch(full) =>
        HostInteractiveShellKind.gitbash,
      'bash' => HostInteractiveShellKind.bash,
      'zsh' => HostInteractiveShellKind.zsh,
      'fish' => HostInteractiveShellKind.fish,
      'powershell' => HostInteractiveShellKind.powershell,
      'pwsh' => HostInteractiveShellKind.pwsh,
      'cmd' => HostInteractiveShellKind.cmd,
      _ => HostInteractiveShellKind.unknown,
    };
  }

  /// Basenames tried by [HostLoginShellLookup] for PATH probes.
  static const loginLookupPosixBasenames = ['bash', 'zsh'];
}
