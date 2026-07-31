import 'dart:io';

import '../../utils/logging/logger.dart';

/// This device's own LAN IPv4, shown on the mobile hosts screen so a failed
/// pairing can be diagnosed against the desktop's advertised subnet.
///
/// Keeps `dart:io` out of the UI: the hosts screen only ever reads the resolved
/// string off `PairingClientState.localIp`. Returns null when the phone has no
/// usable LAN address (cellular only, Wi-Fi off, or self-assigned link-local).
Future<String?> readPrimaryLanIpv4() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        // 169.254/16 means DHCP never answered — useless for reaching a desktop.
        if (addr.address.startsWith('169.254.')) continue;
        return addr.address;
      }
    }
  } on Object catch (e) {
    appLogger.d('local lan ip lookup failed: $e');
  }
  return null;
}
