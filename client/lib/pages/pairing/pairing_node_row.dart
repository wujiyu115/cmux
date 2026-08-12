import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
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
    final spacing = context.tpSpacing;
    final mono = appMonoTextStyle(
      context,
      fontSize: 12,
      color: cs.onSurfaceVariant,
    );
    // Bottom rank of the list's hierarchy (group > workspace > terminal), so it
    // sits under the workspace name that owns it. The prototype's 17 / 500 reads
    // a size larger on device thanks to the phone-wide 15% text boost. Busy dims
    // it.
    final titleStyle = TextStyle(
      fontSize: 14,
      color: busy ? cs.onSurfaceVariant : cs.onSurface,
    );
    // Prototype `.iconbox`: 34px box, 20px glyph.
    const boxSize = 34.0;
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
              Container(
                width: boxSize,
                height: boxSize,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(spacing.sm),
                  border: Border.all(color: cs.outlineVariant),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.terminal_outlined,
                  size: 20,
                  color: node.live ? cs.tertiary : cs.onSurfaceVariant,
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      node.title.isEmpty ? node.nodeKey : node.title,
                      style: titleStyle,
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
