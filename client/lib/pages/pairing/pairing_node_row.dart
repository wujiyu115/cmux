import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import 'mobile_chrome.dart';

/// One live terminal under an expanded workspace: a liveness dot, the terminal
/// title, its command / cwd line in mono, and the grid size at the trailing
/// edge — the reference's nested session row.
///
/// While the host is waking a dormant node the trailing block becomes the
/// progress affordance and the row stops accepting taps.
///
/// Long-press offers the destructive action (close the pane host-side); taps
/// keep their open-mirror meaning.
class PairingNodeRow extends StatelessWidget {
  const PairingNodeRow({
    super.key,
    required this.node,
    required this.busy,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  final PairingSessionNode node;
  final bool busy;

  /// This row's terminal is the one the tablet sidebar's right pane mirrors.
  /// Always false on a phone, where the list is not on screen while mirroring.
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final titleStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: busy ? muted : cs.onSurface,
    );
    return Material(
      // A tinted Material rather than a painted box, so the row's ink splash
      // still lands *above* the tint instead of underneath it.
      color: selected ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: AppKeys.pairingSessionNode(node.nodeKey),
        onTap: busy ? null : onTap,
        onLongPress: busy ? null : onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 8, 4, 8),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: node.live
                        ? mobileOnlineColor(context)
                        : cs.onSurface.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
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
                        const SizedBox(height: 2),
                        Text(
                          node.subtitle,
                          style: appMonoTextStyle(
                            context,
                            fontSize: 11.5,
                            color: muted.withValues(alpha: 0.85),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (busy)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.pairingActivating,
                        style: appMonoTextStyle(
                          context,
                          fontSize: 11.5,
                          color: muted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  )
                else if (node.live)
                  Text(
                    '${node.cols}×${node.rows}',
                    style: appMonoTextStyle(
                      context,
                      fontSize: 11.5,
                      color: muted.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
