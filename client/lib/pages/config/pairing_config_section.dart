import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_ui/shared_ui.dart';

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
      unawaited(cubit.refreshInterfaces());
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
            if (state.enabled || state.running)
              _LocalAddressRow(state: state, cubit: cubit),
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
              _DeviceList(devices: state.devices, onRevoke: cubit.revokeDevice),
            ],
          ],
        );
      },
    );
  }
}

/// "此电脑的地址": which local address the pairing code advertises.
///
/// With a VPN or a virtual adapter present, the machine has several addresses
/// and a phone has to time out on each dead route before it reaches the one
/// that works. Picking one here puts a single address in the code.
class _LocalAddressRow extends StatefulWidget {
  const _LocalAddressRow({required this.state, required this.cubit});

  final PairingHostState state;
  final PairingHostCubit cubit;

  @override
  State<_LocalAddressRow> createState() => _LocalAddressRowState();
}

class _LocalAddressRowState extends State<_LocalAddressRow> {
  /// Menu value for the trailing "add custom address…" action. Selecting a
  /// menu item latches the select's internal value, so the row rebuilds the
  /// select (via this generation counter) after the action runs.
  static const _customValue = '__custom__';

  int _generation = 0;

  Future<void> _addCustomAddress() async {
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => const _CustomAddressDialog(),
    );
    if (!mounted) return;
    setState(() => _generation++);
    if (entered != null) {
      await widget.cubit.setAdvertisedAddress(entered);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final chosen = widget.state.advertisedAddress;
    final entries = <(String, String)>[
      ('', l10n.pairingLocalAddressAll),
      for (final address in widget.state.interfaces)
        (address.ip, l10n.pairingLocalAddressEntry(address.ip, address.name)),
      // An address typed by hand, or one saved when the machine had another
      // network: it must stay selectable even though it is not listed now.
      if (chosen != null && !widget.state.interfaces.any((a) => a.ip == chosen))
        (chosen, chosen),
      (_customValue, l10n.pairingLocalAddressCustom),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.pairingLocalAddressTitle,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              KeyedSubtree(
                key: ValueKey(_generation),
                child: TpCompactSelect<String>(
                  key: AppKeys.pairingLocalAddressSelect,
                  value: chosen ?? '',
                  entries: entries,
                  minWidth: 220,
                  onChanged: (value) {
                    if (value == _customValue) {
                      unawaited(_addCustomAddress());
                      return;
                    }
                    unawaited(
                      widget.cubit.setAdvertisedAddress(
                        value == null || value.isEmpty ? null : value,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              TpIconButton(
                key: AppKeys.pairingLocalAddressRefresh,
                icon: Icons.refresh,
                iconSize: 18,
                tooltip: l10n.pairingLocalAddressRefresh,
                onTap: () => unawaited(widget.cubit.refreshInterfaces()),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.pairingLocalAddressHint,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Free-text address for users whose reachable address is not on a local NIC
/// (a tunnel endpoint, a DNS name). Validated before it can reach the offer.
class _CustomAddressDialog extends StatefulWidget {
  const _CustomAddressDialog();

  @override
  State<_CustomAddressDialog> createState() => _CustomAddressDialogState();
}

class _CustomAddressDialogState extends State<_CustomAddressDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final host = Uri.tryParse('ws://$value')?.host ?? '';
    if (value.isEmpty || host.isEmpty || host != value) {
      setState(() => _error = context.l10n.pairingLocalAddressInvalid);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.pairingLocalAddressCustomTitle),
      content: TpInput(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.pairingLocalAddressCustomHint,
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TpButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TpButton(
          key: AppKeys.pairingLocalAddressCustomSave,
          onPressed: _submit,
          child: Text(l10n.ok),
        ),
      ],
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
            SelectableText(
              url,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
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
