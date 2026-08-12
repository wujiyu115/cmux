import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/notification/terminal_idle_edge_detector.dart';

void main() {
  final t0 = DateTime(2026, 8, 12, 12);

  late TerminalIdleEdgeDetector detector;

  setUp(() {
    detector = TerminalIdleEdgeDetector(
      minimumWorkDuration: const Duration(seconds: 5),
      idleGrace: const Duration(seconds: 8),
    );
  });

  /// One poll tick.
  bool tick({
    required bool working,
    required int atSeconds,
    String paneId = 'p1',
    bool agent = false,
  }) => detector.observe(
    paneId: paneId,
    working: working,
    reportsAgentStatus: agent,
    now: t0.add(Duration(seconds: atSeconds)),
  );

  test('a long burst notifies only after the quiet has held', () {
    expect(tick(working: true, atSeconds: 0), isFalse);
    expect(tick(working: true, atSeconds: 6), isFalse);
    // The falling edge itself never fires — the grace window starts here.
    expect(tick(working: false, atSeconds: 7), isFalse);
    expect(tick(working: false, atSeconds: 14), isFalse);
    expect(tick(working: false, atSeconds: 15), isTrue);
  });

  test('it notifies once, not on every later tick', () {
    tick(working: true, atSeconds: 0);
    tick(working: false, atSeconds: 6);
    expect(tick(working: false, atSeconds: 14), isTrue);
    expect(tick(working: false, atSeconds: 20), isFalse);
    expect(tick(working: false, atSeconds: 60), isFalse);
  });

  test('output resuming inside the grace window cancels the notice', () {
    // This is the mid-turn thinking pause: the tracker calls it idle after 2.5s
    // even though the turn continues. One turn must not fire several times.
    tick(working: true, atSeconds: 0);
    tick(working: false, atSeconds: 6);
    expect(tick(working: true, atSeconds: 9), isFalse);
    // Even well past the original grace deadline, nothing fires for that pause.
    expect(tick(working: false, atSeconds: 20), isFalse);
    expect(tick(working: false, atSeconds: 27), isFalse);
    // Only the burst that actually ended gets announced.
    expect(tick(working: false, atSeconds: 28), isTrue);
  });

  test('a burst shorter than minimumWorkDuration never arms', () {
    // A quick `ls`.
    tick(working: true, atSeconds: 0);
    tick(working: false, atSeconds: 3);
    expect(tick(working: false, atSeconds: 30), isFalse);
  });

  test('a pane that reports agent status is left to the semantic service', () {
    tick(working: true, atSeconds: 0, agent: true);
    expect(tick(working: false, atSeconds: 6, agent: true), isFalse);
    expect(tick(working: false, atSeconds: 20, agent: true), isFalse);
  });

  test('the agent-status latch survives the caller going false', () {
    // The caller reads an attention row that is pruned after 30 minutes idle.
    // Un-latching would resume double-firing on exactly the panes that already
    // have semantic notifications.
    tick(working: true, atSeconds: 0, agent: true);
    tick(working: true, atSeconds: 6, agent: false);
    expect(tick(working: false, atSeconds: 7, agent: false), isFalse);
    expect(tick(working: false, atSeconds: 30, agent: false), isFalse);
  });

  test('retainOnly forgets a closed pane, latch included', () {
    tick(working: true, atSeconds: 0, agent: true);
    detector.retainOnly({'other'});

    // A pane id reused after close starts clean.
    expect(tick(working: true, atSeconds: 10), isFalse);
    expect(tick(working: false, atSeconds: 16), isFalse);
    expect(tick(working: false, atSeconds: 24), isTrue);
  });

  test('panes are tracked independently', () {
    tick(working: true, atSeconds: 0);
    tick(working: true, atSeconds: 0, paneId: 'p2');
    tick(working: false, atSeconds: 6);
    // p2 is still busy while p1's grace window runs out.
    expect(tick(working: true, atSeconds: 14, paneId: 'p2'), isFalse);
    expect(tick(working: false, atSeconds: 14), isTrue);
    expect(tick(working: false, atSeconds: 21, paneId: 'p2'), isFalse);
    expect(tick(working: false, atSeconds: 29, paneId: 'p2'), isTrue);
  });
}
