class SessionPreferences {
  SessionPreferences({
    Map<String, String> cliExecutablePaths = const {},
    Map<String, String> toolchainPaths = const {},
    this.defaultSshWorkingDirectory = '',
    this.sshUseLoginShell = false,
    this.terminalScrollbackLines = 10000,
    this.terminalLinkClickOpensInApp = true,
    this.openExistingSessionStartsTerminal = false,
    this.simpleModeDefaultFullAccess = true,
    this.notifyOnSessionIdle = true,
    this.notifyWhileWatching = true,
  }) : cliExecutablePaths = Map.unmodifiable(
         _normalizeCliExecutablePaths(cliExecutablePaths),
       ),
       toolchainPaths = Map.unmodifiable(
         _normalizeCliExecutablePaths(toolchainPaths),
       );

  /// Well-known keys for [toolchainPaths].
  static const toolchainGit = 'git';
  static const toolchainNode = 'node';

  factory SessionPreferences.fromJson(Map<String, Object?> json) {
    return SessionPreferences(
      cliExecutablePaths: _cliExecutablePathsFromJson(
        json['cliExecutablePaths'],
      ),
      toolchainPaths: _cliExecutablePathsFromJson(json['toolchainPaths']),
      defaultSshWorkingDirectory:
          json['defaultSshWorkingDirectory'] as String? ?? '',
      sshUseLoginShell: json['sshUseLoginShell'] as bool? ?? false,
      terminalScrollbackLines:
          (json['terminalScrollbackLines'] as num?)?.toInt() ?? 10000,
      terminalLinkClickOpensInApp:
          json['terminalLinkClickOpensInApp'] as bool? ?? true,
      openExistingSessionStartsTerminal:
          json['openExistingSessionStartsTerminal'] as bool? ?? false,
      simpleModeDefaultFullAccess:
          json['simpleModeDefaultFullAccess'] as bool? ?? true,
      notifyOnSessionIdle: json['notifyOnSessionIdle'] as bool? ?? true,
      notifyWhileWatching: json['notifyWhileWatching'] as bool? ?? true,
    );
  }

  /// CLI executable paths keyed by [CliTool.value]. Empty value means fall
  /// back to startup discovery, then the tool name on PATH.
  final Map<String, String> cliExecutablePaths;

  /// Toolchain executable paths keyed by toolchain constant (e.g.
  /// [toolchainGit], [toolchainNode]). Empty value means the tool is not
  /// configured — callers should fall back to PATH lookup.
  final Map<String, String> toolchainPaths;

  /// Default remote working directory used when an SSH launch has no workspace
  /// path yet. Empty means "do not cd before launching".
  final String defaultSshWorkingDirectory;

  /// When true, SSH launches run through `bash -lc` so remote shell startup
  /// files can populate PATH and related environment.
  final bool sshUseLoginShell;

  /// Maximum scrollback lines retained per embedded terminal session.
  final int terminalScrollbackLines;

  /// When true, a plain left-click on a link/file-path in the embedded terminal
  /// is handled in-app (open in editor / TeamPilot's URI opener) instead of
  /// being forwarded to the running program (which may launch an external app).
  /// Ctrl/Cmd-click always opens in-app regardless of this setting.
  final bool terminalLinkClickOpensInApp;

  /// When true, opening an existing conversation from search / deep link
  /// connects the PTY immediately. When false (default), the session opens
  /// in history-review mode until the user submits from slim compose.
  final bool openExistingSessionStartsTerminal;

  /// When true (default), Simple-mode compose landing starts with full access
  /// unless a workspace has already persisted a different chip choice.
  final bool simpleModeDefaultFullAccess;

  /// When true (default), fire an OS notification when an embedded terminal
  /// finishes a burst of output and goes idle (agent turn done). The in-app
  /// notification center records it regardless.
  final bool notifyOnSessionIdle;

  /// When true (default), notify even while the app is focused and the user is
  /// looking at the very terminal that reported the edge. When false, that case
  /// is suppressed as "don't nag about what you are already watching".
  final bool notifyWhileWatching;

  String cliExecutablePathFor(String toolId) =>
      cliExecutablePaths[toolId]?.trim() ?? '';

  SessionPreferences copyWith({
    Map<String, String>? cliExecutablePaths,
    Map<String, String>? toolchainPaths,
    String? defaultSshWorkingDirectory,
    bool? sshUseLoginShell,
    int? terminalScrollbackLines,
    bool? terminalLinkClickOpensInApp,
    bool? openExistingSessionStartsTerminal,
    bool? simpleModeDefaultFullAccess,
    bool? notifyOnSessionIdle,
    bool? notifyWhileWatching,
  }) {
    return SessionPreferences(
      cliExecutablePaths: cliExecutablePaths ?? this.cliExecutablePaths,
      toolchainPaths: toolchainPaths ?? this.toolchainPaths,
      defaultSshWorkingDirectory:
          defaultSshWorkingDirectory ?? this.defaultSshWorkingDirectory,
      sshUseLoginShell: sshUseLoginShell ?? this.sshUseLoginShell,
      terminalScrollbackLines:
          terminalScrollbackLines ?? this.terminalScrollbackLines,
      terminalLinkClickOpensInApp:
          terminalLinkClickOpensInApp ?? this.terminalLinkClickOpensInApp,
      openExistingSessionStartsTerminal:
          openExistingSessionStartsTerminal ??
          this.openExistingSessionStartsTerminal,
      simpleModeDefaultFullAccess:
          simpleModeDefaultFullAccess ?? this.simpleModeDefaultFullAccess,
      notifyOnSessionIdle: notifyOnSessionIdle ?? this.notifyOnSessionIdle,
      notifyWhileWatching: notifyWhileWatching ?? this.notifyWhileWatching,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'cliExecutablePaths': cliExecutablePaths,
      'toolchainPaths': toolchainPaths,
      'defaultSshWorkingDirectory': defaultSshWorkingDirectory,
      'sshUseLoginShell': sshUseLoginShell,
      'terminalScrollbackLines': terminalScrollbackLines,
      'terminalLinkClickOpensInApp': terminalLinkClickOpensInApp,
      'openExistingSessionStartsTerminal': openExistingSessionStartsTerminal,
      'simpleModeDefaultFullAccess': simpleModeDefaultFullAccess,
      'notifyOnSessionIdle': notifyOnSessionIdle,
      'notifyWhileWatching': notifyWhileWatching,
    };
  }

  static Map<String, String> _cliExecutablePathsFromJson(Object? value) {
    if (value is! Map) return const {};
    return _normalizeCliExecutablePaths(
      value.map(
        (key, value) =>
            MapEntry(key is String ? key : '', value is String ? value : ''),
      ),
    );
  }

  static Map<String, String> _normalizeCliExecutablePaths(
    Map<String, String> paths,
  ) {
    final normalized = <String, String>{};
    for (final entry in paths.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) continue;
      normalized[key] = value;
    }
    return normalized;
  }
}
