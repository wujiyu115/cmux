import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_typography_scale.dart';
import '../../utils/ui/app_keys.dart';

/// One session or live terminal under a workspace. Title in UI type, the command
/// / model line in mono, liveness and geometry as trailing metadata — so a
/// column of rows scans by title first and detail second.
///
/// While the host is waking a dormant node the trailing block becomes the
/// progress affordance and the row stops accepting taps.
class PairingNodeRow extends StatelessWidget {
  const PairingNodeRow({
    super.key,
    required this.node,
    required this.busy,
    required this.onTap,
  });

  final PairingSessionNode node;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final typography = context.appTypography;
    final mono = appMonoTextStyle(
      context,
      fontSize: typography.bodySmall,
      color: cs.onSurfaceVariant,
    );
    return InkWell(
      key: AppKeys.pairingSessionNode(node.nodeKey),
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(spacing.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: EdgeInsets.only(
            left: spacing.xl,
            right: spacing.xs,
            top: spacing.sm,
            bottom: spacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.terminal_outlined,
                size: 17,
                color: node.live ? cs.tertiary : cs.onSurfaceVariant,
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      node.title.isEmpty ? node.nodeKey : node.title,
                      style: busy
                          ? styles.smMediumColored(cs.onSurfaceVariant)
                          : styles.smMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (node.subtitle.isNotEmpty) ...[
                      SizedBox(height: spacing.xxs),
                      Text(
                        node.subtitle,
                        style: mono,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              if (busy)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.pairingActivating, style: mono),
                    SizedBox(width: spacing.sm),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (node.live) ...[
                      Text('${node.cols}×${node.rows}', style: mono),
                      SizedBox(width: spacing.sm),
                    ],
                    TpStatusBadge(
                      label: node.live
                          ? l10n.pairingLiveBadge
                          : l10n.pairingOfflineBadge,
                      tone: node.live
                          ? TpStatusBadgeTone.success
                          : TpStatusBadgeTone.neutral,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
