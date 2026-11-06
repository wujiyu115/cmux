import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';

/// Phone-shell chrome, restyled after Orca's mobile app: a near-black page with
/// rounded gray cards, circular glyph chips, and an icon + label bottom bar.
///
/// Everything here is theme-driven — surfaces are derived from the active
/// [ColorScheme] (card = a lifted surface, hairlines = a faint onSurface wash),
/// so light themes and the terminal-derived palettes keep working. Sizes are the
/// phone layout's own logical px; the prototype text-boost note in the pairing
/// pages applies here too.
///
/// The bar deliberately carries only the two destinations the phone actually
/// has (activity + settings). Orca's usage / automation tabs have no equivalent
/// in this app, and a tab that opens nothing is worse than a shorter bar.

/// Top-level destinations in [MobileBottomNav], in bar order.
enum MobileTab { activity, settings }

/// Status colour for "this machine / this session is live". Fixed rather than
/// [ColorScheme.tertiary] so the dot reads as *online* in every theme — the
/// amber / violet / green presets each tint tertiary differently, and a status
/// dot that changes hue with the theme stops being a status dot.
Color mobileOnlineColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF32D74B)
    : const Color(0xFF1E9E4A);

Color mobileCardColor(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Color.alphaBlend(cs.onSurface.withValues(alpha: 0.06), cs.surface);
}

Color mobileHairlineColor(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return cs.onSurface.withValues(alpha: 0.09);
}

/// Faint tile behind a glyph chip (desktop icon, terminal dot).
Color mobileGlyphTileColor(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return cs.onSurface.withValues(alpha: 0.08);
}

/// Bottom destination bar: icon over label, active item in [ColorScheme.onSurface],
/// inactive in a muted variant. Sits on the page colour with a hairline on top,
/// matching the reference rather than Material's tinted NavigationBar.
class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({
    super.key,
    required this.current,
    required this.onSelected,
  });

  final MobileTab current;
  final ValueChanged<MobileTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: mobileHairlineColor(context))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _Item(
                tab: MobileTab.activity,
                icon: Icons.dynamic_feed_outlined,
                label: context.l10n.mobileTabActivity,
                selected: current == MobileTab.activity,
                onTap: onSelected,
              ),
              _Item(
                key: AppKeys.mobileSettingsButton,
                tab: MobileTab.settings,
                icon: Icons.settings_outlined,
                label: context.l10n.settings,
                selected: current == MobileTab.settings,
                onTap: onSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    super.key,
    required this.tab,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final MobileTab tab;
  final IconData icon;
  final String label;
  final bool selected;
  final ValueChanged<MobileTab> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.onSurface : cs.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(tab),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 40pt circular chip used for the back / more affordances above a detail list.
class MobileRoundButton extends StatelessWidget {
  const MobileRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 40,
    this.iconSize = 20,
    this.foreground,
    this.background,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  /// Defaults to [ColorScheme.onSurface] on the card surface.
  final Color? foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background ?? mobileCardColor(context),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: iconSize,
              color: foreground ?? cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width action row inside a card (reference `.card .action`): accent glyph
/// + accent label, used for "Pair a desktop".
class MobileCardActionRow extends StatelessWidget {
  const MobileCardActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.foreground,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final color = foreground ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
