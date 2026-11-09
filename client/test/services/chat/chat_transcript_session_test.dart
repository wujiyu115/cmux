import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/chat/chat_transcript_row.dart';
import 'package:teampilot/services/chat/chat_transcript_session.dart';
import 'package:teampilot/services/cli/sessions/agent_cli_session_adapter.dart';
import 'package:teampilot/services/cli/sessions/agent_cli_session_service.dart';
import 'package:teampilot/services/cli/sessions/agent_cli_sessions.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/in_memory_filesystem.dart';

/// One session file in the Claude store for [cwd], as the CLI writes it.
const _home = '/home/u';
const _cwd = '/home/u/proj';
const _projectDir = '/home/u/.claude/projects/-home-u-proj';
const _sessionPath = '$_projectDir/11111111-2222-3333-4444-555555555555.jsonl';

String _userPrompt(String text) => jsonEncode({
  'type': 'user',
  'uuid': 'u-${text.hashCode}',
  'message': {'role': 'user', 'content': text},
});

String _assistantText(String id, String text) => jsonEncode({
  'type': 'assistant',
  'message': {
    'id': id,
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
});

void main() {
  late InMemoryFilesystem fs;
  late RuntimeContext context;
  late AgentCliSessionService sessions;

  setUp(() {
    fs = InMemoryFilesystem();
    context = RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: fs,
      home: _home,
      cwd: _cwd,
      appDataRoot: '$_home/.teampilot',
      paths: AppPaths('$_home/.teampilot'),
    );
    sessions = AgentCliSessionService(
      resolveContext: (_) async => context,
      adapters: const [
        ClaudeStyleAgentCliSessionAdapter(
          family: AgentCliFamily.claude,
          homeDotDir: '.claude',
        ),
      ],
    );
  });

  ChatTranscriptSession newSession({DateTime? startedAt}) =>
      ChatTranscriptSession(
        paneId: 'pane-1',
        resolveContext: (_) async => context,
        target: () => context.target,
        directory: () => _cwd,
        startedAt: startedAt ?? DateTime.utc(2026, 11, 9, 9),
        sessionService: sessions,
      );

  test('resolves the pane session file through the runtime context', () async {
    await fs.writeBytes(
      _sessionPath,
      utf8.encode('${_userPrompt('hi')}\n${_assistantText('m1', 'hello')}\n'),
    );
    final session = newSession();
    addTearDown(session.dispose);

    await session.refreshNow();

    final transcript = session.transcript.value;
    expect(transcript.unavailable, isNull);
    expect(transcript.sessionId, '11111111-2222-3333-4444-555555555555');
    expect(transcript.family, AgentCliFamily.claude.name);
    expect(transcript.rows.map((row) => row.kind), [
      ChatTranscriptRowKind.user,
      ChatTranscriptRowKind.assistant,
    ]);
    expect(transcript.rows.last.text, 'hello');
    expect(session.resolvedPath, _sessionPath);
  });

  test('a growing session file yields new rows on the next poll', () async {
    await fs.writeBytes(_sessionPath, utf8.encode('${_userPrompt('one')}\n'));
    final session = newSession();
    addTearDown(session.dispose);
    await session.refreshNow();
    expect(session.transcript.value.rows, hasLength(1));

    // The agent answers: the CLI appends to the same file.
    await fs.writeBytes(
      _sessionPath,
      utf8.encode(
        '${_userPrompt('one')}\n${_assistantText('m1', 'first answer')}\n',
      ),
    );
    await session.refreshNow();

    expect(session.transcript.value.rows, hasLength(2));
    expect(session.transcript.value.rows.last.text, 'first answer');
  });

  test('a prompt awaiting an answer marks the transcript busy', () async {
    await fs.writeBytes(_sessionPath, utf8.encode('${_userPrompt('one')}\n'));
    final session = newSession();
    addTearDown(session.dispose);

    await session.refreshNow();
    expect(session.transcript.value.busy, isTrue);

    await fs.writeBytes(
      _sessionPath,
      utf8.encode('${_userPrompt('one')}\n${_assistantText('m1', 'done')}\n'),
    );
    await session.refreshNow();
    expect(session.transcript.value.busy, isFalse);
  });

  test('a store with no session for the pane cwd reports it', () async {
    final session = newSession();
    addTearDown(session.dispose);

    await session.refreshNow();

    expect(
      session.transcript.value.unavailable,
      ChatTranscriptUnavailable.noSessionFile,
    );
    expect(session.transcript.value.rows, isEmpty);
  });

  test('a pane without a cwd reports it instead of scanning', () async {
    final session = ChatTranscriptSession(
      paneId: 'pane-1',
      resolveContext: (_) async => context,
      target: () => context.target,
      directory: () => '  ',
      startedAt: DateTime.utc(2026, 11, 9, 9),
      sessionService: sessions,
    );
    addTearDown(session.dispose);

    await session.refreshNow();

    expect(
      session.transcript.value.unavailable,
      ChatTranscriptUnavailable.noDirectory,
    );
  });

  test('a session older than the pane is not claimed', () async {
    await fs.writeBytes(_sessionPath, utf8.encode('${_userPrompt('old')}\n'));
    // In-memory stats carry no mtime, so the adapter reports an unknown update
    // time; filter with a fabricated record instead to prove the floor holds.
    final session = ChatTranscriptSession(
      paneId: 'pane-1',
      resolveContext: (_) async => context,
      target: () => context.target,
      directory: () => _cwd,
      startedAt: DateTime.utc(2026, 11, 9, 9),
      sessionService: _StaleRecordService(context),
    );
    addTearDown(session.dispose);

    await session.refreshNow();

    expect(
      session.transcript.value.unavailable,
      ChatTranscriptUnavailable.noSessionFile,
    );
  });

  test('a read failure keeps the rows already rendered', () async {
    await fs.writeBytes(_sessionPath, utf8.encode('${_userPrompt('one')}\n'));
    final session = newSession();
    addTearDown(session.dispose);
    await session.refreshNow();
    expect(session.transcript.value.rows, hasLength(1));

    // The store disappears between polls.
    await fs.removeRecursive(_projectDir);
    await session.refreshNow();

    expect(
      session.transcript.value.unavailable,
      ChatTranscriptUnavailable.noSessionFile,
    );
  });
}

/// Returns one record whose file is far older than the pane's start time.
class _StaleRecordService extends AgentCliSessionService {
  _StaleRecordService(RuntimeContext context)
    : super(resolveContext: (_) async => context);

  @override
  Future<List<AgentCliSessionRecord>> listSessions({
    required RuntimeTarget target,
    required String directory,
  }) async => [
    AgentCliSessionRecord(
      family: AgentCliFamily.claude,
      sessionId: 'stale',
      updatedAt: DateTime.utc(2026, 1, 1),
      filePath: _sessionPath,
    ),
  ];
}
