import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/command_log_entry.dart';
import 'package:teampilot/services/terminal/shell_command_tracker.dart';

/// `ESC ] 133 ; <payload> BEL`
String _osc133(String payload) => '\x1b]133;$payload\x07';

void main() {
  late List<CommandLogEntry> done;
  late List<CommandLogEntry> started;
  late DateTime now;
  late int ids;
  late PaneLogContext context;

  ShellCommandTracker build() => ShellCommandTracker(
    paneId: 'pane-1',
    workspaceId: 'ws-1',
    context: () => context,
    onCompleted: done.add,
    onStarted: started.add,
    clock: () => now,
    newId: () => 'id-${++ids}',
  );

  setUp(() {
    done = [];
    started = [];
    ids = 0;
    now = DateTime.utc(2026, 7, 20, 10);
    context = const PaneLogContext(
      surfaceId: 'sf-1',
      surfaceName: '终端 1',
      paneName: 'pane one',
      workspaceName: 'demo',
      workingDirectory: '/repo',
    );
  });

  test('A/B/C/D produces one finished row with context, exit code, duration', () {
    final tracker = build();
    expect(tracker.hasShellIntegration, isFalse);

    tracker.observePtyText(_osc133('A'));
    expect(tracker.hasShellIntegration, isTrue);
    tracker.observePtyText(_osc133('B;git status'));
    tracker.observePtyText(_osc133('C'));

    expect(started, hasLength(1));
    expect(tracker.active?.command, 'git status');
    expect(done, isEmpty);

    now = now.add(const Duration(milliseconds: 1500));
    tracker.observePtyText(_osc133('D;0'));

    expect(tracker.active, isNull);
    expect(done, hasLength(1));
    final entry = done.single;
    expect(entry.id, 'id-1');
    expect(entry.command, 'git status');
    expect(entry.exitCode, 0);
    expect(entry.succeeded, isTrue);
    expect(entry.duration, const Duration(milliseconds: 1500));
    expect(entry.paneId, 'pane-1');
    expect(entry.workspaceId, 'ws-1');
    expect(entry.surfaceId, 'sf-1');
    expect(entry.surfaceName, '终端 1');
    expect(entry.paneName, 'pane one');
    expect(entry.workspaceName, 'demo');
    expect(entry.workingDirectory, '/repo');
  });

  test('non-zero exit code is kept, extra D params are ignored', () {
    final tracker = build();
    tracker.observePtyText(_osc133('B;false'));
    tracker.observePtyText(_osc133('C'));
    tracker.observePtyText(_osc133('D;1;aid=2'));
    expect(done.single.exitCode, 1);
    expect(done.single.succeeded, isFalse);
  });

  test('D without a status leaves exitCode null but still finishes the row', () {
    final tracker = build();
    tracker.observePtyText(_osc133('B;sleep 1'));
    tracker.observePtyText(_osc133('C'));
    tracker.observePtyText(_osc133('D'));
    expect(done.single.exitCode, isNull);
    expect(done.single.completedAt, isNotNull);
  });

  test('a new prompt closes a row that never reported a status', () {
    final tracker = build();
    tracker.observePtyText(_osc133('B;top'));
    tracker.observePtyText(_osc133('C'));
    tracker.observePtyText(_osc133('A'));

    expect(done, hasLength(1));
    expect(done.single.command, 'top');
    expect(done.single.exitCode, isNull);
    expect(tracker.active, isNull);
  });

  test('sequences split across PTY chunks still resolve', () {
    final tracker = build();
    tracker.observePtyText('out\x1b]133;B;git ');
    expect(tracker.active, isNull);
    tracker.observePtyText('log\x07');
    tracker.observePtyText('\x1b]133;C\x1b\\');
    expect(tracker.active?.command, 'git log');
    tracker.observePtyText('\x1b]13');
    tracker.observePtyText('3;D;0\x07');
    expect(done.single.command, 'git log');
    expect(done.single.exitCode, 0);
  });

  test('C without B falls back to cmdline= and then to the typed line', () {
    final tracker = build();
    tracker.observePtyText(_osc133('C;cmdline=make build'));
    expect(tracker.active?.command, 'make build');
    tracker.observePtyText(_osc133('D;0'));

    tracker.observeUserInput('cargo test');
    tracker.observePtyText(_osc133('A'));
    tracker.observePtyText(_osc133('C'));
    expect(tracker.active?.command, 'cargo test');
  });

  test('a repeated C for the running command does not orphan the row', () {
    final tracker = build();
    tracker.observePtyText(_osc133('B;git status'));
    tracker.observePtyText(_osc133('C'));
    final active = tracker.active;
    tracker.observePtyText(_osc133('C'));

    expect(done, isEmpty);
    expect(tracker.active?.id, active?.id);
  });

  test('an out-of-order D with nothing running is ignored', () {
    final tracker = build();
    tracker.observePtyText(_osc133('D;0'));
    tracker.observePtyText(_osc133('D;1'));
    expect(done, isEmpty);
    expect(tracker.hasShellIntegration, isTrue);
  });

  test('unknown markers and empty payloads change no state', () {
    final tracker = build();
    tracker.observePtyText(_osc133('L'));
    tracker.observePtyText(_osc133(''));
    tracker.observePtyText('\x1b]133;\x07');
    expect(done, isEmpty);
    expect(tracker.active, isNull);
  });

  test('panes without shell integration log each submitted line', () {
    final tracker = build();
    tracker.observeUserInput('ls -la');
    expect(tracker.active?.command, 'ls -la');
    expect(done, isEmpty);

    tracker.observeUserInput('cd ..');
    expect(done, hasLength(1));
    expect(done.single.command, 'ls -la');
    expect(done.single.exitCode, isNull);
    expect(done.single.completedAt, isNull);
    expect(tracker.active?.command, 'cd ..');
  });

  test('once shell integration is seen, typed lines stop opening rows', () {
    final tracker = build();
    tracker.observePtyText(_osc133('A'));
    tracker.observeUserInput('ls -la');
    expect(tracker.active, isNull);
    expect(done, isEmpty);
  });

  test('secrets are redacted in marker payloads and typed lines', () {
    final tracker = build();
    tracker.observePtyText(_osc133('B;mysql --password hunter2'));
    tracker.observePtyText(_osc133('C'));
    tracker.observePtyText(_osc133('D;0'));
    expect(done.single.command, 'mysql --password [REDACTED]');

    final bare = build();
    bare.observeUserInput('Tr0ub4dor&3');
    expect(bare.active, isNull);
    expect(done, hasLength(1));
  });

  test('the row falls back to the live cwd when none was captured', () {
    context = const PaneLogContext(surfaceId: 'sf-1');
    final tracker = build();
    tracker.observePtyText(_osc133('B;pwd'));
    tracker.observePtyText(_osc133('C'));
    context = const PaneLogContext(
      surfaceId: 'sf-1',
      workingDirectory: '/repo/sub',
    );
    tracker.observePtyText(_osc133('D;0'));
    expect(done.single.workingDirectory, '/repo/sub');
  });

  test('flush ends a running row without a status', () {
    final tracker = build();
    tracker.observePtyText(_osc133('B;top'));
    tracker.observePtyText(_osc133('C'));
    tracker.flush();
    expect(done.single.completedAt, isNull);
    expect(tracker.active, isNull);
    tracker.flush();
    expect(done, hasLength(1));
  });

  test('dispose flushes once and then ignores further input', () {
    final tracker = build();
    tracker.observePtyText(_osc133('B;top'));
    tracker.observePtyText(_osc133('C'));
    tracker.dispose();
    expect(done, hasLength(1));

    tracker.observePtyText(_osc133('B;ls'));
    tracker.observeUserInput('ls');
    tracker.dispose();
    expect(done, hasLength(1));
  });

  test('reset drops the running row without reporting it', () {
    final tracker = build();
    tracker.observePtyText(_osc133('B;top'));
    tracker.observePtyText(_osc133('C'));
    tracker.reset();
    expect(tracker.active, isNull);
    expect(done, isEmpty);
  });
}
