import 'package:flutter/foundation.dart';

/// A phone currently mirroring a terminal. While non-null the desktop pane
/// yields the grid: it stops pushing SIGWINCH and refuses input, so the two
/// ends never fight over the shared PTY's size.
@immutable
class TerminalMirrorTakeover {
  const TerminalMirrorTakeover({
    required this.viewers,
    required this.cols,
    required this.rows,
  });

  /// Refcount: more than one phone can mirror the same terminal.
  final int viewers;

  /// The phone-driven grid the PTY is currently sized to (banner copy).
  final int cols;
  final int rows;

  TerminalMirrorTakeover copyWith({int? viewers, int? cols, int? rows}) {
    return TerminalMirrorTakeover(
      viewers: viewers ?? this.viewers,
      cols: cols ?? this.cols,
      rows: rows ?? this.rows,
    );
  }
}
