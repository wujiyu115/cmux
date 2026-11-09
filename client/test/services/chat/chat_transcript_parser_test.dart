import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/chat_transcript_parser.dart';
import 'package:teampilot/services/chat/chat_transcript_row.dart';
import 'package:teampilot/services/cli/sessions/agent_cli_sessions.dart';

List<int> _jsonl(List<Object?> records) =>
    utf8.encode('${records.map(jsonEncode).join('\n')}\n');

Map<String, Object?> _toolUse(String id, String name, Object? input) => {
  'type': 'tool_use',
  'id': id,
  'name': name,
  'input': input,
};

void main() {
  const parser = ClaudeStyleChatTranscriptParser(AgentCliFamily.claude);

  test('reads a turn as user, thought, answer, and tool rows', () {
    final bytes = _jsonl([
      // Bookkeeping the CLI writes around the conversation.
      {'type': 'mode', 'mode': 'normal'},
      {'type': 'file-history-snapshot', 'snapshot': <String, Object?>{}},
      {
        'type': 'user',
        'uuid': 'u1',
        'timestamp': '2026-11-09T10:00:00.000Z',
        'message': {'role': 'user', 'content': 'run the tests'},
      },
      {
        'type': 'assistant',
        'uuid': 'a1',
        'timestamp': '2026-11-09T10:00:01.000Z',
        'message': {
          'id': 'msg_1',
          'role': 'assistant',
          'content': [
            {'type': 'thinking', 'thinking': 'they want the suite'},
            {'type': 'text', 'text': 'Running them now.'},
            _toolUse('t1', 'Bash', {'command': 'flutter test\n--coverage'}),
          ],
        },
      },
      {
        'type': 'user',
        'uuid': 'u2',
        'message': {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 't1', 'content': 'ok\n'},
          ],
        },
      },
      // A subagent's own conversation, not this one.
      {
        'type': 'assistant',
        'uuid': 'a2',
        'isSidechain': true,
        'message': {
          'id': 'msg_2',
          'content': [
            {'type': 'text', 'text': 'sidechain noise'},
          ],
        },
      },
      // Hook bookkeeping, not conversation.
      {'type': 'system', 'subtype': 'stop_hook_summary', 'hookCount': 2},
    ]);

    final rows = parser.parse(bytes);

    expect(rows.map((row) => row.kind), [
      ChatTranscriptRowKind.user,
      ChatTranscriptRowKind.thought,
      ChatTranscriptRowKind.assistant,
      ChatTranscriptRowKind.tool,
    ]);
    expect(rows[0].text, 'run the tests');
    expect(rows[0].at, DateTime.utc(2026, 11, 9, 10));
    expect(rows[1].text, 'they want the suite');
    expect(rows[2].text, 'Running them now.');
    expect(rows[3].toolName, 'Bash');
    // First line only: a multi-line command is still one row header.
    expect(rows[3].detail, 'flutter test');
    expect(rows[3].running, isFalse);
    expect(rows[3].text, 'ok');
  });

  test('a tool call with no result yet stays running', () {
    final rows = parser.parse(
      _jsonl([
        {
          'type': 'assistant',
          'message': {
            'id': 'msg_1',
            'content': [
              _toolUse('t9', 'Read', {'file_path': 'lib/main.dart'}),
            ],
          },
        },
      ]),
    );

    expect(rows.single.kind, ChatTranscriptRowKind.tool);
    expect(rows.single.running, isTrue);
    expect(rows.single.detail, 'lib/main.dart');
  });

  test('a streaming rewrite of one message does not duplicate rows', () {
    Map<String, Object?> assistant(List<Object?> blocks) => {
      'type': 'assistant',
      'message': {'id': 'msg_1', 'content': blocks},
    };
    final bytes = _jsonl([
      assistant([
        {'type': 'text', 'text': 'Hel'},
      ]),
      // Same message id, same block run, longer text: the last write wins.
      assistant([
        {'type': 'text', 'text': 'Hello'},
      ]),
      // A second block run appends a second paragraph.
      assistant([
        {'type': 'text', 'text': 'Hello'},
        {'type': 'text', 'text': 'world'},
      ]),
    ]);

    final rows = parser.parse(bytes);

    expect(rows, hasLength(1));
    expect(rows.single.text, 'Hello\n\nworld');
  });

  test(
    'consecutive text blocks read as one paragraph run, tools split them',
    () {
      final rows = parser.parse(
        _jsonl([
          {
            'type': 'assistant',
            'message': {
              'id': 'msg_1',
              'content': [
                {'type': 'text', 'text': 'first'},
                {'type': 'text', 'text': 'second'},
                _toolUse('t1', 'Grep', {'pattern': 'TODO'}),
                {'type': 'text', 'text': 'third'},
              ],
            },
          },
        ]),
      );

      expect(rows.map((row) => row.kind), [
        ChatTranscriptRowKind.assistant,
        ChatTranscriptRowKind.tool,
        ChatTranscriptRowKind.assistant,
      ]);
      expect(rows[0].text, 'first\n\nsecond');
      expect(rows[2].text, 'third');
      expect(rows[1].detail, 'TODO');
    },
  );

  test('meta and empty prompts are dropped', () {
    final rows = parser.parse(
      _jsonl([
        {
          'type': 'user',
          'isMeta': true,
          'message': {'content': 'caveat: system injected'},
        },
        {
          'type': 'user',
          'message': {'content': '   '},
        },
        {
          'type': 'user',
          'message': {
            'content': [
              {'type': 'tool_result', 'tool_use_id': 'gone', 'content': 'x'},
            ],
          },
        },
      ]),
    );

    expect(rows, isEmpty);
  });

  test('compaction becomes a notice row', () {
    final rows = parser.parse(
      _jsonl([
        {'type': 'system', 'subtype': 'compact_boundary', 'uuid': 's1'},
      ]),
    );

    expect(rows.single.kind, ChatTranscriptRowKind.notice);
    expect(rows.single.text, 'compacted');
  });

  test('long tool output is clipped instead of dominating the transcript', () {
    final rows = parser.parse(
      _jsonl([
        {
          'type': 'assistant',
          'message': {
            'id': 'msg_1',
            'content': [
              _toolUse('t1', 'Bash', {'command': 'cat big.log'}),
            ],
          },
        },
        {
          'type': 'user',
          'message': {
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 't1',
                'content': 'x' * 9000,
              },
            ],
          },
        },
      ]),
    );

    expect(rows.single.text.length, lessThanOrEqualTo(4001));
  });

  test('a family without a parser reports unsupported', () {
    expect(chatTranscriptParserFor(AgentCliFamily.codex), isNull);
    expect(chatTranscriptParserFor(AgentCliFamily.claude), isNotNull);
    expect(chatTranscriptParserFor(AgentCliFamily.qoder), isNotNull);
  });

  test('rows round-trip through the wire form', () {
    final row = ChatTranscriptRow(
      id: 'msg_1#tool:t1',
      kind: ChatTranscriptRowKind.tool,
      toolName: 'Edit',
      detail: 'lib/main.dart',
      text: 'ok',
      running: true,
      at: DateTime.fromMillisecondsSinceEpoch(1763000000000, isUtc: true),
    );

    expect(ChatTranscriptRow.fromJson(row.toJson()), row);
  });
}
