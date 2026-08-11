import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// The top bar shared by the mobile pairing screens: back affordance, a title,
/// and one optional trailing slot.
///
/// The pairing client is a 1:1 port of the 393-logical-px prototype, so the
/// sizes here are the prototype's exact px (not scaled [TpTextStyles] roles):
/// `.appbar` min-height 56, large title 26/700, centered title 18/600.
///
/// Not an [AppBar]: these screens are phases of one flow inside a single shell
/// rather than pushed routes, so there is no Navigator entry for an AppBar's
/// automatic leading button to derive from.
class PairingNavBar extends StatelessWidget {
  const PairingNavBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.backTooltip,
    this.count,
  }) : large = false;

  /// Large left-aligned title bar used by the list / settings screens
  /// (desktops, settings, customize keys, voice). Mirrors the prototype's
  /// default `.appbar` (big title, optional count and trailing action) while
  /// the default constructor mirrors the centered `.appbar.center`.
  const PairingNavBar.large({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.backTooltip,
    this.count,
  }) : large = true;

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final String? backTooltip;

  /// Optional count shown next to the title (e.g. paired-desktop count).
  final String? count;
  final bool large;

  /// Prototype `.appbar` min-height and horizontal padding (px, 393 space).
  static const double height = 56;
  static const double _hPadding = 16;
  static const double _slotWidth = 48;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: height),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _hPadding,
            vertical: large ? 10 : 0,
          ),
          child: large ? _buildLarge(context, cs) : _buildCentered(context, cs),
        ),
      ),
    );
  }

  Widget _buildCentered(BuildContext context, ColorScheme cs) {
    return Row(
      children: [
        SizedBox(
          width: _slotWidth,
          child: onBack == null
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: PairingNavAction(
                    icon: Icons.arrow_back,
                    tooltip: backTooltip ?? context.l10n.back,
                    onTap: onBack!,
                  ),
                ),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            // Prototype centered `.appbar` title: 18px / 600.
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Grows past one slot for multi-action trailings (e.g. add + refresh),
        // but keeps a full slot when empty so a lone back button stays centered.
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: _slotWidth),
          child: trailing ?? const SizedBox(width: _slotWidth),
        ),
      ],
    );
  }

  Widget _buildLarge(BuildContext context, ColorScheme cs) {
    return Row(
      children: [
        if (onBack != null) ...[
          PairingNavAction(
            icon: Icons.arrow_back,
            tooltip: backTooltip ?? context.l10n.back,
            onTap: onBack!,
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            title,
            // Prototype large `.appbar` title: 26px / 700.
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 12),
          Text(
            count!,
            // Prototype `.appbar .count`: 17px, muted.
            style: TextStyle(fontSize: 17, color: cs.onSurfaceVariant),
          ),
        ],
        if (trailing != null) ...[const SizedBox(width: 4), trailing!],
      ],
    );
  }
}

/// A 48pt touch-target icon action sized for [PairingNavBar]'s slots. Matches
/// the prototype `.appbar .back` / `.act`: a 48px tap target with a 24px glyph.
class PairingNavAction extends StatelessWidget {
  const PairingNavAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconSize = 24,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Glyph size. Prototype: back arrow 24, other actions 22.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return TpIconButton(
      icon: icon,
      tooltip: tooltip,
      size: 48,
      iconSize: iconSize,
      onTap: onTap,
    );
  }
}
