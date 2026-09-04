import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/cli/sessions/agent_cli_session_adapter.dart';
import 'package:teampilot/services/cli/sessions/agent_cli_session_service.dart';
import 'package:teampilot/services/cli/sessions/agent_cli_sessions.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import '../../../support/in_memory_filesystem.dart';

RuntimeContext _context(Filesystem fs) => RuntimeContext(
  target: RuntimeTarget.local(),
  filesystem: fs,
  home: '/home/u',
  cwd: '/home/u',
  appDataRoot: '/home/u/.app',
  paths: AppPaths('/home/u/.app'),
);

void main() {
  group('mungeDirectory', () {
    test('replaces every non-alphanumeric char', () {
      expect(mungeDirectory(r'D:\git\mo_token'), 'D--git-mo-token');
      expect(mungeDirectory('/home/u/proj'), '-home-u-proj');
      expect(mungeDirectory('  D:/git/x  '), 'D--git-x');
    });
  });

  group('posixDirectoryFromOsc7', () {
    test('parses posix file URIs', () {
      expect(posixDirectoryFromOsc7('file:///home/u/proj'), '/home/u/proj');
      expect(
        posixDirectoryFromOsc7('file://somehost/home/u/proj'),
        '/home/u/proj',
      );
      expect(
        posixDirectoryFromOsc7('file:///home/u/with%20space'),
        '/home/u/with space',
      );
    });

    test('rejects windows drive paths, garbage, and empty input', () {
      expect(posixDirectoryFromOsc7('file:///D:/git/x'), isNull);
      expect(posixDirectoryFromOsc7(''), isNull);
      expect(posixDirectoryFromOsc7('not-a-uri'), isNull);
      expect(posixDirectoryFromOsc7('https://example.com/x'), isNull);
      expect(posixDirectoryFromOsc7('file:///'), isNull);
    });
  });

  group('sameCliDirectory', () {
    test('ignores case and separators', () {
      expect(sameCliDirectory(r'D:\Git\Teampilot', 'd:/git/teampilot'), isTrue);
      expect(sameCliDirectory('/home/u/proj/', '/home/u/proj'), isTrue);
      expect(sameCliDirectory('/home/u/proj', '/home/u/other'), isFalse);
      expect(sameCliDirectory('', ''), isFalse);
    });
  });

  group('ClaudeStyleAgentCliSessionAdapter', () {
    test('lists jsonl sessions for the pane directory with titles', () async {
      final fs = InMemoryFilesystem();
      const dir = '/home/u/.claude/projects/-home-u-proj';
      await fs.writeBytes('$dir/aaa11111-1111-1111-1111-111111111111.jsonl', utf8.encode(
        '{"type":"ai-title","aiTitle":"修复 ctrl+p 搜索不到新文件"}\n'
            '{"type":"user","message":{"role":"user","content":"你好"}}\n',
      ));
      await fs.writeBytes('$dir/bbb22222-2222-2222-2222-222222222222.jsonl', utf8.encode(
        '{"type":"user","message":{"role":"user","content":"另一个会话"}}\n',
      ));
      await fs.writeBytes('$dir/not-a-session.txt', utf8.encode(
        'ignored',
      ));
      await fs.ensureDir('/home/u/.claude/projects/-home-u-other');
      await fs.writeBytes('/home/u/.claude/projects/-home-u-other/ccc.jsonl', utf8.encode(
        '{"type":"user","message":{"role":"user","content":"别的目录"}}\n',
      ));

      final records = await const ClaudeStyleAgentCliSessionAdapter(
        family: AgentCliFamily.claude,
        homeDotDir: '.claude',
      ).listSessions(
        AgentCliSessionQuery(context: _context(fs), directory: '/home/u/proj'),
      );

      expect(
        records.map((r) => r.sessionId),
        unorderedEquals([
          'aaa11111-1111-1111-1111-111111111111',
          'bbb22222-2222-2222-2222-222222222222',
        ]),
      );
      final byId = {for (final r in records) r.sessionId: r};
      expect(
        byId['aaa11111-1111-1111-1111-111111111111']?.title,
        '修复 ctrl+p 搜索不到新文件',
      );
      expect(byId['bbb22222-2222-2222-2222-222222222222']?.title, '另一个会话');
      expect(records.every((r) => r.family == AgentCliFamily.claude), isTrue);
    });

    test('falls back to case-insensitive project dir match', () async {
      final fs = InMemoryFilesystem();
      await fs.writeBytes('/home/u/.qoder/projects/D--git-teampilot/aaa.jsonl', utf8.encode(
        '{"type":"ai-title","aiTitle":"标题"}\n',
      ));

      final records = await const ClaudeStyleAgentCliSessionAdapter(
        family: AgentCliFamily.qoder,
        homeDotDir: '.qoder',
      ).listSessions(
        AgentCliSessionQuery(
          context: _context(fs),
          directory: r'd:\git\teampilot',
        ),
      );

      expect(records, hasLength(1));
      expect(records.single.sessionId, 'aaa');
      expect(records.single.title, '标题');
      expect(records.single.family, AgentCliFamily.qoder);
    });

    test('prefers custom-title and tolerates content blocks', () async {
      final fs = InMemoryFilesystem();
      await fs.writeBytes('/home/u/.claude/projects/-home-u-proj/aaa.jsonl', utf8.encode(
        '{"type":"ai-title","aiTitle":"ai 标题"}\n'
            '{"type":"custom-title","customTitle":"用户改名"}\n',
      ));
      await fs.writeBytes('/home/u/.claude/projects/-home-u-proj/bbb.jsonl', utf8.encode(
        '{"type":"user","message":{"role":"user","content":'
            '[{"type":"text","text":"块内容"}]}}\n',
      ));

      final records = await const ClaudeStyleAgentCliSessionAdapter(
        family: AgentCliFamily.claude,
        homeDotDir: '.claude',
      ).listSessions(
        AgentCliSessionQuery(context: _context(fs), directory: '/home/u/proj'),
      );

      final byId = {for (final r in records) r.sessionId: r};
      expect(byId['aaa']?.title, '用户改名');
      expect(byId['bbb']?.title, '块内容');
    });

    test('missing store yields empty', () async {
      final fs = InMemoryFilesystem();
      final records = await const ClaudeStyleAgentCliSessionAdapter(
        family: AgentCliFamily.claude,
        homeDotDir: '.claude',
      ).listSessions(
        AgentCliSessionQuery(context: _context(fs), directory: '/home/u/proj'),
      );
      expect(records, isEmpty);
    });
  });

  group('CodexAgentCliSessionAdapter', () {
    test('matches session_meta cwd and skips other directories', () async {
      final fs = InMemoryFilesystem();
      String rollout(String day, String id, String cwd) =>
          '{"timestamp":"2026-08-27T03:34:57.317Z","ordinal":0,'
          '"type":"session_meta","payload":{"session_id":"$id",'
          '"timestamp":"2026-08-27T03:34:51.295Z","cwd":"$cwd",'
          '"base_instructions":{"text":"prompt…"}}}';
      await fs.writeBytes(
        '/home/u/.codex/sessions/2026/08/26/'
            'rollout-2026-08-26T10-00-00-old.jsonl',
        utf8.encode(rollout('2026/08/26', 'old-id', r'D:\\other')),
      );
      await fs.writeBytes(
        '/home/u/.codex/sessions/2026/08/27/'
            'rollout-2026-08-27T11-34-51-match.jsonl',
        utf8.encode(rollout('2026/08/27', 'match-id', r'd:\\git\\teampilot')),
      );

      final records = await const CodexAgentCliSessionAdapter().listSessions(
        AgentCliSessionQuery(
          context: _context(fs),
          directory: r'D:\git\teampilot',
        ),
      );

      expect(records, hasLength(1));
      expect(records.single.sessionId, 'match-id');
      expect(records.single.family, AgentCliFamily.codex);
    });

    test('caps to the newest day dirs', () async {
      final fs = InMemoryFilesystem();
      final days = ['2026/08/25', '2026/08/26', '2026/08/27', '2026/08/24'];
      for (final day in days) {
        await fs.writeBytes('/home/u/.codex/sessions/$day/rollout-$day-T10-00-00-x.jsonl', utf8.encode(
          '{"type":"session_meta","payload":{"session_id":"$day-id",'
          '"cwd":"/home/u/proj"}}',
        ));
      }

      final records = await const CodexAgentCliSessionAdapter().listSessions(
        AgentCliSessionQuery(context: _context(fs), directory: '/home/u/proj'),
      );

      // Only the three newest days are scanned; the 08/24 day is skipped.
      expect(
        records.map((r) => r.sessionId),
        unorderedEquals(['2026/08/25-id', '2026/08/26-id', '2026/08/27-id']),
      );
    });

    test('missing store yields empty', () async {
      final fs = InMemoryFilesystem();
      final records = await const CodexAgentCliSessionAdapter().listSessions(
        AgentCliSessionQuery(context: _context(fs), directory: '/home/u/proj'),
      );
      expect(records, isEmpty);
    });
  });

  group('OpencodeAgentCliSessionAdapter', () {
    test('filters by directory and reads title and updated time', () async {
      final fs = InMemoryFilesystem();
      await fs.writeBytes('/home/u/.local/share/opencode/storage/session/global/ses_a.json', utf8.encode(
        '{"id":"ses_a","directory":"E:\\\\test_note",'
            '"title":"当前技能有哪些",'
            '"time":{"created":1772588625633,"updated":1772676654561}}',
      ));
      await fs.writeBytes('/home/u/.local/share/opencode/storage/session/abcd123/ses_b.json', utf8.encode(
        '{"id":"ses_b","directory":"/home/u/proj",'
            '"title":"匹配会话",'
            '"time":{"created":1,"updated":2}}',
      ));
      await fs.writeBytes('/home/u/.local/share/opencode/storage/session/abcd123/ses_c.json', utf8.encode(
        '{"id":"ses_c","directory":"/home/u/other","title":"不匹配"}',
      ));

      final records = await const OpencodeAgentCliSessionAdapter().listSessions(
        AgentCliSessionQuery(context: _context(fs), directory: '/home/u/proj'),
      );

      expect(records, hasLength(1));
      expect(records.single.sessionId, 'ses_b');
      expect(records.single.title, '匹配会话');
      expect(records.single.updatedAt, isNotNull);
      expect(records.single.family, AgentCliFamily.opencode);
    });

    test('missing store yields empty', () async {
      final fs = InMemoryFilesystem();
      final records = await const OpencodeAgentCliSessionAdapter().listSessions(
        AgentCliSessionQuery(context: _context(fs), directory: '/home/u/proj'),
      );
      expect(records, isEmpty);
    });
  });

  group('AgentCliSessionService', () {
    AgentCliSessionService serviceOf(List<AgentCliSessionAdapter> adapters) =>
        AgentCliSessionService(
          resolveContext: (_) async => _context(InMemoryFilesystem()),
          adapters: adapters,
        );

    test('a resolve failure yields empty', () async {
      final service = AgentCliSessionService(
        resolveContext: (_) async => throw StateError('unreachable target'),
        adapters: [
          _fakeAdapter([
            const AgentCliSessionRecord(
              family: AgentCliFamily.claude,
              sessionId: 'x',
            ),
          ]),
        ],
      );
      final records = await service.listSessions(
        target: RuntimeTarget.local(),
        directory: '/home/u/proj',
      );
      expect(records, isEmpty);
    });

    test('merges adapters newest first', () async {
      final older = DateTime.utc(2026, 8, 1);
      final newer = DateTime.utc(2026, 9, 1);
      final service = serviceOf([
        _fakeAdapter([
          AgentCliSessionRecord(
            family: AgentCliFamily.claude,
            sessionId: 'old',
            updatedAt: older,
          ),
        ]),
        _fakeAdapter([
          AgentCliSessionRecord(
            family: AgentCliFamily.codex,
            sessionId: 'new',
            updatedAt: newer,
          ),
          AgentCliSessionRecord(
            family: AgentCliFamily.opencode,
            sessionId: 'undated',
          ),
        ]),
      ]);

      final records = await service.listSessions(
        target: RuntimeTarget.local(),
        directory: '/home/u/proj',
      );
      expect(records.map((r) => r.sessionId), ['new', 'old', 'undated']);
    });

    test('a failing adapter does not fail the scan', () async {
      final service = serviceOf([
        _throwingAdapter(),
        _fakeAdapter([
          const AgentCliSessionRecord(
            family: AgentCliFamily.qoder,
            sessionId: 'ok',
          ),
        ]),
      ]);

      final records = await service.listSessions(
        target: RuntimeTarget.local(),
        directory: '/home/u/proj',
      );
      expect(records.map((r) => r.sessionId), ['ok']);
    });

    test('a slow adapter is cut off by the timeout', () async {
      final service = AgentCliSessionService(
        resolveContext: (_) async => _context(InMemoryFilesystem()),
        adapters: [_slowAdapter(), _fakeAdapter(const [])],
        timeout: const Duration(milliseconds: 10),
      );

      final records = await service.listSessions(
        target: RuntimeTarget.local(),
        directory: '/home/u/proj',
      );
      expect(records, isEmpty);
    });

    test('empty directory short-circuits', () async {
      final service = serviceOf([
        _throwingAdapter(),
      ]);
      final records = await service.listSessions(
        target: RuntimeTarget.local(),
        directory: '  ',
      );
      expect(records, isEmpty);
    });

    test('resume commands are family-specific', () async {
      expect(
        AgentCliFamily.claude.resumeCommand('abc'),
        'claude --resume abc',
      );
      expect(AgentCliFamily.qoder.resumeCommand('abc'), 'qodercli --resume abc');
      expect(AgentCliFamily.codex.resumeCommand('abc'), 'codex resume abc');
      expect(
        AgentCliFamily.opencode.resumeCommand('abc'),
        'opencode --session abc',
      );
    });
  });
}

