import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';

/// This phone's own network context above the hosts list. Pairing fails most
/// often because the two devices are on different subnets, so showing the local
/// IPv4 next to the desktop's advertised address makes that diagnosable without
/// leaving the app. Renders nothing when no LAN address resolved.
class PairingNetworkStrip extends StatelessWidget {
  const PairingNetworkStrip({super.key, required this.localIp});

  final String? localIp;

  @override
  Widget build(BuildContext context) {
    final ip = localIp;
    if (ip == null || ip.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    return Padding(
      key: AppKeys.pairingNetworkStrip,
      padding: EdgeInsets.only(bottom: spacing.md),
      child: Row(
        children: [
          TpStatusBadge(
            label: context.l10n.pairingLanLabel,
            tone: TpStatusBadgeTone.success,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              ip,
              style: appMonoTextStyle(
                context,
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
