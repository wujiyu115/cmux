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
      await fs.writeBytes(
        '$dir/aaa11111-1111-1111-1111-111111111111.jsonl',
        utf8.encode(
          '{"type":"ai-title","aiTitle":"修复 ctrl+p 搜索不到新文件"}\n'
          '{"type":"user","message":{"role":"user","content":"你好"}}\n',
        ),
      );
      await fs.writeBytes(
        '$dir/bbb22222-2222-2222-2222-222222222222.jsonl',
        utf8.encode(
          '{"type":"user","message":{"role":"user","content":"另一个会话"}}\n',
        ),
      );
      await fs.writeBytes('$dir/not-a-session.txt', utf8.encode('ignored'));
      await fs.ensureDir('/home/u/.claude/projects/-home-u-other');
      await fs.writeBytes(
        '/home/u/.claude/projects/-home-u-other/ccc.jsonl',
        utf8.encode(
          '{"type":"user","message":{"role":"user","content":"别的目录"}}\n',
        ),
      );

      final records =
          await const ClaudeStyleAgentCliSessionAdapter(
            family: AgentCliFamily.claude,
            homeDotDir: '.claude',
          ).listSessions(
            AgentCliSessionQuery(
              context: _context(fs),
              directory: '/home/u/proj',
            ),
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
      await fs.writeBytes(
        '/home/u/.qoder/projects/D--git-teampilot/aaa.jsonl',
        utf8.encode('{"type":"ai-title","aiTitle":"标题"}\n'),
      );

      final records =
          await const ClaudeStyleAgentCliSessionAdapter(
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
      await fs.writeBytes(
        '/home/u/.claude/projects/-home-u-proj/aaa.jsonl',
        utf8.encode(
          '{"type":"ai-title","aiTitle":"ai 标题"}\n'
          '{"type":"custom-title","customTitle":"用户改名"}\n',
        ),
      );
      await fs.writeBytes(
        '/home/u/.claude/projects/-home-u-proj/bbb.jsonl',
        utf8.encode(
          '{"type":"user","message":{"role":"user","content":'
          '[{"type":"text","text":"块内容"}]}}\n',
        ),
      );

      final records =
          await const ClaudeStyleAgentCliSessionAdapter(
            family: AgentCliFamily.claude,
            homeDotDir: '.claude',
          ).listSessions(
            AgentCliSessionQuery(
              context: _context(fs),
              directory: '/home/u/proj',
            ),
          );

      final byId = {for (final r in records) r.sessionId: r};
      expect(byId['aaa']?.title, '用户改名');
      expect(byId['bbb']?.title, '块内容');
    });

    test('missing store yields empty', () async {
      final fs = InMemoryFilesystem();
      final records =
          await const ClaudeStyleAgentCliSessionAdapter(
            family: AgentCliFamily.claude,
            homeDotDir: '.claude',
          ).listSessions(
            AgentCliSessionQuery(
              context: _context(fs),
              directory: '/home/u/proj',
            ),
          );
      expect(records, isEmpty);
    });

    test('batched backend reads every head in one round trip', () async {
      final fs = _BatchingInMemoryFilesystem();
      const dir = '/home/u/.claude/projects/-home-u-proj';
      await fs.writeBytes(
        '$dir/aaa.jsonl',
        utf8.encode('{"type":"ai-title","aiTitle":"批量读取的会话"}\n'),
      );
      await fs.writeBytes(
        '$dir/bbb.jsonl',
        utf8.encode(
          '{"type":"user","message":{"role":"user","content":"第二个"}}\n',
        ),
      );

      final records =
          await const ClaudeStyleAgentCliSessionAdapter(
            family: AgentCliFamily.claude,
            homeDotDir: '.claude',
          ).listSessions(
            AgentCliSessionQuery(
              context: _context(fs),
              directory: '/home/u/proj',
            ),
          );

      expect(records, hasLength(2));
      expect(fs.statAndReadBytesManyCalls, 1);
      expect(fs.statAndReadBytesCalls, 0);
    });

    test('batched backend falls back to per-file reads', () async {
      final fs = _BatchingInMemoryFilesystem()..failStatAndReadBytesMany = true;
      const dir = '/home/u/.claude/projects/-home-u-proj';
      await fs.writeBytes(
        '$dir/aaa.jsonl',
        utf8.encode('{"type":"ai-title","aiTitle":"降级读取的会话"}\n'),
      );

      final records =
          await const ClaudeStyleAgentCliSessionAdapter(
            family: AgentCliFamily.claude,
            homeDotDir: '.claude',
          ).listSessions(
            AgentCliSessionQuery(
              context: _context(fs),
              directory: '/home/u/proj',
            ),
          );

      expect(records, hasLength(1));
      expect(records.single.title, '降级读取的会话');
      expect(fs.statAndReadBytesCalls, 1);
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
        await fs.writeBytes(
          '/home/u/.codex/sessions/$day/rollout-$day-T10-00-00-x.jsonl',
          utf8.encode(
            '{"type":"session_meta","payload":{"session_id":"$day-id",'
            '"cwd":"/home/u/proj"}}',
          ),
        );
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
      await fs.writeBytes(
        '/home/u/.local/share/opencode/storage/session/global/ses_a.json',
        utf8.encode(
          '{"id":"ses_a","directory":"E:\\\\test_note",'
          '"title":"当前技能有哪些",'
          '"time":{"created":1772588625633,"updated":1772676654561}}',
        ),
      );
      await fs.writeBytes(
        '/home/u/.local/share/opencode/storage/session/abcd123/ses_b.json',
        utf8.encode(
          '{"id":"ses_b","directory":"/home/u/proj",'
          '"title":"匹配会话",'
          '"time":{"created":1,"updated":2}}',
        ),
      );
      await fs.writeBytes(
        '/home/u/.local/share/opencode/storage/session/abcd123/ses_c.json',
        utf8.encode('{"id":"ses_c","directory":"/home/u/other","title":"不匹配"}'),
      );

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

  group('OhMyPiAgentCliSessionAdapter', () {
    String ompHead({String title = '', String? sessionId, String? prompt}) {
      final buffer = StringBuffer()
        ..write('{"type":"title","v":1,"title":"$title","source":"auto",')
        ..write('"updatedAt":"2026-09-08T02:55:22.756Z","pad":""}\n')
        ..write(
          '{"type":"session","version":3,'
          '"id":"${sessionId ?? '01a07edb-eefa-7123-943f-8633e59c918c'}",'
          '"timestamp":"2026-09-08T02:32:17.914Z","cwd":"/home/u/proj"}\n',
        );
      if (prompt != null) {
        buffer.write(
          '{"type":"message","id":"m1","message":{"role":"user",'
          '"content":[{"type":"text","text":"$prompt"}]}}\n',
        );
      }
      return buffer.toString();
    }

    test('lists sessions with the title record and session id', () async {
      final fs = InMemoryFilesystem();
      const dir = '/home/u/.omp/agent/sessions/-proj';
      await fs.writeBytes(
        '$dir/2026-09-08T02-32-17-914Z_01a07edb-eefa-7123-943f-8633e59c918c.jsonl',
        utf8.encode(ompHead(title: '标题来自 title 记录')),
      );

      final records = await const OhMyPiAgentCliSessionAdapter().listSessions(
        AgentCliSessionQuery(context: _context(fs), directory: '/home/u/proj'),
      );

      expect(records, hasLength(1));
      expect(records.single.sessionId, '01a07edb-eefa-7123-943f-8633e59c918c');
      expect(records.single.title, '标题来自 title 记录');
      expect(records.single.family, AgentCliFamily.ohMyPi);
    });

    test('empty title falls back to the first user message', () async {
      final fs = InMemoryFilesystem();
      const dir = '/home/u/.omp/agent/sessions/-proj';
      await fs.writeBytes(
        '$dir/2026-09-08T02-34-02-509Z_01a07edd-878d-716d-9e74-b7856fc8e058.jsonl',
        utf8.encode(ompHead(prompt: '第一个用户提问')),
      );

      final records = await const OhMyPiAgentCliSessionAdapter().listSessions(
        AgentCliSessionQuery(context: _context(fs), directory: '/home/u/proj'),
      );

      expect(records.single.title, '第一个用户提问');
    });

    test('directories outside home keep their full munged path', () async {
      final fs = InMemoryFilesystem();
      await fs.writeBytes(
        '/home/u/.omp/agent/sessions/-tmp-omp-test2/'
        '2026-09-08T02-32-17-914Z_01a07edb-eefa-7123-943f-8633e59c918c.jsonl',
        utf8.encode(ompHead(title: 'home 外的会话')),
      );

      final records = await const OhMyPiAgentCliSessionAdapter().listSessions(
        AgentCliSessionQuery(
          context: _context(fs),
          directory: '/tmp/omp-test2',
        ),
      );

      expect(records.single.title, 'home 外的会话');
    });

    test('skips tool-log directories and other projects', () async {
      final fs = InMemoryFilesystem();
      const dir = '/home/u/.omp/agent/sessions/-proj';
      await fs.writeBytes(
        '$dir/2026-09-08T02-32-17-914Z_01a07edb-eefa-7123-943f-8633e59c918c.jsonl',
        utf8.encode(ompHead()),
      );
      // Per-session tool-log directory sharing the session's name.
      await fs.ensureDir(
        '$dir/2026-09-08T02-32-17-914Z_01a07edb-eefa-7123-943f-8633e59c918c',
      );
      // A different project's sessions must not leak in.
      await fs.writeBytes(
        '/home/u/.omp/agent/sessions/-home-u-other/'
        '2026-09-08T02-00-00-000Z_ffffffff-0000-0000-0000-000000000000.jsonl',
        utf8.encode(ompHead(title: '别的目录')),
      );

      final records = await const OhMyPiAgentCliSessionAdapter().listSessions(
        AgentCliSessionQuery(context: _context(fs), directory: '/home/u/proj'),
      );

      expect(records, hasLength(1));
      expect(records.single.sessionId, '01a07edb-eefa-7123-943f-8633e59c918c');
    });

    test(
      'head without a session record falls back to the filename suffix',
      () async {
        final fs = InMemoryFilesystem();
        const dir = '/home/u/.omp/agent/sessions/-proj';
        await fs.writeBytes(
          '$dir/2026-09-08T02-32-17-914Z_01a07edb-eefa-7123-943f-8633e59c918c.jsonl',
          utf8.encode('{"type":"title","v":1,"title":"截断的文件"}\n'),
        );

        final records = await const OhMyPiAgentCliSessionAdapter().listSessions(
          AgentCliSessionQuery(
            context: _context(fs),
            directory: '/home/u/proj',
          ),
        );

        expect(
          records.single.sessionId,
          '01a07edb-eefa-7123-943f-8633e59c918c',
        );
        expect(records.single.title, '截断的文件');
      },
    );

    test('missing store yields empty', () async {
      final fs = InMemoryFilesystem();
      final records = await const OhMyPiAgentCliSessionAdapter().listSessions(
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

    test('a batched backend gets the wider timeout budget', () async {
      // 200ms of work would be cut off by the local 20ms budget, but the
      // batched (WSL-style) context scans under the 10s batched budget.
      final service = AgentCliSessionService(
        resolveContext: (_) async => _context(_BatchingInMemoryFilesystem()),
        adapters: [
          _SlowAdapter(
            delay: const Duration(milliseconds: 200),
            records: const [
              AgentCliSessionRecord(
                family: AgentCliFamily.claude,
                sessionId: 'wsl-session',
              ),
            ],
          ),
        ],
        timeout: const Duration(milliseconds: 20),
        batchedTimeout: const Duration(seconds: 10),
      );

      final records = await service.listSessions(
        target: RuntimeTarget.local(),
        directory: '/home/u/proj',
      );
      expect(records.map((r) => r.sessionId), ['wsl-session']);
    });

    test('empty directory short-circuits', () async {
      final service = serviceOf([_throwingAdapter()]);
      final records = await service.listSessions(
        target: RuntimeTarget.local(),
        directory: '  ',
      );
      expect(records, isEmpty);
    });

    test('resume commands are family-specific', () async {
      expect(AgentCliFamily.claude.resumeCommand('abc'), 'claude --resume abc');
      expect(
        AgentCliFamily.qoder.resumeCommand('abc'),
        'qodercli --resume abc',
      );
      expect(AgentCliFamily.codex.resumeCommand('abc'), 'codex resume abc');
      expect(
        AgentCliFamily.opencode.resumeCommand('abc'),
        'opencode --session abc',
      );
      expect(AgentCliFamily.ohMyPi.resumeCommand('abc'), 'omp --resume abc');
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
  _SlowAdapter({
    this.delay = const Duration(seconds: 5),
    this.records = const [],
  });

  final Duration delay;
  final List<AgentCliSessionRecord> records;

  @override
  AgentCliFamily get family => AgentCliFamily.opencode;

  @override
  Future<List<AgentCliSessionRecord>> listSessions(
    AgentCliSessionQuery query,
  ) async {
    await Future<void>.delayed(delay);
    return records;
  }
}

/// Batches like the WSL backend so adapter scans take the FsBatchOps path;
/// the batched ops delegate to the in-memory per-file primitives.
class _BatchingInMemoryFilesystem extends InMemoryFilesystem
    implements FsBatchOps {
  int statAndReadBytesManyCalls = 0;
  int statAndReadBytesCalls = 0;
  bool failStatAndReadBytesMany = false;

  @override
  Future<FsStatAndBytes?> statAndReadBytes(String path, {int? maxBytes}) async {
    statAndReadBytesCalls++;
    return _statAndRead(path, maxBytes);
  }

  @override
  Future<Map<String, FsStatAndBytes?>> statAndReadBytesMany(
    List<String> paths, {
    int? maxBytesPerFile,
  }) async {
    statAndReadBytesManyCalls++;
    if (failStatAndReadBytesMany) throw StateError('batch transport failed');
    return {
      for (final path in paths) path: await _statAndRead(path, maxBytesPerFile),
    };
  }

  @override
  Future<Map<String, bool>> existsMany(List<String> paths) async {
    return {for (final p in paths) p: (await stat(p)).exists};
  }

  Future<FsStatAndBytes?> _statAndRead(String path, int? maxBytes) async {
    final stat = await this.stat(path);
    if (!stat.exists) return null;
    final bytes = await readBytes(path);
    if (bytes == null) return FsStatAndBytes(stat: stat);
    return FsStatAndBytes(
      stat: stat,
      bytes: maxBytes == null ? bytes : bytes.take(maxBytes).toList(),
    );
  }
}
