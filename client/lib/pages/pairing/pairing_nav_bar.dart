import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// The 52pt top bar shared by the mobile pairing screens: back affordance, a
/// centered title, and one optional trailing slot.
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
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final String? backTooltip;

  static const double height = 52;
  static const double _slotWidth = 56;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.tpSpacing.sm),
          child: Row(
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
                  style: TpTextStyles.of(context).mdSemibold,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: _slotWidth,
                child: trailing == null
                    ? null
                    : Align(alignment: Alignment.centerRight, child: trailing),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 44pt touch-target icon action sized for [PairingNavBar]'s slots.
class PairingNavAction extends StatelessWidget {
  const PairingNavAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TpIconButton(icon: icon, tooltip: tooltip, size: 44, onTap: onTap);
  }
}
