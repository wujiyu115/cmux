import 'dart:convert';

import '../cli/sessions/agent_cli_sessions.dart';
import 'chat_transcript_row.dart';

/// Turns one agent CLI session store into rendered rows.
///
/// A parser is called with the whole session file on every change: agent CLIs
/// rewrite early records (titles, costs, streaming assistant blocks), so an
/// incremental append-only parse would drift. Files are a few hundred KB in
/// practice and the caller polls at human speed, so a full pass is cheaper
/// than reconciling patches.
abstract interface class ChatTranscriptParser {
  /// Store family this parser understands.
  AgentCliFamily get family;

  /// Rows in conversation order, oldest first.
  List<ChatTranscriptRow> parse(List<int> bytes);
}

/// The parser for a family, or null when its store has no parser yet.
ChatTranscriptParser? chatTranscriptParserFor(AgentCliFamily family) =>
    switch (family) {
      AgentCliFamily.claude || AgentCliFamily.qoder =>
        const ClaudeStyleChatTranscriptParser(AgentCliFamily.claude),
      AgentCliFamily.pi ||
      AgentCliFamily.ohMyPi => const PiChatTranscriptParser(),
      _ => null,
    };

/// Claude Code / Qoder session JSONL (`~/.claude/projects/…/*.jsonl`).
///
/// Records are `{type, message, uuid, timestamp, isSidechain, …}` where
/// `message.content` is either a string or a block list of `text`,
/// `thinking`, `tool_use`, `tool_result`. Everything else in the file is
/// bookkeeping (`attachment`, `file-history-snapshot`, `mode`,
/// `permission-mode`, `cost-state`, `last-prompt`, hook summaries) and is
/// skipped rather than shown as conversation.
class ClaudeStyleChatTranscriptParser implements ChatTranscriptParser {
  const ClaudeStyleChatTranscriptParser(this.family);

  @override
  final AgentCliFamily family;

  /// Tool output is context, not conversation: long results are clipped so one
  /// `cat` of a big file cannot dominate the transcript (and the wire payload
  /// to the phone).
  static const int maxToolText = 4000;

  /// One-line tool target length.
  static const int maxDetail = 120;

  @override
  List<ChatTranscriptRow> parse(List<int> bytes) {
    final rows = <ChatTranscriptRow>[];
    final openTools = <String, int>{};

    for (final line in _jsonLines(bytes)) {
      // Subagent traffic belongs to the subagent's own conversation.
      if (line['isSidechain'] == true) continue;
      final at = _timestamp(line['timestamp']);
      switch (line['type']) {
        case 'user':
          if (line['isMeta'] == true) continue;
          _appendUser(line, at, rows, openTools);
        case 'assistant':
          _appendAssistant(line, at, rows, openTools);
        case 'system':
          if (line['subtype'] == 'compact_boundary') {
            _add(
              rows,
              ChatTranscriptRow(
                id: 'system:${line['uuid'] ?? rows.length}',
                kind: ChatTranscriptRowKind.notice,
                text: 'compacted',
                at: at,
              ),
            );
          }
      }
    }

    // A tool call with no result yet is still running.
    for (final entry in openTools.entries) {
      final index = entry.value;
      if (index < 0 || index >= rows.length) continue;
      rows[index] = rows[index].copyWith(running: true);
    }
    return rows;
  }

