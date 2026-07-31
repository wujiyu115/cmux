import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// The square, outlined desktop mark used on the hosts list and the confirm
/// card. Reads as hardware rather than as a filled avatar, which keeps the row's
/// visual weight on the host name.
class PairingHostGlyph extends StatelessWidget {
  const PairingHostGlyph({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(context.tpSpacing.sm),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Icon(
        Icons.desktop_windows_outlined,
        size: size * 0.5,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}
