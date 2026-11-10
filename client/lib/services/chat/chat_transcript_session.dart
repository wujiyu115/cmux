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
  bool _borrowed = false;
  bool _resolving = false;

  /// The prompt the user just typed, until the store shows it landing.
  ///
  /// Resolution can only guess before the first prompt: two panes in one
  /// directory, or a session another window keeps writing, look identical to a
  /// resumed session. Sending settles it — the CLI records the prompt in the
  /// file its pane's agent is actually appending to, so a prompt that shows up
  /// in a different file than the one being read is proof of the real owner.
  String? _pendingPrompt;
  DateTime? _pendingSince;
  bool _refreshing = false;
  bool _disposed = false;

  /// Rows for the UI and the paired phone; identical payload either way.
  ValueListenable<ChatTranscriptSnapshot> get transcript => _transcript;

  /// Store file being read, once resolved.
  String? get resolvedPath => _path;

  /// Announces a prompt that was just written to the pane's PTY, so the next
  /// polls can follow it to the session file that receives it.
  void markPromptSent(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _pendingPrompt = trimmed;
    _pendingSince = DateTime.now();
  }

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
      var rows = _parser!.parse(bytes);
      if (!_pendingLanded(rows)) {
        // The prompt went into some other file, so that file — not this one —
        // is the pane's session. Render it now rather than one poll later.
        rows = await _followPendingPrompt(context, path: path) ?? rows;
        if (_disposed) return;
      }
      _emit(
        ChatTranscriptSnapshot(
          rows: rows,
          sessionId: _sessionId,
          family: _family?.name,
          busy: _isBusy(rows),
          borrowed: _borrowed,
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

  /// True once [rows] carries the prompt that was just sent.
  bool _pendingLanded(List<ChatTranscriptRow> rows) {
    final prompt = _pendingPrompt;
    if (prompt == null) return false;
    for (final row in rows.reversed) {
      if (row.kind != ChatTranscriptRowKind.user) continue;
      if (_samePrompt(row.text, prompt)) {
        _pendingPrompt = null;
        _pendingSince = null;
        return true;
      }
    }
    return false;
  }

  /// Rebinds to whichever session file the prompt actually landed in, and
  /// returns the rows of that file so they can be shown on the same poll.
  ///
  /// Only files touched in the last few minutes are read, and only their
  /// newest prompt matters, so this stays one small read per candidate on the
  /// polls that follow a send.
  Future<List<ChatTranscriptRow>?> _followPendingPrompt(
    RuntimeContext context, {
    required String path,
  }) async {
    final prompt = _pendingPrompt;
    final since = _pendingSince;
    if (prompt == null) return null;
    if (since != null && DateTime.now().difference(since).inSeconds > 20) {
      _pendingPrompt = null;
      _pendingSince = null;
      return null;
    }
    final directory = _directory().trim();
    if (directory.isEmpty) return null;
    final List<AgentCliSessionRecord> records;
    try {
      records = await _sessions.listSessions(
        target: _target(),
        directory: directory,
      );
    } on Object {
      return null;
    }
    if (_disposed) return null;
    final recent = DateTime.now().subtract(const Duration(minutes: 3));
    for (final record in records) {
      final candidate = record.filePath;
      if (candidate == null || candidate == path) continue;
      final parser = chatTranscriptParserFor(record.family);
      if (parser == null) continue;
      final updated = record.updatedAt;
      if (updated != null && updated.isBefore(recent)) continue;
      final int size;
      try {
        final stat = await context.filesystem.stat(candidate);
        if (!stat.isFile) continue;
        size = stat.size ?? 0;
      } on Object {
        continue;
      }
      if (size == 0) continue;
      final offset = size > maxBytes ? size - maxBytes : 0;
      final List<int> bytes;
      try {
        bytes =
            await context.filesystem.readBytesRange(
              candidate,
              offset,
              size - offset,
            ) ??
            const <int>[];
      } on Object {
        continue;
      }
      if (_disposed) return null;
      final rows = parser.parse(bytes);
      final landed = rows.any(
        (row) =>
            row.kind == ChatTranscriptRowKind.user &&
            _samePrompt(row.text, prompt),
      );
      if (!landed) continue;
      _path = candidate;
      _sessionId = record.sessionId;
      _family = record.family;
      // A prompt that landed here settles the question the guess could not.
      _borrowed = false;
      _parser = parser;
      _pendingPrompt = null;
      _pendingSince = null;
      return rows;
    }
    return null;
  }

  /// Prompts are compared after collapsing whitespace: a CLI may trim, wrap, or
  /// re-quote what it stored.
  static bool _samePrompt(String stored, String sent) =>
      _squeeze(stored) == _squeeze(sent);

  static String _squeeze(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

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
      AgentCliSessionRecord? own;
      AgentCliSessionRecord? borrowed;
      for (final record in records) {
        if (record.filePath == null) continue;
        if (chatTranscriptParserFor(record.family) == null) continue;
        // A pane can only own a session its PTY started. A session another
        // window is still writing keeps a fresh mtime forever, so mtime alone
        // would let one pane publish — and answer for — another's conversation.
        final created = record.createdAt;
        if (created != null && !created.isBefore(floor)) {
          own = record;
          break;
        }
        // Borrowed means "this file moved after the pane existed": a resumed
        // session appends its startup records, while another window's session
        // was already running when the pane launched and proves nothing here.
        final updated = record.updatedAt;
        if (updated != null && updated.isBefore(_startedAt)) continue;
        borrowed ??= record;
      }
      final chosen = own ?? borrowed;
      if (chosen == null) return;
      _path = chosen.filePath;
      _sessionId = chosen.sessionId;
      _family = chosen.family;
      _borrowed = own == null;
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
    _borrowed = false;
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