  void _appendUser(
    Map<String, Object?> line,
    DateTime? at,
    List<ChatTranscriptRow> rows,
    Map<String, int> openTools,
  ) {
    final message = line['message'];
    if (message is! Map<String, Object?>) return;
    final content = message['content'];
    final baseId = _idOf(line, message);
    if (content is String) {
      if (content.trim().isEmpty) return;
      _add(
        rows,
        ChatTranscriptRow(
          id: '$baseId#text',
          kind: ChatTranscriptRowKind.user,
          text: content,
          at: at,
        ),
      );
      return;
    }
    if (content is! List) return;
    var index = 0;
    for (final block in content) {
      if (block is! Map<String, Object?>) continue;
      switch (block['type']) {
        case 'text':
          final text = _asString(block['text']);
          if (text.trim().isEmpty) continue;
          _add(
            rows,
            ChatTranscriptRow(
              id: '$baseId#text$index',
              kind: ChatTranscriptRowKind.user,
              text: text,
              at: at,
            ),
          );
        case 'tool_result':
          final toolUseId = _asString(block['tool_use_id']);
          final rowIndex = openTools.remove(toolUseId);
          if (rowIndex == null) continue;
          final output = _toolResultText(block['content']);
          if (output.isEmpty) continue;
          rows[rowIndex] = rows[rowIndex].copyWith(
            text: _clip(output, maxToolText),
            running: false,
          );
      }
      index++;
    }
  }

  void _appendAssistant(
    Map<String, Object?> line,
    DateTime? at,
    List<ChatTranscriptRow> rows,
    Map<String, int> openTools,
  ) {
    final message = line['message'];
    if (message is! Map<String, Object?>) return;
    final content = message['content'];
    final baseId = _idOf(line, message);
    if (content is String) {
      if (content.trim().isEmpty) return;
      _replaceOrAdd(
        rows,
        ChatTranscriptRow(
          id: '$baseId#text',
          kind: ChatTranscriptRowKind.assistant,
          text: content,
          at: at,
        ),
      );
      return;
    }
    if (content is! List) return;

    // Streaming rewrites the same message id as more blocks land, so rows are
    // keyed by block position kind and replaced in place. Consecutive text (or
    // thinking) blocks of one message read as one paragraph run, and a tool
    // call interrupts that run, so the block order is preserved.
    final runs = <String, List<String>>{};
    var runIndex = 0;
    String? runKind;
    void flushRun() {
      final kind = runKind;
      if (kind == null) return;
      final parts = runs.remove(kind) ?? const <String>[];
      runKind = null;
      final text = _joinBlocks(parts);
      if (text.isEmpty) return;
      _replaceOrAdd(
        rows,
        ChatTranscriptRow(
          id: '$baseId#$kind${runIndex - 1}',
          kind: kind == 'thinking'
              ? ChatTranscriptRowKind.thought
              : ChatTranscriptRowKind.assistant,
          text: text,
          at: at,
        ),
      );
    }

    for (final block in content) {
      if (block is! Map<String, Object?>) continue;
      final type = _asString(block['type']);
      if (type == 'text' || type == 'thinking') {
        if (runKind != type) {
          flushRun();
          runKind = type;
          runIndex++;
          runs[type] = [];
        }
        runs[type]!.add(
          _asString(type == 'text' ? block['text'] : block['thinking']),
        );
        continue;
      }
      if (type != 'tool_use') continue;
      flushRun();
      final toolId = _asString(block['id']);
      final row = ChatTranscriptRow(
        id: '$baseId#tool:${toolId.isEmpty ? runIndex : toolId}',
        kind: ChatTranscriptRowKind.tool,
        toolName: _asString(block['name']),
        detail: _toolDetail(block['input']),
        running: true,
        at: at,
      );
      final existing = rows.indexWhere((r) => r.id == row.id);
      if (existing >= 0) {
        rows[existing] = row;
        openTools[toolId] = existing;
      } else {
        openTools[toolId] = rows.length;
        rows.add(row);
      }
    }
    flushRun();
  }

  /// Rows keyed by id are replaced in place; a brand-new id appends.
  void _replaceOrAdd(List<ChatTranscriptRow> rows, ChatTranscriptRow row) {
    final existing = rows.indexWhere((r) => r.id == row.id);
    if (existing >= 0) {
      rows[existing] = row;
      return;
    }
    rows.add(row);
  }

  void _add(List<ChatTranscriptRow> rows, ChatTranscriptRow row) {
    if (row.isEmpty) return;
    rows.add(row);
  }

