import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/toolbar_key_encoder.dart';

void main() {
  group('no modifier', () {
    test('passes bytes through untouched', () {
      expect(encodeToolbarKey([0x2f]), [0x2f]);
      expect(encodeToolbarKey([0x1b, 0x5b, 0x41]), [0x1b, 0x5b, 0x41]);
      expect(encodeToolbarKey(const []), isEmpty);
    });
  });

  group('ctrl', () {
    test('maps a printable byte into its control code', () {
      expect(encodeToolbarKey([0x61], ctrl: true), [0x01]); // ^A
      expect(encodeToolbarKey([0x40], ctrl: true), [0x00]); // ^@
      expect(encodeToolbarKey([0x7f], ctrl: true), [0x1f]);
    });

    test('leaves bytes outside 0x40..0x7f alone', () {
      expect(encodeToolbarKey([0x09], ctrl: true), [0x09]); // Tab
      expect(encodeToolbarKey([0x1b], ctrl: true), [0x1b]); // Esc
    });

    test('rewrites escape sequences with xterm modifier 5', () {
      expect(
        encodeToolbarKey([0x1b, 0x5b, 0x41], ctrl: true),
        [0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x41], // CSI 1;5 A
      );
      expect(
        encodeToolbarKey([0x1b, 0x4f, 0x50], ctrl: true),
        [0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x50], // F1 → CSI 1;5 P
      );
      expect(
        encodeToolbarKey([0x1b, 0x5b, 0x35, 0x7e], ctrl: true),
        [0x1b, 0x5b, 0x35, 0x3b, 0x35, 0x7e], // CSI 5;5 ~
      );
    });

    test('leaves a non-escape multi-byte key alone', () {
      expect(encodeToolbarKey([0x18, 0x18], ctrl: true), [0x18, 0x18]);
    });
  });

  group('alt', () {
    test('prefixes a single byte with ESC', () {
      expect(encodeToolbarKey([0x2f], alt: true), [0x1b, 0x2f]);
    });

    test('rewrites escape sequences with xterm modifier 3', () {
      expect(
        encodeToolbarKey([0x1b, 0x4f, 0x50], alt: true),
        [0x1b, 0x5b, 0x31, 0x3b, 0x33, 0x50],
      );
      expect(
        encodeToolbarKey([0x1b, 0x5b, 0x35, 0x7e], alt: true),
        [0x1b, 0x5b, 0x35, 0x3b, 0x33, 0x7e],
      );
    });
  });

  test('ctrl wins when both modifiers are somehow set', () {
    expect(encodeToolbarKey([0x61], ctrl: true, alt: true), [0x01]);
  });

  test('unrecognised escape shapes are returned unchanged', () {
    // CSI 200 h — parameterised but not a "~"-terminated key.
    const raw = [0x1b, 0x5b, 0x32, 0x30, 0x30, 0x68];
    expect(encodeToolbarKey(raw, ctrl: true), raw);
  });

  group('terminalizeNewlines', () {
    test('turns LF and CRLF into CR so the shell submits', () {
      expect(terminalizeNewlines('a\nb'), 'a\rb');
      expect(terminalizeNewlines('a\r\nb'), 'a\rb');
      expect(terminalizeNewlines('plain'), 'plain');
      expect(terminalizeNewlines('trailing\n'), 'trailing\r');
    });
  });
}
