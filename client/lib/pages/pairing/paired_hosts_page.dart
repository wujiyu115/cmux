import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';

/// Mobile home (orca `index`): the list of desktops this phone has paired with,
/// plus the entry point to scan a new one. Empty state points at the scanner.
class PairedHostsPage extends StatelessWidget {
  const PairedHostsPage({required this.onScan, super.key});

  /// Opens the QR scanner (host injects navigation; keeps this page routing-free).
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PairingClientCubit, PairingClientState>(
      buildWhen: (a, b) => a.pairedDesktops != b.pairedDesktops,
      builder: (context, state) {
        final l10n = context.l10n;
        final cubit = context.read<PairingClientCubit>();
        final desktops = state.pairedDesktops;
        return Scaffold(
          key: AppKeys.pairedHostsPage,
          appBar: AppBar(title: Text(l10n.pairingDesktops)),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: onScan,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(l10n.pairingScan),
          ),
          body: desktops.isEmpty
              ? _EmptyState(onScan: onScan)
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: desktops.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = desktops[i];
                    return ListTile(
                      key: ValueKey('paired-desktop-${d.id}'),
                      leading: const Icon(Icons.desktop_windows_outlined),
                      title: Text(d.name),
                      subtitle: Text(
                        d.wsUrls.isEmpty ? d.id : d.wsUrls.first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l10n.pairingRemove,
                        onPressed: () => cubit.removeDesktop(d.id),
                      ),
                      onTap: () => cubit.connectToDesktop(d),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2, size: 64),
            const SizedBox(height: 16),
            Text(
              l10n.pairingNoPairedDesktops,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.pairingEmptyHint,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(l10n.pairingScanQrCode),
            ),
          ],
        ),
      ),
    );
  }
}
