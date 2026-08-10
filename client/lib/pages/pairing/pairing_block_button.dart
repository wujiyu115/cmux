import 'package:flutter/material.dart';

/// Prototype `.btn`: a full-width call-to-action that fills its row, stands
/// 56 logical tall, has a 14px radius and an 18/600 label — the size language
/// the shared [TpButton] cannot express (its theme caps every button at the
/// compact 26px track).
///
/// Colors stay theme-driven: [filled] paints [ColorScheme.primary] /
/// [ColorScheme.onPrimary]; the outline form borders with
/// [ColorScheme.outlineVariant] over [ColorScheme.onSurface].
class PairingBlockButton extends StatelessWidget {
  const PairingBlockButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.outlined = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Both sizes pinned so the global button theme (which clamps height to the
    // 26px compact track) cannot shrink this back below the prototype's 56.
    final base = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 56)),
      maximumSize: const WidgetStatePropertyAll(Size(double.infinity, 56)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 22),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    return TextButton(
      onPressed: onPressed,
      style: outlined
          ? base.copyWith(
              foregroundColor: WidgetStatePropertyAll(cs.onSurface),
              side: WidgetStatePropertyAll(
                BorderSide(color: cs.outlineVariant),
              ),
              overlayColor: WidgetStatePropertyAll(
                cs.onSurface.withValues(alpha: 0.08),
              ),
            )
          : base.copyWith(
              backgroundColor: WidgetStatePropertyAll(cs.primary),
              foregroundColor: WidgetStatePropertyAll(cs.onPrimary),
              overlayColor: WidgetStatePropertyAll(
                cs.onPrimary.withValues(alpha: 0.12),
              ),
            ),
      child: child,
    );
  }
}
