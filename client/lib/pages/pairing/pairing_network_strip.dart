import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import 'mobile_chrome.dart';

/// This phone's own network context under the hosts card. Pairing fails most
/// often because the two devices are on different subnets, so showing the local
/// IPv4 makes that diagnosable without leaving the app. Renders nothing when no
/// LAN address resolved.
class PairingNetworkStrip extends StatelessWidget {
  const PairingNetworkStrip({super.key, required this.localIp});

  final String? localIp;

  @override
  Widget build(BuildContext context) {
    final ip = localIp;
    if (ip == null || ip.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Row(
      key: AppKeys.pairingNetworkStrip,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: mobileOnlineColor(context),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          context.l10n.pairingLanLabel,
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
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
    );
  }
}
