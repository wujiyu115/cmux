import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';

/// Live connection diagnostics (orca `ConnectionLog`). LAN pairing fails in
/// opaque ways — wrong IP, firewall, expired code — so the confirm flow shows
/// every step the client logs.
class ConnectionLogView extends StatelessWidget {
  const ConnectionLogView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PairingClientCubit, PairingClientState>(
      buildWhen: (a, b) => a.logs != b.logs,
      builder: (context, state) {
        final logs = state.logs;
        return Container(
          key: AppKeys.pairingConnectionLog,
          constraints: const BoxConstraints(maxHeight: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: logs.isEmpty
              ? Text(context.l10n.pairingWaitingForConnection)
              : ListView.builder(
                  reverse: true,
                  itemCount: logs.length,
                  itemBuilder: (context, i) {
                    final line = logs[logs.length - 1 - i];
                    return Text(
                      line,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
