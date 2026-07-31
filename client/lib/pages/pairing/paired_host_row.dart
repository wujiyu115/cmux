import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../repositories/pairing_settings_repository.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import '../../utils/ui/coarse_relative_time.dart';
import 'pairing_host_glyph.dart';

/// One paired desktop on the mobile home list: glyph, name, and its LAN address
/// and last-connect time in mono (they are machine facts, not prose). Rows are
/// separated by hairlines by the caller — stacked cards would read as unrelated
/// panels rather than one list.
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
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
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
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(spacing.sm),
              child: Row(
                children: [
                  const PairingHostGlyph(),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          desktop.name,
                          style: styles.mdSemibold,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: spacing.xxs),
                        Text(
                          desktop.wsUrls.isEmpty
                              ? desktop.id
                              : desktop.wsUrls.first,
                          style: mono,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (lastConnected != null) ...[
                          SizedBox(height: spacing.xxs),
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
