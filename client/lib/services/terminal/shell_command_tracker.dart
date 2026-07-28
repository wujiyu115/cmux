import 'package:uuid/uuid.dart';

import '../../models/command_log_entry.dart';
import '../../utils/terminal/osc_sequence_scanner.dart';
import 'command_secret_redactor.dart';

const _uuid = Uuid();

/// The pane facts that can change while a shell runs, resolved per command.
///
/// A pane may be renamed, moved to another surface, or `cd` somewhere else
/// between two commands, so the tracker asks for these at row-start time rather
/// than capturing them once.
class PaneLogContext {
  const PaneLogContext({
    this.surfaceId = '',
    this.surfaceName = '',
    this.paneName = '',
    this.workspaceName = '',
    this.workingDirectory = '',
  });

  final String surfaceId;
  final String surfaceName;
  final String paneName;
  final String workspaceName;
  final String workingDirectory;
}

/// Turns one pane's OSC 133 prompt markers into [CommandLogEntry] rows.
///
/// Marker vocabulary (FinalTerm / iTerm2 shell integration):
/// * `A` — a fresh prompt is being drawn. Anything still open ended without ever
///   reporting a status (shell killed, `Ctrl+C` at the prompt).
/// * `B` — the user's command line starts. Some integrations put the command text
///   in the payload; most send nothing.
/// * `C` — the command starts running. This is where the clock starts.
/// * `D[;exit]` — the command finished.
///
/// Command text is best-effort: the `B` payload, else `C;cmdline=…`, else the
/// last line the user actually submitted into the PTY ([observeUserInput]).
///
/// Panes whose shell has no integration at all still get rows: until the first
/// marker arrives, each submitted line opens an entry (with no exit status, since
/// nothing reports one) and the next line closes it.
class ShellCommandTracker {
  ShellCommandTracker({
    required this.paneId,
    required this.workspaceId,
    required this.context,
    required this.onCompleted,
    this.onStarted,
    DateTime Function()? clock,
    String Function()? newId,
  }) : _clock = clock ?? DateTime.now,
       _newId = newId ?? _uuid.v4,
       _scanner = OscSequenceScanner(codes: const {osc133Code});

  /// Shell integration prompt markers: `ESC ] 133 ; A|B|C|D … ST`.
  static const int osc133Code = 133;

  final String paneId;
  final String workspaceId;

  /// Resolved per row: surface, labels and cwd all move under a live shell.
  final PaneLogContext Function() context;

  /// Called once per finished row — the log repository's write hook.
  final void Function(CommandLogEntry entry) onCompleted;

  /// Called when a row starts running, for live "running…" display.
  final void Function(CommandLogEntry entry)? onStarted;

  final DateTime Function() _clock;
  final String Function() _newId;
  final OscSequenceScanner _scanner;

  CommandLogEntry? _active;

  /// Command text seen on `B` / `C`, waiting for the run to start.
  String? _pendingCommand;

  /// Last line submitted into the PTY, used when the shell reports no text.
  String? _lastUserLine;

  bool _sawShellIntegration = false;
  bool _disposed = false;

  /// The row currently running in this pane, or null.
  CommandLogEntry? get active => _active;

  /// True once any OSC 133 marker has been seen — shell integration is live.
  bool get hasShellIntegration => _sawShellIntegration;

  /// Feed decoded PTY output (same chunks the notification bridge sees).
  void observePtyText(String text) {
    if (_disposed || text.isEmpty) return;
    for (final sequence in _scanner.push(text)) {
      _onMarker(sequence.payload);
    }
  }

  /// Feed a line the user submitted into the PTY (Enter pressed).
  void observeUserInput(String line) {
    if (_disposed) return;
    final command = CommandSecretRedactor.sanitize(line);
    if (command == null) return;
    _lastUserLine = command;
    // No shell integration in this pane: the submitted line is all we will ever
    // learn, so open a row now and close whatever the previous line opened.
    if (!_sawShellIntegration) {
      _closeActive(exitCode: null, completedAt: null);
      _start(command);
    }
  }

  /// Ends any running row without a status — pane closed or PTY died.
  void flush() => _closeActive(exitCode: null, completedAt: null);

  void reset() {
    _scanner.reset();
    _active = null;
    _pendingCommand = null;
    _lastUserLine = null;
  }

  void dispose() {
    if (_disposed) return;
    flush();
    _disposed = true;
    reset();
  }

  // --- OSC 133 ---------------------------------------------------------------

  /// [payload] is everything after `ESC ] 133 ;` — `marker[;params…]`.
  void _onMarker(String payload) {
    if (payload.isEmpty) return;
    final split = payload.indexOf(';');
    final marker = (split < 0 ? payload : payload.substring(0, split))
        .trim()
        .toUpperCase();
    final params = split < 0 ? '' : payload.substring(split + 1);
    if (marker.isEmpty) return;
    _sawShellIntegration = true;

    switch (marker[0]) {
      case 'A':
        // A new prompt: whatever was running never reported a status.
        _closeActive(exitCode: null, completedAt: _clock().toUtc());
        _pendingCommand = null;
      case 'B':
        _pendingCommand = CommandSecretRedactor.sanitize(params) ?? _pendingCommand;
      case 'C':
        final command =
            _pendingCommand ??
            CommandSecretRedactor.sanitize(_cmdlineParam(params)) ??
            _lastUserLine;
        _pendingCommand = null;
        if (command == null) return;
        // A second `C` without a `D` (nested prompt, reprint) must not orphan the
        // running row.
        if (_active?.command == command) return;
        _closeActive(exitCode: null, completedAt: _clock().toUtc());
        _start(command);
      case 'D':
        _closeActive(exitCode: _parseExitCode(params), completedAt: _clock().toUtc());
        _pendingCommand = null;
      default:
        // `L` (fresh-line) and vendor extensions carry no command state.
        break;
    }
  }

  void _start(String command) {
    final ctx = context();
    final entry = CommandLogEntry(
      id: _newId(),
      command: command,
      startedAt: _clock().toUtc(),
      paneId: paneId,
      surfaceId: ctx.surfaceId,
      workspaceId: workspaceId,
      paneName: ctx.paneName,
      surfaceName: ctx.surfaceName,
      workspaceName: ctx.workspaceName,
      workingDirectory: ctx.workingDirectory,
    );
    _active = entry;
    onStarted?.call(entry);
  }

  void _closeActive({required int? exitCode, required DateTime? completedAt}) {
    final active = _active;
    if (active == null) return;
    _active = null;
    var done = active;
    if (done.workingDirectory.isEmpty) {
      done = done.copyWith(workingDirectory: context().workingDirectory);
    }
    onCompleted(done.copyWith(exitCode: exitCode, completedAt: completedAt));
  }

  /// `cmdline=git%20status` style parameter used by some integrations.
  static String? _cmdlineParam(String params) {
    for (final part in params.split(';')) {
      const key = 'cmdline=';
      if (part.length > key.length &&
          part.substring(0, key.length).toLowerCase() == key) {
        return part.substring(key.length);
      }
    }
    return null;
  }

  /// First integer among the `D` parameters: `D;1`, `D;1;aid=2`, `D` → null.
  static int? _parseExitCode(String params) {
    if (params.isEmpty) return null;
    for (final part in params.split(';')) {
      final code = int.tryParse(part.trim());
      if (code != null) return code;
    }
    return null;
  }
}
