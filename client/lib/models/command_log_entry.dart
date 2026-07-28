/// One shell command observed in a terminal pane, from OSC 133 prompt markers.
///
/// JSON field names match the original cmux `CommandLogEntry` so daily log files
/// written by either app stay mutually readable.
class CommandLogEntry {
  const CommandLogEntry({
    required this.id,
    required this.command,
    required this.startedAt,
    this.paneId = '',
    this.surfaceId = '',
    this.workspaceId = '',
    this.paneName = '',
    this.surfaceName = '',
    this.workspaceName = '',
    this.completedAt,
    this.exitCode,
    this.workingDirectory = '',
  });

  final String id;

  /// Redacted command line; never empty (entries without text are not created).
  final String command;

  /// UTC instant the command started running.
  final DateTime startedAt;

  final String paneId;
  final String surfaceId;
  final String workspaceId;

  /// Display labels captured when the command ran. Kept alongside the ids so a
  /// row from last week still reads properly after the pane, surface or
  /// workspace has been renamed or closed. Extra JSON keys, ignored by cmux.
  final String paneName;
  final String surfaceName;
  final String workspaceName;

  /// UTC completion instant. Null when the command is still running, or when it
  /// was closed out without a `D` marker (killed shell, no shell integration).
  final DateTime? completedAt;

  /// Exit status from the `D` marker; null when never reported.
  final int? exitCode;

  final String workingDirectory;

  /// Null unless the command actually reported a finish.
  Duration? get duration => completedAt?.difference(startedAt);

  bool get succeeded => exitCode == 0;

  /// Column text: the captured label, or the raw id when none was recorded.
  String get workspaceLabel =>
      workspaceName.isNotEmpty ? workspaceName : workspaceId;
  String get surfaceLabel => surfaceName.isNotEmpty ? surfaceName : surfaceId;
  String get paneLabel => paneName.isNotEmpty ? paneName : paneId;

  CommandLogEntry copyWith({
    String? command,
    DateTime? completedAt,
    int? exitCode,
    String? workingDirectory,
  }) => CommandLogEntry(
    id: id,
    command: command ?? this.command,
    startedAt: startedAt,
    paneId: paneId,
    surfaceId: surfaceId,
    workspaceId: workspaceId,
    paneName: paneName,
    surfaceName: surfaceName,
    workspaceName: workspaceName,
    completedAt: completedAt ?? this.completedAt,
    exitCode: exitCode ?? this.exitCode,
    workingDirectory: workingDirectory ?? this.workingDirectory,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'paneId': paneId,
    'surfaceId': surfaceId,
    'workspaceId': workspaceId,
    if (paneName.isNotEmpty) 'paneName': paneName,
    if (surfaceName.isNotEmpty) 'surfaceName': surfaceName,
    if (workspaceName.isNotEmpty) 'workspaceName': workspaceName,
    'command': command,
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toUtc().toIso8601String(),
    if (exitCode != null) 'exitCode': exitCode,
    if (workingDirectory.isNotEmpty) 'workingDirectory': workingDirectory,
  };

  /// Returns null when the row cannot be trusted (no command text, unparseable
  /// start time) so callers can count it as a skipped line instead of guessing.
  static CommandLogEntry? fromJson(Map<String, dynamic> json) {
    final command = (json['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) return null;
    final startedAt = _parseTime(json['startedAt']);
    if (startedAt == null) return null;
    final id = (json['id'] as String?)?.trim() ?? '';
    return CommandLogEntry(
      id: id.isEmpty ? '${startedAt.microsecondsSinceEpoch}' : id,
      command: command,
      startedAt: startedAt,
      paneId: json['paneId'] as String? ?? '',
      surfaceId: json['surfaceId'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      paneName: json['paneName'] as String? ?? '',
      surfaceName: json['surfaceName'] as String? ?? '',
      workspaceName: json['workspaceName'] as String? ?? '',
      completedAt: _parseTime(json['completedAt']),
      exitCode: switch (json['exitCode']) {
        final int code => code,
        final String code => int.tryParse(code),
        _ => null,
      },
      workingDirectory: json['workingDirectory'] as String? ?? '',
    );
  }

  static DateTime? _parseTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

/// Locale-independent duration label: `820ms`, `1.4s`, `2m 3s`, `1h 4m`.
String commandDurationLabel(Duration duration) {
  final ms = duration.inMilliseconds;
  if (ms < 1000) return '${ms < 0 ? 0 : ms}ms';
  if (duration.inMinutes < 1) {
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }
  if (duration.inHours < 1) {
    return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
  }
  return '${duration.inHours}h ${duration.inMinutes % 60}m';
}
