import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../cubits/pairing_host_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/app/platform_utils.dart';
import '../../services/pairing/device_registry.dart';
import '../../utils/ui/app_keys.dart';

/// Desktop config section: toggle the LAN pairing server, show the current QR
/// offer + LAN URLs for a phone to scan/enter, and manage paired devices.
class PairingConfigWorkspace extends StatefulWidget {
  const PairingConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  State<PairingConfigWorkspace> createState() => _PairingConfigWorkspaceState();
}

class _PairingConfigWorkspaceState extends State<PairingConfigWorkspace> {
  @override
  void initState() {
    super.initState();
    // Opening the pairing page = user is about to pair. Rotate a fresh TTL code
    // so the QR/deep-link on screen is always live (an old window may have
    // silently expired since the server started).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cubit = context.read<PairingHostCubit>();
      if (cubit.state.running) cubit.refreshOffer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final showHeading = widget.showHeading;
    if (!isPairingHost) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.l10n.pairingHostDesktopOnly),
        ),
      );
    }
    return BlocBuilder<PairingHostCubit, PairingHostState>(
      builder: (context, state) {
        final l10n = context.l10n;
        final cubit = context.read<PairingHostCubit>();
        return ListView(
          key: AppKeys.pairingConfigWorkspace,
          padding: const EdgeInsets.all(20),
          children: [
            if (showHeading)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  l10n.pairingSettingsTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            SwitchListTile(
              key: AppKeys.pairingHostEnableSwitch,
              title: Text(l10n.pairingEnableTitle),
              subtitle: Text(l10n.pairingEnableSubtitle),
              value: state.enabled,
              onChanged: (v) => cubit.setEnabled(v),
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (state.running) ...[
              const SizedBox(height: 16),
              _OfferCard(state: state, onRefresh: cubit.refreshOffer),
              const SizedBox(height: 24),
              _DeviceList(
                devices: state.devices,
                onRevoke: cubit.revokeDevice,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.state, required this.onRefresh});

  final PairingHostState state;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final offer = state.offer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.pairingScanToPair,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton.icon(
              key: AppKeys.pairingRefreshOfferButton,
              onPressed: () => onRefresh(),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.pairingNewCode),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (offer != null)
          Container(
            key: AppKeys.pairingQrImage,
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: QrImageView(
              data: offer.toDeepLink(),
              size: 220,
              backgroundColor: Colors.white,
            ),
          )
        else
          Text(l10n.pairingGeneratingCode),
        if (offer != null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.pairingCodeTtlHint,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.pairingManualCodeLabel,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  offer.toDeepLink(),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: offer.toDeepLink()),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.pairingCodeCopied)),
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text(l10n.pairingCopyCode),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text(
          l10n.pairingEnterAddressManually,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        if (state.lanUrls.isEmpty)
          Text(l10n.pairingNoLanAddress)
        else
          for (final url in state.lanUrls)
            SelectableText(url, style: const TextStyle(fontFamily: 'monospace')),
      ],
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.devices, required this.onRevoke});

  final List<PairedDeviceInfo> devices;
  final Future<void> Function(String deviceId) onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.pairingPairedDevices,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (devices.isEmpty)
          Text(l10n.pairingNoDevicesYet)
        else
          for (final device in devices)
            ListTile(
              key: ValueKey('pairing-device-${device.deviceId}'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone_android),
              title: Text(device.name),
              subtitle: Text(device.deviceId),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l10n.pairingRevoke,
                onPressed: () => onRevoke(device.deviceId),
              ),
            ),
      ],
    );
  }
}
