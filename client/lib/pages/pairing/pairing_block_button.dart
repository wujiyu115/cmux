import 'package:flutter/material.dart';

/// Prototype `.btn` family: the full-width call-to-action language of the mobile
/// pairing flow — 50 logical tall, 12px radius, 15/600 label (the app's phone
/// pages size text ~15% down from the prototype's 16 to offset the mobile text
/// boost). The shared [TpButton] cannot express this: its theme caps every
/// button at the compact 26px desktop track.
///
/// Variants map to the prototype's classes:
/// [PairingButtonVariant.filled] `.btn-primary`, [PairingButtonVariant.secondary]
/// `.btn-secondary`, [PairingButtonVariant.quiet] `.btn-quiet` (44 tall, 14/500).
/// [PairingButtonVariant.outlined] is the transparent bordered form used inline
/// in workspace rows.
///
/// Colors stay theme-driven: filled paints [ColorScheme.primary] /
/// [ColorScheme.onPrimary]; secondary fills [ColorScheme.surface] with an
/// [ColorScheme.outlineVariant] border.
class PairingBlockButton extends StatelessWidget {
  const PairingBlockButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.variant = PairingButtonVariant.filled,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final PairingButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final quiet = variant == PairingButtonVariant.quiet;
    // Both sizes pinned so the global button theme (which clamps height to the
    // 26px compact track) cannot shrink this back below the prototype metrics.
    final height = quiet ? 44.0 : 50.0;
    final base = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(double.infinity, height)),
      maximumSize: WidgetStatePropertyAll(Size(double.infinity, height)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: quiet ? 12 : 18),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: quiet ? 14 : 15,
          fontWeight: quiet ? FontWeight.w500 : FontWeight.w600,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    return TextButton(
      onPressed: onPressed,
      style: switch (variant) {
        PairingButtonVariant.filled => base.copyWith(
          backgroundColor: WidgetStatePropertyAll(cs.primary),
          foregroundColor: WidgetStatePropertyAll(cs.onPrimary),
          overlayColor: WidgetStatePropertyAll(
            cs.onPrimary.withValues(alpha: 0.12),
          ),
        ),
        PairingButtonVariant.secondary => base.copyWith(
          backgroundColor: WidgetStatePropertyAll(cs.surface),
          foregroundColor: WidgetStatePropertyAll(cs.onSurface),
          side: WidgetStatePropertyAll(
            BorderSide(color: cs.outlineVariant),
          ),
          overlayColor: WidgetStatePropertyAll(
            cs.onSurface.withValues(alpha: 0.08),
          ),
        ),
        PairingButtonVariant.outlined => base.copyWith(
          foregroundColor: WidgetStatePropertyAll(cs.onSurface),
          side: WidgetStatePropertyAll(
            BorderSide(color: cs.outlineVariant),
          ),
          overlayColor: WidgetStatePropertyAll(
            cs.onSurface.withValues(alpha: 0.08),
          ),
        ),
        PairingButtonVariant.quiet => base.copyWith(
          foregroundColor: WidgetStatePropertyAll(cs.onSurfaceVariant),
          overlayColor: WidgetStatePropertyAll(
            cs.onSurface.withValues(alpha: 0.08),
          ),
        ),
      },
      child: child,
    );
  }
}

enum PairingButtonVariant { filled, secondary, outlined, quiet }
