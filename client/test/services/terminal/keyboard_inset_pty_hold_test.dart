import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/keyboard_inset_pty_hold.dart';
import 'package:teampilot/services/terminal/terminal_layout_coordinator.dart';

/// Records the bracket calls in order, so a test can assert one hold spanning
/// many insets rather than a hold per inset.
class _RecordingTarget implements PtyResizeHoldTarget {
  final calls = <String>[];

  @override
  void beginPtyHold() => calls.add('begin');

  @override
  void endPtyHold({bool flush = true}) => calls.add('end(flush:$flush)');
}

void main() {
  const settle = Duration(milliseconds: 120);

  group('KeyboardInsetPtyHold', () {
    test('one keyboard animation yields one hold and one flush', () {
      fakeAsync((async) {
        final target = _RecordingTarget();
        final hold = KeyboardInsetPtyHold(target: () => target);

        // 16 frames of a growing inset, one per vsync — what Android actually
        // reports while the IME slides up.
        for (var frame = 1; frame <= 16; frame++) {
          hold.onInsetChanged(frame * 20.0);
          async.elapse(const Duration(milliseconds: 16));
        }
        expect(target.calls, ['begin'], reason: 'held for the whole animation');
        expect(hold.isHolding, isTrue);

        async.elapse(settle);
        expect(target.calls, ['begin', 'end(flush:true)']);
        expect(hold.isHolding, isFalse);
      });
    });

    test('a second animation opens a fresh bracket', () {
      fakeAsync((async) {
        final target = _RecordingTarget();
        final hold = KeyboardInsetPtyHold(target: () => target);

        hold.onInsetChanged(320);
        async.elapse(settle);
        // Keyboard dismissed: back to zero, one more bracket.
        hold.onInsetChanged(0);
        async.elapse(settle);

        expect(target.calls, [
          'begin',
          'end(flush:true)',
          'begin',
          'end(flush:true)',
        ]);
      });
    });

    test('a repeated inset is not a resize', () {
      fakeAsync((async) {
        final target = _RecordingTarget();
        final hold = KeyboardInsetPtyHold(target: () => target);

        hold.onInsetChanged(320);
        async.elapse(settle);
        target.calls.clear();

        // A metrics change that left the keyboard alone (cutout report,
        // rotation with no keyboard up) must not bracket anything.
        hold.onInsetChanged(320);
        async.elapse(settle);
        expect(target.calls, isEmpty);
      });
    });

    test('dispose ends the bracket without flushing', () {
      fakeAsync((async) {
        final target = _RecordingTarget();
        final hold = KeyboardInsetPtyHold(target: () => target);

        hold.onInsetChanged(320);
        hold.dispose();
        expect(target.calls, ['begin', 'end(flush:false)']);

        // The settle timer must be dead, not merely overtaken.
        async.elapse(settle * 2);
        expect(target.calls, ['begin', 'end(flush:false)']);
      });
    });

    test('survives a target that is not mounted yet', () {
      fakeAsync((async) {
        // The terminal view sits behind a GlobalKey: currentState is null until
        // the first layout, and a keyboard can be up before then.
        final hold = KeyboardInsetPtyHold(target: () => null);
        hold.onInsetChanged(320);
        async.elapse(settle);
        expect(hold.isHolding, isFalse);
      });
    });
  });
}
