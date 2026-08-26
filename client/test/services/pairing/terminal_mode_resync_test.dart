import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/terminal_mode_resync.dart';

void main() {
  group('terminalModeResync', () {
    test('emits DECTCEM show when the pane shows its cursor', () {
      // ESC [ ? 2 5 h
      expect(
        terminalModeResync(cursorVisible: true),
        [0x1b, 0x5b, 0x3f, 0x32, 0x35, 0x68],
      );
    });

    test('emits DECTCEM hide when the pane hides its cursor', () {
      // ESC [ ? 2 5 l — the case that fixes the mirror's second cursor.
      expect(
        terminalModeResync(cursorVisible: false),
        [0x1b, 0x5b, 0x3f, 0x32, 0x35, 0x6c],
      );
    });

    test('states the mode absolutely rather than only correcting a mismatch', () {
      // Both branches emit something: relying on what a fresh `Term` defaults to
      // would make this silently wrong if that default ever changed.
      expect(terminalModeResync(cursorVisible: true), isNotEmpty);
      expect(terminalModeResync(cursorVisible: false), isNotEmpty);
      expect(
        terminalModeResync(cursorVisible: true),
        isNot(terminalModeResync(cursorVisible: false)),
      );
    });

    test('differs only in the final byte', () {
      // `h` sets, `l` resets; everything before is the DEC private mode prefix.
      final shown = terminalModeResync(cursorVisible: true);
      final hidden = terminalModeResync(cursorVisible: false);
      expect(shown.length, hidden.length);
      expect(shown.sublist(0, shown.length - 1), hidden.sublist(0, hidden.length - 1));
    });

    test('is short enough to prepend to every snapshot', () {
      // It goes out on every subscribe, including ones with an empty ring.
      expect(terminalModeResync(cursorVisible: true).length, lessThan(16));
    });
  });
}