AgentCliSessionAdapter _fakeAdapter(List<AgentCliSessionRecord> records) =>
    _FakeAdapter(records);

AgentCliSessionAdapter _throwingAdapter() => _ThrowingAdapter();

AgentCliSessionAdapter _slowAdapter() => _SlowAdapter();

class _FakeAdapter implements AgentCliSessionAdapter {
  _FakeAdapter(this.records);

  final List<AgentCliSessionRecord> records;

  @override
  AgentCliFamily get family => AgentCliFamily.claude;

  @override
  Future<List<AgentCliSessionRecord>> listSessions(
    AgentCliSessionQuery query,
  ) async => records;
}

class _ThrowingAdapter implements AgentCliSessionAdapter {
  @override
  AgentCliFamily get family => AgentCliFamily.codex;

  @override
  Future<List<AgentCliSessionRecord>> listSessions(
    AgentCliSessionQuery query,
  ) async => throw const FileSystemException('boom');
}

class _SlowAdapter implements AgentCliSessionAdapter {
  @override
  AgentCliFamily get family => AgentCliFamily.opencode;

  @override
  Future<List<AgentCliSessionRecord>> listSessions(
    AgentCliSessionQuery query,
  ) async {
    await Future<void>.delayed(const Duration(seconds: 5));
    return const [];
  }
}
