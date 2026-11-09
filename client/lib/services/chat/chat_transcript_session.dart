import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/runtime_target.dart';
import '../cli/sessions/agent_cli_session_service.dart';
import '../cli/sessions/agent_cli_sessions.dart';
import '../storage/runtime_context.dart';
import 'chat_transcript_parser.dart';
import 'chat_transcript_row.dart';

/// Live chat transcript of one pane's agent CLI session.
///
/// The pane keeps running its agent in the terminal; this class only *reads*
/// what the CLI itself persists, so chat mode is a second view of the same
/// session and needs no protocol work in the CLI. Resolution goes through the
/// runtime target's [RuntimeContext], which is what makes Windows, WSL, and SSH
/// panes behave the same: the only difference is which filesystem answers.
///
/// Polling at human speed rather than watching the file keeps WSL cheap — every
/// `WslFilesystem` stat is a `wsl.exe` spawn, so a native watch would be a
/// process per event.
class ChatTranscriptSession {
  ChatTranscriptSession({
    required this.paneId,
    required Future<RuntimeContext> Function(RuntimeTarget target)
    resolveContext,
    required RuntimeTarget Function() target,
    required String Function() directory,
    required DateTime startedAt,
    AgentCliSessionService? sessionService,
    this.pollInterval = const Duration(milliseconds: 800),
    this.maxBytes = 4 << 20,
    this.slack = const Duration(minutes: 2),
  }) : _resolveContext = resolveContext,
       _target = target,
       _directory = directory,
       _startedAt = startedAt,
       _sessions =
           sessionService ??
           AgentCliSessionService(resolveContext: resolveContext);

  final String paneId;

  /// Upper bound on one read. A long agent session can reach megabytes of
  /// tool output; the transcript only needs the recent tail.
  final int maxBytes;

  final Duration pollInterval;

  /// How far before the pane started a session file may have been written and
  /// still count as this pane's. Resumed sessions keep their original creation
  /// time but get a fresh mtime.
  final Duration slack;

  final Future<RuntimeContext> Function(RuntimeTarget target) _resolveContext;
  final RuntimeTarget Function() _target;
  final String Function() _directory;
  final DateTime _startedAt;
  final AgentCliSessionService _sessions;

  final _transcript = ValueNotifier<ChatTranscriptSnapshot>(
    const ChatTranscriptSnapshot(
      unavailable: ChatTranscriptUnavailable.noSessionFile,
    ),
  );

  Timer? _timer;
  ChatTranscriptParser? _parser;
  String? _path;
  String? _sessionId;
  AgentCliFamily? _family;
  bool _resolving = false;
  bool _refreshing = false;
  bool _disposed = false;

  /// Rows for the UI and the paired phone; identical payload either way.
  ValueListenable<ChatTranscriptSnapshot> get transcript => _transcript;

  /// Store file being read, once resolved.
  String? get resolvedPath => _path;

  /// Starts polling. Idempotent.
  void start() {
    if (_disposed || _timer != null) return;
    unawaited(_refresh());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_refresh()));
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _transcript.dispose();
  }

  /// One poll, awaited. The poll timer cannot be awaited; tests and the
  /// "refresh now" affordance need the deterministic form.
  Future<void> refreshNow() => _refresh();

  Future<void> _refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      if (_path == null) await _resolveFile();
      final path = _path;
      if (path == null || _parser == null) {
        _emit(
          ChatTranscriptSnapshot(
            rows: _transcript.value.rows,
            unavailable: _unavailable(),
          ),
        );
        return;
      }
      final context = await _resolveContext(_target());
      if (_disposed) return;
      final fs = context.filesystem;
      final stat = await fs.stat(path);
      if (_disposed) return;
      if (!stat.isFile) {
        // The CLI removed or rotated the file; look again from scratch.
        _forget();
        _emit(
          const ChatTranscriptSnapshot(
            unavailable: ChatTranscriptUnavailable.noSessionFile,
          ),
        );
        return;
      }
      final size = stat.size ?? 0;
      if (size == 0) {
        _emit(ChatTranscriptSnapshot(unavailable: null, rows: const []));
        return;
      }
      final offset = size > maxBytes ? size - maxBytes : 0;
      final bytes =
          await fs.readBytesRange(path, offset, size - offset) ?? const <int>[];
      if (_disposed) return;
      final rows = _parser!.parse(bytes);
      _emit(
        ChatTranscriptSnapshot(
          rows: rows,
          sessionId: _sessionId,
          family: _family?.name,
          busy: _isBusy(rows),
        ),
      );
    } on Object {
      if (_disposed) return;
      _emit(
        ChatTranscriptSnapshot(
          rows: _transcript.value.rows,
          unavailable: ChatTranscriptUnavailable.readFailed,
        ),
      );
    } finally {
      _refreshing = false;
    }
  }

  /// Newest session file bound to this pane's cwd that a parser understands.
  Future<void> _resolveFile() async {
    if (_resolving) return;
    final directory = _directory().trim();
    if (directory.isEmpty) return;
    _resolving = true;
    try {
      final records = await _sessions.listSessions(
        target: _target(),
        directory: directory,
      );
      if (_disposed) return;
      final floor = _startedAt.subtract(slack);
      AgentCliSessionRecord? chosen;
      for (final record in records) {
        if (record.filePath == null) continue;
        if (chatTranscriptParserFor(record.family) == null) continue;
        final updated = record.updatedAt;
        // Records arrive newest-first, so the first live one is the pane's own
        // unless a second pane in the same directory raced it.
        if (updated != null && updated.isBefore(floor)) continue;
        chosen = record;
        break;
      }
      if (chosen == null) return;
      _path = chosen.filePath;
      _sessionId = chosen.sessionId;
      _family = chosen.family;
      _parser = chatTranscriptParserFor(chosen.family);
    } on Object {
      // A backend that cannot scan (SSH without the agent installed, a WSL
      // distro that stopped) just leaves the pane unresolved.
    } finally {
      _resolving = false;
    }
  }

  void _forget() {
    _path = null;
    _sessionId = null;
    _family = null;
    _parser = null;
  }

  ChatTranscriptUnavailable _unavailable() {
    if (_directory().trim().isEmpty) {
      return ChatTranscriptUnavailable.noDirectory;
    }
    if (_path != null) return ChatTranscriptUnavailable.unsupportedFamily;
    return ChatTranscriptUnavailable.noSessionFile;
  }

  /// A turn is in flight while the newest row is a prompt with no answer yet,
  /// or while a tool call has no result.
  static bool _isBusy(List<ChatTranscriptRow> rows) {
    if (rows.isEmpty) return false;
    for (final row in rows.reversed) {
      if (row.kind == ChatTranscriptRowKind.user) return true;
      if (row.kind == ChatTranscriptRowKind.tool && row.running) return true;
      if (row.kind == ChatTranscriptRowKind.assistant ||
          row.kind == ChatTranscriptRowKind.thought) {
        return false;
      }
    }
    return false;
  }

  void _emit(ChatTranscriptSnapshot snapshot) {
    if (_disposed) return;
    if (_transcript.value == snapshot) return;
    _transcript.value = snapshot;
  }
}
