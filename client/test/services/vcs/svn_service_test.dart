import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_blame.dart';
import 'package:teampilot/services/vcs/svn_command_runner.dart';
import 'package:teampilot/services/vcs/svn_service.dart';

/// Real `svn blame --verbose` output shape (svn 1.10, sampled from
/// ~/work/2003VB12/common): space-separated fields; `--` (or `---` when the
/// content starts with `-`) separates the date block from the line content.
const _blameSample = '''
 368522 qiankong.lhp 2020-04-22 21:39:20 +0800 (Wed, 22 Apr 2020) --- @module Class providing the actual XML parser.
 368522 qiankong.lhp 2020-04-22 21:39:20 +0800 (Wed, 22 Apr 2020) --  Available options are:
 778812 someone.else 2021-06-01 08:00:00 +0800 (Tue, 01 Jun 2021) --    * stripWS
 368522 qiankong.lhp 2020-04-22 21:39:20 +0800 (Wed, 22 Apr 2020) --        Strip non-significant whitespace
''';

/// Real `svn status --ignore-externals` shape: status letter, spaces, path.
const _statusSample = '''
X       convertor/SpriteData
X       convertor/lang/trans_eu
M       convertor/XmlParser.lua
?       convertor/new_file.lua
!       convertor/gone_dir
D       convertor/old.lua
A       convertor/added.lua
Performing status on external item at 'convertor/SpriteData':
Status against revision: 1360277
''';

class _FakeSvnRunner implements SvnCommandRunner {
  _FakeSvnRunner({this.stdout = '', this.exitCode = 0});

  final String stdout;
  final int exitCode;

  final calls = <(String, List<String>)>[];

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args) async {
    calls.add((dir, args));
    return GitCommandResult(
      exitCode: exitCode,
      stdout: stdout,
      stderr: '',
    );
  }
}

void main() {
  group('parseSvnStatus', () {
    test('parses kinds, skips externals notices and summary lines', () {
      final rows = parseSvnStatus(_statusSample);
      expect(rows, hasLength(7));
      expect(rows[0].kind, SvnChangeKind.external);
      expect(rows[0].path, 'convertor/SpriteData');
      expect(rows[2].kind, SvnChangeKind.modified);
      expect(rows[2].path, 'convertor/XmlParser.lua');
      expect(rows[3].kind, SvnChangeKind.unversioned);
      expect(rows[4].kind, SvnChangeKind.missing);
      expect(rows[5].kind, SvnChangeKind.deleted);
      expect(rows[6].kind, SvnChangeKind.added);
    });

    test('badges match svn status letters', () {
      final rows = parseSvnStatus(_statusSample);
      expect(
        rows.map((r) => r.badge).join(),
        'XXM?!DA',
      );
    });

    test('empty and notice-only output parse to nothing', () {
      expect(parseSvnStatus(''), isEmpty);
      expect(
        parseSvnStatus("Performing status on external item at 'x':\n"),
        isEmpty,
      );
    });
  });

  group('parseSvnBlame', () {
    test('groups per revision with coalesced ranges and author/date', () {
      final entries = parseSvnBlame(_blameSample);
      expect(entries, hasLength(2));

      // Sorted by first range start: r368522 owns line 1, r778812 line 3.
      final first = entries[0];
      expect(first.hash, 'r368522'.padLeft(8, 'r'));
      expect(first.authorName, 'qiankong.lhp');
      // Lines 1,2,4 of r368522 — 1-2 coalesce, 4 separate.
      expect(first.ranges, hasLength(2));
      expect(first.ranges[0], const GitBlameLineRange(start: 1, end: 2));
      expect(first.ranges[1], const GitBlameLineRange(start: 4, end: 4));

      final second = entries[1];
      expect(second.hash, 'r778812'.padLeft(8, 'r'));
      expect(second.ranges.single, const GitBlameLineRange(start: 3, end: 3));
      expect(second.authorName, 'someone.else');
    });

    test('date parses to a unix timestamp in the file line order', () {
      final entries = parseSvnBlame(_blameSample);
      final first = entries[0];
      // 2020-04-22 21:39:20 +0800 == 2020-04-22 13:39:20 UTC == 1587562760.
      expect(first.authorTime, 1587562760);
    });

    test('garbage input parses to an empty list', () {
      expect(parseSvnBlame(''), isEmpty);
      expect(parseSvnBlame('Skipped resource\n'), isEmpty);
    });
  });

  group('SvnService', () {
    test('status returns parsed rows', () async {
      final runner = _FakeSvnRunner(stdout: _statusSample);
      final service = SvnService(runner: runner);
      final rows = await service.status('/wc');
      expect(rows, hasLength(7));
      expect(runner.calls.single.$1, '/wc');
      expect(runner.calls.single.$2.join(' '), 'status --ignore-externals');
    });

    test('blameFile returns entries on success, null on failure', () async {
      final ok = SvnService(
        runner: _FakeSvnRunner(stdout: _blameSample),
      );
      final entries = await ok.blameFile('/wc', 'lib/a.lua');
      expect(entries, hasLength(2));

      final failing = SvnService(
        runner: _FakeSvnRunner(exitCode: 1, stdout: ''),
      );
      expect(await failing.blameFile('/wc', 'unversioned'), isNull);
    });

    test('info parses url and revision from xml', () async {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<info>
<entry kind="dir" path="." revision="1360185">
<url>http://m2.svn.ejoy.com/M2/branch/cn/m2/editor/config</url>
</entry>
</info>
''';
      final service = SvnService(runner: _FakeSvnRunner(stdout: xml));
      final info = await service.info('/wc');
      expect(info?.revision, 1360185);
      expect(info?.url, 'http://m2.svn.ejoy.com/M2/branch/cn/m2/editor/config');
    });

    test('info returns null for non-checkout (non-zero exit)', () async {
      final service = SvnService(
        runner: _FakeSvnRunner(exitCode: 155013, stdout: ''),
      );
      expect(await service.info('/not-a-wc'), isNull);
    });

    test('commit passes message and selected paths', () async {
      final runner = _FakeSvnRunner(stdout: 'Committed revision 10.\n');
      final service = SvnService(runner: runner);
      await service.commit('/wc', 'fix', ['a.lua', 'b.lua']);
      expect(runner.calls.single.$1, '/wc');
      expect(runner.calls.single.$2.join(' '), 'commit -m fix -- a.lua b.lua');
    });

    test('commit without paths commits the whole wc', () async {
      final runner = _FakeSvnRunner(stdout: 'Committed revision 10.\n');
      final service = SvnService(runner: runner);
      await service.commit('/wc', 'fix', const []);
      expect(runner.calls.single.$2.join(' '), 'commit -m fix');
    });

    test('revert and add forward paths after --', () async {
      final runner = _FakeSvnRunner();
      final service = SvnService(runner: runner);
      await service.revert('/wc', ['a.lua']);
      await service.add('/wc', ['b.lua']);
      expect(runner.calls[0].$2.join(' '), 'revert -- a.lua');
      expect(runner.calls[1].$2.join(' '), 'add -- b.lua');
    });
  });
}
