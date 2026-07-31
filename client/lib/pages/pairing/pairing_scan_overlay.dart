import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Viewfinder chrome drawn over the camera: a 232pt reticle plus a success ring.
///
/// Purely decorative and wrapped in [IgnorePointer] by the caller's stack order
/// so it never intercepts the scanner's own gestures.
class PairingScanReticle extends StatelessWidget {
  const PairingScanReticle({super.key, required this.hit});

  /// True once a valid code was decoded — swaps the brackets for a check ring.
  final bool hit;

  static const double _size = 232;
  static const double _corner = 34;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: _size,
          height: _size,
          child: hit
              ? _HitRing(color: cs.tertiary)
              : Stack(
                  children: [
                    for (final corner in _Corner.values)
                      Align(
                        alignment: corner.alignment,
                        child: _Bracket(corner: corner, length: _corner),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _HitRing extends StatelessWidget {
  const _HitRing({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: 2.5),
      ),
      child: Center(child: Icon(Icons.check, size: 52, color: color)),
    );
  }
}

enum _Corner {
  topLeft(Alignment.topLeft),
  topRight(Alignment.topRight),
  bottomLeft(Alignment.bottomLeft),
  bottomRight(Alignment.bottomRight);

  const _Corner(this.alignment);

  final Alignment alignment;
}

class _Bracket extends StatelessWidget {
  const _Bracket({required this.corner, required this.length});

  final _Corner corner;
  final double length;

  @override
  Widget build(BuildContext context) {
    // Reticle sits on top of an unpredictable camera image, so it uses a fixed
    // light stroke rather than a theme surface color.
    const stroke = BorderSide(color: Colors.white, width: 2.5);
    const radius = Radius.circular(12);
    final isTop = corner == _Corner.topLeft || corner == _Corner.topRight;
    final isLeft = corner == _Corner.topLeft || corner == _Corner.bottomLeft;
    return SizedBox(
      width: length,
      height: length,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: isTop ? stroke : BorderSide.none,
            bottom: isTop ? BorderSide.none : stroke,
            left: isLeft ? stroke : BorderSide.none,
            right: isLeft ? BorderSide.none : stroke,
          ),
          borderRadius: BorderRadius.only(
            topLeft: corner == _Corner.topLeft ? radius : Radius.zero,
            topRight: corner == _Corner.topRight ? radius : Radius.zero,
            bottomLeft: corner == _Corner.bottomLeft ? radius : Radius.zero,
            bottomRight: corner == _Corner.bottomRight ? radius : Radius.zero,
          ),
        ),
      ),
    );
  }
}

/// The translucent card floating over the bottom of the viewfinder: what to aim
/// at, and the manual-entry escape hatch for when the camera can't see the code.
class PairingScanSheet extends StatelessWidget {
  const PairingScanSheet({
    super.key,
    required this.hint,
    required this.manualLabel,
    required this.onManualEntry,
    this.manualButtonKey,
  });

  final String hint;
  final String manualLabel;
  final VoidCallback onManualEntry;
  final Key? manualButtonKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(spacing.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hint, style: TpTextStyles.of(context).mutedSm),
                SizedBox(height: spacing.sm),
                TpButton(
                  key: manualButtonKey,
                  variant: TpButtonVariant.secondary,
                  onPressed: onManualEntry,
                  child: Text(manualLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
