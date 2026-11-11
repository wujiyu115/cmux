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

  test('a session this pane could not have started is not adopted', () async {
    // Another window keeps writing a session that began before this pane
    // existed; the pane's own session began after it. Picking the fresh mtime
    // would publish — and let the composer answer for — the wrong conversation.
    const foreign = '$_projectDir/00000000-0000-0000-0000-000000000000.jsonl';
    const own = '$_projectDir/99999999-9999-9999-9999-999999999999.jsonl';
    final foreignRecord = jsonEncode({
      'type': 'user',
      'timestamp': '2026-11-09T06:00:00.000Z',
      'message': {'role': 'user', 'content': 'someone else'},
    });
    final ownRecord = jsonEncode({
      'type': 'user',
      'timestamp': '2026-11-09T09:30:00.000Z',
      'message': {'role': 'user', 'content': 'mine'},
    });
    await fs.writeBytes(foreign, utf8.encode('$foreignRecord\n'));
    await fs.writeBytes(own, utf8.encode('$ownRecord\n'));

    final session = newSession();
    addTearDown(session.dispose);
    await session.refreshNow();

    expect(session.resolvedPath, own);
    expect(session.transcript.value.rows.single.text, 'mine');
  });

  test(
    'a resumed session, created before the pane, is still adopted',
    () async {
      // `--resume` keeps the original creation time, so the pane owns nothing
      // new; the fallback must still bind it or resume would lose its chat.
      final old = jsonEncode({
        'type': 'user',
        'timestamp': '2026-11-09T06:00:00.000Z',
        'message': {'role': 'user', 'content': 'resumed'},
      });
      await fs.writeBytes(_sessionPath, utf8.encode('$old\n'));

      final session = newSession();
      addTearDown(session.dispose);
      await session.refreshNow();

      expect(session.resolvedPath, _sessionPath);
      expect(session.transcript.value.rows.single.text, 'resumed');
    },
  );

  test(
    'a sent prompt follows itself to the session that received it',
    () async {
      // The guess bound this pane to another window's session; the pane's own
      // agent writes to a second file. Sending is the evidence that settles it.
      const foreign = '$_projectDir/00000000-0000-0000-0000-000000000000.jsonl';
      const own = '$_projectDir/99999999-9999-9999-9999-999999999999.jsonl';
      await fs.writeBytes(foreign, utf8.encode('${_userPrompt('theirs')}\n'));

      final session = newSession();
      addTearDown(session.dispose);
      await session.refreshNow();
      expect(session.resolvedPath, foreign);

      session.markPromptSent('mine now');
      await fs.writeBytes(own, utf8.encode('${_userPrompt('mine now')}\n'));
      await session.refreshNow();

      expect(session.resolvedPath, own);
      expect(session.transcript.value.rows.single.text, 'mine now');
    },
  );

  test('a prompt that lands where it is expected keeps the binding', () async {
    await fs.writeBytes(_sessionPath, utf8.encode('${_userPrompt('one')}\n'));
    final session = newSession();
    addTearDown(session.dispose);
    await session.refreshNow();

    session.markPromptSent('two');
    await fs.writeBytes(
      _sessionPath,
      utf8.encode('${_userPrompt('one')}\n${_userPrompt('two')}\n'),
    );
    await session.refreshNow();

    expect(session.resolvedPath, _sessionPath);
    expect(session.transcript.value.rows, hasLength(2));
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

  test('a pane that started its own agent never borrows a session', () async {
    // The CLI in a freshly launched chat pane writes no session file until the
    // first prompt (`pi` and `oh-my-pi` behave this way), while another window
    // keeps an older session file moving. Borrowing here would show — and let
    // the composer answer for — a conversation this pane never started.
    await fs.writeBytes(
      _sessionPath,
      utf8.encode('${_userPrompt('elsewhere')}\n'),
    );
    final session = ChatTranscriptSession(
      paneId: 'pane-1',
      resolveContext: (_) async => context,
      target: () => context.target,
      directory: () => _cwd,
      startedAt: DateTime.utc(2026, 11, 9, 9),
      expectOwnSession: true,
      sessionService: _FreshForeignRecordService(context),
    );
    addTearDown(session.dispose);

    await session.refreshNow();

    expect(session.resolvedPath, isNull);
    expect(
      session.transcript.value.unavailable,
      ChatTranscriptUnavailable.noSessionFile,
    );
    expect(session.transcript.value.borrowed, isFalse);
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

/// Returns one record another window is still writing: created long ago, moved
/// just now — exactly what a borrow would latch onto.
class _FreshForeignRecordService extends AgentCliSessionService {
  _FreshForeignRecordService(RuntimeContext context)
    : super(resolveContext: (_) async => context);

  @override
  Future<List<AgentCliSessionRecord>> listSessions({
    required RuntimeTarget target,
    required String directory,
  }) async => [
    AgentCliSessionRecord(
      family: AgentCliFamily.claude,
      sessionId: 'foreign',
      createdAt: DateTime.utc(2026, 11, 9, 6),
      updatedAt: DateTime.now(),
      filePath: _sessionPath,
    ),
  ];
}
