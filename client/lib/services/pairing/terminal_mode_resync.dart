import 'dart:typed_data';

/// Bytes that put a freshly created mirror engine into the terminal modes the
/// desktop is actually in, prepended to the snapshot a new subscriber receives.
///
/// **Why this is needed at all.** A mirror replays [RecentPtyBuffer]'s last
/// ~64 KiB of raw PTY output into a brand-new engine. That ring keeps bytes, not
/// state: it tracks no DEC private modes and emits no reset preamble. A full-screen
/// program sets its modes *once*, at startup — Claude Code hides the hardware
/// cursor with `CSI ?25l` and from then on draws its own caret as a text glyph —
/// so by the time a phone subscribes, the sequence that set the mode is long
/// evicted. The new engine boots with `TermMode::SHOW_CURSOR` set and never hears
/// otherwise, so the phone painted a *second*, blinking cursor wherever the
/// program last wrote, on top of the caret glyph the program drew itself.
///
/// **Why absolute, not a diff.** This emits the sequence for the current state
/// either way rather than only correcting a mismatch. Six extra bytes are
/// cheaper than depending on what a fresh `Term` happens to default to.
///
/// Known gap: cursor visibility is the only mode carried across, because it is
/// the only one exposed on the Dart side today. The alternate screen buffer
/// (`?1049`), bracketed paste (`?2004`) and the mouse reporting modes have the
/// same hole — a program that enabled them before the retained window will have
/// a mirror that disagrees. Cursor visibility is the one a user can see.
Uint8List terminalModeResync({required bool cursorVisible}) {
  // DECTCEM. `h` shows, `l` hides.
  return Uint8List.fromList(
    cursorVisible
        ? const [0x1b, 0x5b, 0x3f, 0x32, 0x35, 0x68] // ESC [ ? 2 5 h
        : const [0x1b, 0x5b, 0x3f, 0x32, 0x35, 0x6c], // ESC [ ? 2 5 l
  );
}