  /// Assistant records carry `message.id`; fall back to the record uuid so a
  /// store that omits it still gets stable ids.
  String _idOf(Map<String, Object?> line, Map<String, Object?> message) {
    final id = _asString(message['id']);
    if (id.isNotEmpty) return id;
    final uuid = _asString(line['uuid']);
    return uuid.isNotEmpty ? uuid : 'row';
  }
}

/// pi / oh-my-pi session JSONL (`~/.pi/agent/sessions/…/*.jsonl`).
///
/// Every entry is `{type, id, parentId, timestamp}`; conversation lives in
/// `message` entries whose `message.role` is `user`, `assistant`, or
/// `toolResult`. Assistant content is a block list of `text`, `thinking`, and
/// `toolCall` (`{id, name, arguments}`); a `toolResult` carries the matching
/// `toolCallId`, so tool output is attached to the call it answers.
/// `session`, `model_change`, `thinking_level_change` are bookkeeping;
/// `compaction` is shown as the same notice Claude's `compact_boundary` gets.
class PiChatTranscriptParser implements ChatTranscriptParser {
  const PiChatTranscriptParser();

  static const int maxToolText = ClaudeStyleChatTranscriptParser.maxToolText;
  static const int maxDetail = ClaudeStyleChatTranscriptParser.maxDetail;

  @override
  AgentCliFamily get family => AgentCliFamily.pi;

  @override
  List<ChatTranscriptRow> parse(List<int> bytes) {
    final rows = <ChatTranscriptRow>[];
    final openTools = <String, int>{};

    for (final line in _jsonLines(bytes)) {
      switch (line['type']) {
        case 'message':
          _appendMessage(line, rows, openTools);
        case 'compaction':
          rows.add(
            ChatTranscriptRow(
              id: 'compaction:${line['id'] ?? rows.length}',
              kind: ChatTranscriptRowKind.notice,
              text: 'compacted',
              at: _timestamp(line['timestamp']),
            ),
          );
      }
    }

    // A call with no result entry yet is still running.
    for (final entry in openTools.entries) {
      final index = entry.value;
      if (index < 0 || index >= rows.length) continue;
      rows[index] = rows[index].copyWith(running: true);
    }
    return rows;
  }

