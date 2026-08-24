import 'package:flutter/material.dart';

/// The mirror's terminal plus its floating touch-selection chip.
///
/// Exists as its own widget because the stacking is load-bearing and easy to
/// break: the terminal sizes its cell grid from the constraints it is handed, so
/// a [Stack] that shrink-wraps here hands it a zero-width box and the grid
/// collapses to the engine's 8-column floor.
class MirrorTerminalStack extends StatelessWidget {
  const MirrorTerminalStack({
    super.key,
    required this.terminal,
    required this.overlay,
  });

  /// Fills the whole box.
  final Widget terminal;

  /// Floats over [terminal]'s top-right corner. May be a zero-size box while
  /// there is nothing to show — that is exactly the case [StackFit.expand]
  /// protects the terminal from.
  final Widget overlay;

  @override
  Widget build(BuildContext context) => Stack(
    // Without this the stack shrink-wraps its non-positioned children, and the
    // only one is the chip — a `SizedBox.shrink()` whenever no selection is
    // live. The stack then measures 0 wide inside the column's loose cross-axis
    // constraints, and `Positioned.fill` faithfully passes that zero width down
    // to the terminal.
    fit: StackFit.expand,
    children: [
      terminal,
      Positioned(top: 8, right: 8, child: overlay),
    ],
  );
}
