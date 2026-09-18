import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/search/ripgrep_search_engine.dart';
import 'package:teampilot/services/search/search_query.dart';
import 'package:teampilot/services/search/search_result_models.dart';

/// Replays canned `rg --json` lines through a fake [ProcessRunHandle].
class _FakeHandle implements ProcessRunHandle {
  _FakeHandle(this.lines, {Completer<void>? hold}) : _hold = hold;

  final List<String> lines;
  final Completer<void>? _hold;
  final _exit = Completer<int>();
  bool killed = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<List<int>> get stdout async* {
    if (_hold != null) await _hold!.future;
    // rg emits one JSON object per newline-terminated line.
    for (final line in lines) {
      yield '$line\n'.codeUnits;
    }
  }

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  void kill() {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(130);
  }

  void finish(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }
}

String _matchEvent(String path, int lineNo, String text) => jsonEncode({
  'type': 'match',
  'data': {
    'path': {'text': path},
    'lines': {'text': text},
    'line_number': lineNo,
    'absolute_offset': 0,
    'submatches': [
      {'match': {'text': 'foo'}, 'start': 0, 'end': 3},
    ],
  },
});

void main() {
  var lastArguments = <String>[];
  var lastWorkingDirectory = '';

  late _FakeHandle handle;
  late RipgrepSearchEngine engine;

  setUp(() {
    engine = RipgrepSearchEngine(
      spawner: ({required executable, required arguments, required workingDirectory}) async {
        lastArguments = arguments;
        lastWorkingDirectory = workingDirectory;
        return handle;
      },
    );
  });

  test('parses match events into grouped results with spans', () async {
    handle = _FakeHandle([
      _matchEvent('/repo/lib/a.dart', 3, 'foo bar foo\n'),
      '{"type":"begin","data":{"path":{"text":"/repo/lib/a.dart"}}}',
      _matchEvent('/repo/lib/a.dart', 9, 'another foo\n'),
      _matchEvent('/repo/lib/b.dart', 1, 'no foo here\n'),
      '{"type":"summary","data":{"elapsed_total":{}}}',
    ]);
    handle.finish(0);

    const query = SearchQuery(text: 'foo');
    final run = engine.search(
      query: query,
      pattern: query.compilePattern().pattern!,
      targetId: 'local',
      pathContext: pContext,
      roots: ['/repo'],
      workingDirectory: '/repo',
    );
    final results = await run.results;

    expect(results.files, hasLength(2));
    final a = results.files.first;
    expect(a.displayPath, 'lib/a.dart');
    expect(a.matches, hasLength(2));
    expect(a.matches.first.lineNo, 3);
    expect(a.matches.first.spans, hasLength(2)); // Both hits on the line.
    expect(a.matches.first.spans.first.start, 0);
    expect(a.matches.first.spans.last.start, 8);
    expect(results.totalMatches, 3);
    expect(results.engine, SearchEngineKind.ripgrep);
  });

  test('non-primary root gets basename prefix; other target prefixed', () async {
    handle = _FakeHandle([
      _matchEvent('/other/src/x.dart', 1, 'foo\n'),
    ]);
    handle.finish(0);

    const query = SearchQuery(text: 'foo');
    final run = engine.search(
      query: query,
      pattern: query.compilePattern().pattern!,
      targetId: 'ssh:1',
      pathContext: pContext,
      roots: ['/main', '/other'],
      workingDirectory: '/main',
      primaryTargetId: 'local',
    );
    final results = await run.results;

    expect(results.files.single.displayPath, 'ssh:1:other/src/x.dart');
  });

  test('argument mapping: fixed/word/case/globs/roots', () async {
    handle = _FakeHandle([]);
    handle.finish(1); // No matches.

    const query = SearchQuery(
      text: 'foo',
      caseSensitive: true,
      wholeWord: true,
      includeGlobs: '*.dart, *.md',
      excludeGlobs: 'build/',
    );
    final run = engine.search(
      query: query,
      pattern: query.compilePattern().pattern!,
      targetId: 'local',
      pathContext: pContext,
      roots: ['/repo', '/repo2'],
      workingDirectory: '/repo',
    );
    await run.results;

    expect(lastArguments, containsAll(['--json', '-w', '-F', '--']));
    expect(lastArguments, isNot(contains('-i')));
    expect(lastArguments.where((a) => a == '-g'), hasLength(3));
    expect(lastArguments, contains('*.dart'));
    expect(lastArguments, contains('*.md'));
    expect(lastArguments, contains('!build/**'));
    // Pattern precedes `--`; roots (path-only) follow it.
    expect(lastArguments[lastArguments.indexOf('--') - 1], 'foo');
    expect(lastArguments.sublist(lastArguments.length - 2), [
      '/repo',
      '/repo2',
    ]);
    expect(lastWorkingDirectory, '/repo');
  });

  test('kill marks results truncated and completes', () async {
    // Hold the stream open so the kill lands mid-scan, not after completion.
    final hold = Completer<void>();
    handle = _FakeHandle(
      [_matchEvent('/repo/lib/a.dart', 1, 'foo\n')],
      hold: hold,
    );

    const query = SearchQuery(text: 'foo');
    final run = engine.search(
      query: query,
      pattern: query.compilePattern().pattern!,
      targetId: 'local',
      pathContext: pContext,
      roots: ['/repo'],
      workingDirectory: '/repo',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    run.cancel();
    hold.complete();
    final results = await run.results;

    expect(handle.killed, isTrue);
    expect(results.truncated, isTrue);
    expect(results.files, hasLength(1)); // Parsed-before-kill result kept.
  });

  test('malformed JSON lines are tolerated', () async {
    handle = _FakeHandle([
      'not json',
      '{"type":"match","data":{"path":{"text":"/repo/a.dart"},',
      _matchEvent('/repo/a.dart', 2, 'foo\n'),
    ]);
    handle.finish(0);

    const query = SearchQuery(text: 'foo');
    final run = engine.search(
      query: query,
      pattern: query.compilePattern().pattern!,
      targetId: 'local',
      pathContext: pContext,
      roots: ['/repo'],
      workingDirectory: '/repo',
    );
    final results = await run.results;

    expect(results.files.single.matches.single.lineNo, 2);
  });
}

/// Posix-style context for path math in tests.
final pContext = p.posix;
