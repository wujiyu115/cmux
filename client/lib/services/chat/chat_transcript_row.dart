import 'package:flutter/foundation.dart';

/// What a rendered conversation row represents.
///
/// The set is deliberately small: it is what a terminal-backed transcript can
/// recover from an agent CLI's own session store, and what both the desktop
/// pane and the phone mirror can draw without knowing the CLI.
enum ChatTranscriptRowKind {
  /// A prompt the human sent.
  user,

  /// Agent output meant for the human.
  assistant,

  /// Agent reasoning (`thinking` blocks). Collapsed by default.
  thought,

  /// One tool invocation: name plus a one-line target, expandable to detail.
  tool,

  /// Transcript-level information that is not part of the conversation
  /// (compaction boundaries, interrupted turns, …).
  notice,
}

/// One row of a terminal-backed chat transcript.
///
/// [id] is stable for the life of the underlying transcript, so a rebuild
/// re-uses its list element instead of remounting every row on each poll.
@immutable
class ChatTranscriptRow {
  const ChatTranscriptRow({
    required this.id,
    required this.kind,
    this.text = '',
    this.toolName = '',
    this.detail = '',
    this.running = false,
    this.at,
  });

  factory ChatTranscriptRow.fromJson(Map<String, Object?> json) {
    final rawKind = json['kind'] as String? ?? '';
    final kind = ChatTranscriptRowKind.values.firstWhere(
      (value) => value.name == rawKind,
      orElse: () => ChatTranscriptRowKind.notice,
    );
    final at = json['at'];
    return ChatTranscriptRow(
      id: json['id'] as String? ?? '',
      kind: kind,
      text: json['text'] as String? ?? '',
      toolName: json['toolName'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      running: json['running'] == true,
      at: at is int
          ? DateTime.fromMillisecondsSinceEpoch(at, isUtc: true)
          : null,
    );
  }

  final String id;
  final ChatTranscriptRowKind kind;

  /// Body text: the message, the thought, or the tool detail.
  final String text;

  /// Tool name for [ChatTranscriptRowKind.tool] rows (`Bash`, `Edit`, …).
  final String toolName;

  /// One-line target shown next to [toolName] (`npm test`, `lib/main.dart`).
  final String detail;

  /// True while the tool call has no matching result yet.
  final bool running;

  final DateTime? at;

  bool get isEmpty =>
      text.trim().isEmpty && toolName.trim().isEmpty && detail.trim().isEmpty;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'text': text,
    if (toolName.isNotEmpty) 'toolName': toolName,
    if (detail.isNotEmpty) 'detail': detail,
    if (running) 'running': true,
    if (at != null) 'at': at!.millisecondsSinceEpoch,
  };

  ChatTranscriptRow copyWith({
    String? text,
    String? detail,
    bool? running,
    DateTime? at,
  }) => ChatTranscriptRow(
    id: id,
    kind: kind,
    text: text ?? this.text,
    toolName: toolName,
    detail: detail ?? this.detail,
    running: running ?? this.running,
    at: at ?? this.at,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatTranscriptRow &&
          other.id == id &&
          other.kind == kind &&
          other.text == text &&
          other.toolName == toolName &&
          other.detail == detail &&
          other.running == running &&
          other.at == at;

  @override
  int get hashCode =>
      Object.hash(id, kind, text, toolName, detail, running, at);

  @override
  String toString() => 'ChatTranscriptRow(${kind.name}, $id)';
}

/// Why a pane has no transcript to show.
enum ChatTranscriptUnavailable {
  /// The pane has no cwd yet (no session started).
  noDirectory,

  /// None of the installed CLIs wrote a session for this panes's cwd.
  noSessionFile,

  /// A session was found, but its store format has no parser yet.
  unsupportedFamily,

  /// The transcript exists but could not be read.
  readFailed,
}

/// Immutable snapshot handed to the UI and, unchanged, to the paired phone.
@immutable
class ChatTranscriptSnapshot {
  const ChatTranscriptSnapshot({
    this.rows = const [],
    this.unavailable,
    this.sessionId,
    this.family,
    this.busy = false,
    this.borrowed = false,
  });

  final List<ChatTranscriptRow> rows;
  final ChatTranscriptUnavailable? unavailable;

  /// CLI session id backing this transcript, when one was resolved.
  final String? sessionId;

  /// Store family that produced [rows] (`claude`, `qoder`, …).
  final String? family;

  /// True while the newest turn has no closing boundary yet.
  final bool busy;

  /// The session was not started by this pane's PTY — it was adopted only
  /// because its file is still being written (a `--resume`d session looks the
  /// same). Worth saying out loud: a prompt here may not reach this agent.
  final bool borrowed;

  bool get isEmpty => rows.isEmpty;

  bool get isAvailable => unavailable == null;

  Map<String, Object?> toJson() => {
    'rows': [for (final row in rows) row.toJson()],
    if (unavailable != null) 'unavailable': unavailable!.name,
    if (sessionId != null) 'sessionId': sessionId,
    if (family != null) 'family': family,
    if (busy) 'busy': true,
    if (borrowed) 'borrowed': true,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatTranscriptSnapshot &&
          other.unavailable == unavailable &&
          other.sessionId == sessionId &&
          other.family == family &&
          other.busy == busy &&
          other.borrowed == borrowed &&
          listEquals(other.rows, rows);

  @override
  int get hashCode => Object.hash(
    unavailable,
    sessionId,
    family,
    busy,
    borrowed,
    Object.hashAll(rows),
  );
}
