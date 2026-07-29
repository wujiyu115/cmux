import '../workspace_dnd/path_reference_formatter.dart';

/// How a dropped file path is injected into the terminal.
enum TerminalPathDropMode {
  /// Write the text straight to the PTY with no trailing CR. Suits line-edited
  /// input where raw bytes land at the cursor.
  rawAppend,

  /// Wrap the text in bracketed-paste markers and send no CR, so a full-screen
  /// TUI inserts it without submitting.
  bracketedNoSubmit,
}

/// Rules for turning a dragged path into input-box text.
class TerminalPathDropBehavior {
  const TerminalPathDropBehavior({required this.mode, required this.quoting});

  final TerminalPathDropMode mode;
  final PathQuoting quoting;

  /// Default derived from full-screen input: TUIs need bracketed paste without
  /// submit; line-edited shells take a raw append. POSIX quote-if-needed.
  factory TerminalPathDropBehavior.defaultFor({
    required bool usesFullScreenInput,
  }) => TerminalPathDropBehavior(
    mode: usesFullScreenInput
        ? TerminalPathDropMode.bracketedNoSubmit
        : TerminalPathDropMode.rawAppend,
    quoting: PathQuoting.posixQuoteIfNeeded,
  );
}
