import 'dart:typed_data';

import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/flush_terminal_engine.dart';

/// The pairing mode resync (`terminalModeResync`) trusts that
/// `TerminalSession.cursorVisible` — `engine.grid.cursorVisible` — tracks what
/// the pane's program last asked for via DECTCEM. This test proves the engine
/// side of that contract with the real parser, independent of any phone: a
/// full-screen program hides the cursor with `CSI ?25l` once at startup, and
/// if that byte fell out of the retained snapshot window the mirror would
/// otherwise keep painting a hardware cursor.
void main() {
  test('grid.cursorVisible follows DECTCEM hide/show', () async {
    final engine = TerminalEngine(config: TerminalConfig.defaults());
    engine.resize(columns: 40, rows: 5);
    engine.initializeEmpty(5, 40);
    engine.feed(Uint8List.fromList('prompt> '.codeUnits));
    await flushTerminalEngine(engine);

    expect(engine.grid.cursorVisible, isTrue,
        reason: 'the plain prompt shows the hardware cursor');

    engine.feed(Uint8List.fromList('\x1b[?25l'.codeUnits));
    await flushTerminalEngine(engine);
    expect(engine.grid.cursorVisible, isFalse,
        reason: 'CSI ?25l hides the cursor — what a full-screen program '
            'sends once at startup');

    engine.feed(Uint8List.fromList('\x1b[?25h'.codeUnits));
    await flushTerminalEngine(engine);
    expect(engine.grid.cursorVisible, isTrue,
        reason: 'CSI ?25h shows it again');

    engine.dispose();
  });

  test('the hide survives later screen repaints', () async {
    // A full-screen program hides the cursor once, then repaints the screen
    // many times. The resync reads the value at subscribe time, which can be
    // minutes later — a repaint must not re-show the cursor.
    final engine = TerminalEngine(config: TerminalConfig.defaults());
    engine.resize(columns: 40, rows: 5);
    engine.initializeEmpty(5, 40);
    engine.feed(Uint8List.fromList('\x1b[?25lframe one\n'.codeUnits));
    await flushTerminalEngine(engine);
    engine.feed(Uint8List.fromList('\x1b[2Jframe two\nframe three\n'.codeUnits));
    await flushTerminalEngine(engine);

    expect(engine.grid.cursorVisible, isFalse);
    engine.dispose();
  });
}
