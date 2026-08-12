import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../repositories/pairing_settings_repository.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import '../../utils/ui/coarse_relative_time.dart';

/// One paired desktop on the mobile home list: a bold name over its LAN address
/// (prefixed with a monitor glyph) and last-connect time in mono (they are
/// machine facts, not prose). Rows are separated by hairlines by the caller —
/// stacked cards would read as unrelated panels rather than one list.
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
    final spacing = context.tpSpacing;
    final iconSizes = context.tpIconSizes;
    final mono = appMonoTextStyle(
      context,
      fontSize: 12,
      color: cs.onSurfaceVariant,
    );
    final lastConnected = desktop.lastConnectedAt;

    return Padding(
      key: AppKeys.pairedHostRow(desktop.id),
      padding: EdgeInsets.symmetric(vertical: spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(spacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    desktop.name,
                    // Same rank as a workspace name in the session list, so the
                    // two lists read as one size language. The prototype's
                    // 21 / 700 reads a size larger on device (phone-wide 15%
                    // text boost) and bold made a single row shout.
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: spacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.desktop_windows_outlined,
                        size: iconSizes.sm,
                        color: cs.onSurfaceVariant,
                      ),
                      SizedBox(width: spacing.sm),
                      Expanded(
                        child: Text(
                          desktop.displayUrl,
                          style: mono,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (lastConnected != null) ...[
                    SizedBox(height: spacing.xs),
                    Text(
                      l10n.pairingLastConnected(
                        formatCoarseRelativeTime(l10n, lastConnected),
                      ),
                      style: mono,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(width: spacing.sm),
          TpIconButton(
            icon: Icons.delete_outline,
            tooltip: l10n.pairingRemove,
            size: 44,
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}
