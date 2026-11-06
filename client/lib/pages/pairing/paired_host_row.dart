import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../repositories/pairing_settings_repository.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import '../../utils/ui/coarse_relative_time.dart';
import 'mobile_chrome.dart';

/// One paired desktop inside the home card, in the reference's row shape: a
/// rounded glyph tile, a bold name, a dot-led status line, and the address that
/// last worked in mono below it. The chevron belongs to the row; the remove
/// affordance sits just before it so the destructive action never owns the
/// trailing edge on its own.
class PairedHostRow extends StatelessWidget {
  const PairedHostRow({
    super.key,
    required this.desktop,
    required this.onTap,
    required this.onRemove,
  });

  final PairedDesktop desktop;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final lastConnected = desktop.lastConnectedAt;
    final statusLine = lastConnected == null
        ? '${l10n.pairingDesktopFallback} · ${l10n.pairingLanLabel}'
        : l10n.pairingLastConnected(
            formatCoarseRelativeTime(l10n, lastConnected),
          );

    return InkWell(
      key: AppKeys.pairedHostRow(desktop.id),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: mobileGlyphTileColor(context),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.desktop_windows_outlined,
                size: 22,
                color: cs.onSurface.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    desktop.name,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: mobileOnlineColor(context),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          statusLine,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    desktop.displayUrl,
                    style: appMonoTextStyle(
                      context,
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            TpIconButton(
              icon: Icons.delete_outline,
              tooltip: l10n.pairingRemove,
              size: 36,
              iconSize: 18,
              color: cs.onSurfaceVariant,
              onTap: onRemove,
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