  void _appendMessage(
    Map<String, Object?> line,
    List<ChatTranscriptRow> rows,
    Map<String, int> openTools,
  ) {
    final message = line['message'];
    if (message is! Map<String, Object?>) return;
    final baseId = _asString(line['id']);
    final at = _timestamp(line['timestamp']);
    final content = message['content'];

    switch (_asString(message['role'])) {
      case 'user':
        if (content is String) {
          if (content.trim().isEmpty) return;
          rows.add(
            ChatTranscriptRow(
              id: '$baseId#text',
              kind: ChatTranscriptRowKind.user,
              text: content,
              at: at,
            ),
          );
          return;
        }
        if (content is! List) return;
        var index = 0;
        for (final block in content) {
          if (block is! Map<String, Object?>) continue;
          if (block['type'] != 'text') continue;
          final text = _asString(block['text']);
          if (text.trim().isEmpty) continue;
          rows.add(
            ChatTranscriptRow(
              id: '$baseId#text$index',
              kind: ChatTranscriptRowKind.user,
              text: text,
              at: at,
            ),
          );
          index++;
        }
      case 'assistant':
        if (content is String) {
          if (content.trim().isEmpty) return;
          rows.add(
            ChatTranscriptRow(
              id: '$baseId#text',
              kind: ChatTranscriptRowKind.assistant,
              text: content,
              at: at,
            ),
          );
          return;
        }
        if (content is! List) return;
        // Consecutive text (or thinking) blocks of one message are one
        // paragraph run; a tool call interrupts the run.
        final runs = <String, List<String>>{};
        var runIndex = 0;
        String? runKind;
        void flushRun() {
          final kind = runKind;
          if (kind == null) return;
          final parts = runs.remove(kind) ?? const <String>[];
          runKind = null;
          final text = _joinBlocks(parts);
          if (text.isEmpty) return;
          rows.add(
            ChatTranscriptRow(
              id: '$baseId#$kind${runIndex - 1}',
              kind: kind == 'thinking'
                  ? ChatTranscriptRowKind.thought
                  : ChatTranscriptRowKind.assistant,
              text: text,
              at: at,
            ),
          );
        }

        for (final block in content) {
          if (block is! Map<String, Object?>) continue;
          final type = _asString(block['type']);
          if (type == 'text' || type == 'thinking') {
            if (runKind != type) {
              flushRun();
              runKind = type;
              runIndex++;
              runs[type] = [];
            }
            runs[type]!.add(
              _asString(type == 'text' ? block['text'] : block['thinking']),
            );
            continue;
          }
          if (type != 'toolCall') continue;
          flushRun();
          final toolId = _asString(block['id']);
          openTools[toolId] = rows.length;
          rows.add(
            ChatTranscriptRow(
              id: '$baseId#tool:${toolId.isEmpty ? runIndex : toolId}',
              kind: ChatTranscriptRowKind.tool,
              toolName: _asString(block['name']),
              detail: _toolDetail(block['arguments']),
              running: true,
              at: at,
            ),
          );
        }
        flushRun();
      case 'toolResult':
        final toolId = _asString(message['toolCallId']);
        final rowIndex = openTools.remove(toolId);
        if (rowIndex == null) return;
        final output = _toolResultText(content);
        if (output.isEmpty) {
          rows[rowIndex] = rows[rowIndex].copyWith(running: false);
          return;
        }
        rows[rowIndex] = rows[rowIndex].copyWith(
          text: _clip(output, maxToolText),
          running: false,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Field helpers
// ---------------------------------------------------------------------------
String _asString(Object? raw) => raw is String ? raw : '';

DateTime? _timestamp(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

/// Consecutive text blocks of one message are one paragraph run.
String _joinBlocks(List<String> parts) {
  final kept = [
    for (final part in parts)
      if (part.trim().isNotEmpty) part.trimRight(),
  ];
  return kept.join('\n\n');
}

/// Tool result content is a string or a block list of `{type: text, text: …}`.
String _toolResultText(Object? raw) {
  if (raw is String) return raw;
  if (raw is! List) return '';
  final parts = <String>[];
  for (final block in raw) {
    if (block is Map<String, Object?> && block['type'] == 'text') {
      parts.add(_asString(block['text']));
    }
  }
  return _joinBlocks(parts);
}

/// One-line summary of a tool call, chosen by the argument that identifies its
/// target for this CLI family.
String _toolDetail(Object? input) {
  if (input is! Map<String, Object?>) return '';
  for (final key in const [
    'command',
    'file_path',
    'notebook_path',
    'path',
    'pattern',
    'url',
    'query',
    'description',
    'prompt',
    'skill',
  ]) {
    final value = input[key];
    if (value is String && value.trim().isNotEmpty) {
      return _clip(
        value.trim().split('\n').first,
        ClaudeStyleChatTranscriptParser.maxDetail,
      );
    }
  }
  if (input.isEmpty) return '';
  return _clip(jsonEncode(input), ClaudeStyleChatTranscriptParser.maxDetail);
}

String _clip(String value, int limit) {
  final collapsed = value.replaceAll('\r\n', '\n').trimRight();
  return collapsed.length > limit
      ? '${collapsed.substring(0, limit)}…'
      : collapsed;
}

List<Map<String, Object?>> _jsonLines(List<int> bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return [
    for (final line in const LineSplitter().convert(text))
      if (_tryJsonLine(line) case final json?) json,
  ];
}

Map<String, Object?>? _tryJsonLine(String line) {
  if (line.isEmpty) return null;
  try {
    final decoded = jsonDecode(line);
    return decoded is Map<String, Object?> ? decoded : null;
  } on Object {
    return null;
  }
}
