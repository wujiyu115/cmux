import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';
import 'connection_log_view.dart';

/// Pairing confirmation (orca `pair-confirm`): three states
/// `awaiting → connecting → error`, an embedded [ConnectionLogView], and the
/// ~25s hard timeout enforced by the cubit so a bad LAN gives an actionable
/// error instead of an endless spinner. Cancel / back returns to the host list.
class PairingConfirmPage extends StatelessWidget {
  const PairingConfirmPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PairingClientCubit, PairingClientState>(
      builder: (context, state) {
        final l10n = context.l10n;
        final cubit = context.read<PairingClientCubit>();
        final phase = state.phase;
        final connecting = phase == PairingClientPhase.confirmConnecting;
        final isError = phase == PairingClientPhase.error;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) cubit.cancel();
          },
          child: Scaffold(
            key: AppKeys.pairingConfirmPage,
            appBar: AppBar(title: Text(l10n.pairingConfirmTitle)),
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusHeader(
                    connecting: connecting,
                    isError: isError,
                    error: state.error,
                  ),
                  const SizedBox(height: 20),
                  const Expanded(child: ConnectionLogView()),
                  const SizedBox(height: 16),
                  if (isError)
                    FilledButton(
                      onPressed: cubit.confirmPairing,
                      child: Text(l10n.pairingRetry),
                    )
                  else if (!connecting)
                    FilledButton(
                      onPressed: cubit.confirmPairing,
                      child: Text(l10n.pairingConnect),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: AppKeys.pairingConfirmCancelButton,
                    onPressed: cubit.cancel,
                    child: Text(l10n.cancel),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.connecting,
    required this.isError,
    required this.error,
  });

  final bool connecting;
  final bool isError;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    if (isError) {
      return Row(
        children: [
          Icon(Icons.error_outline, color: scheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error ?? l10n.pairingFailed,
              style: TextStyle(color: scheme.error),
            ),
          ),
        ],
      );
    }
    if (connecting) {
      return Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(l10n.pairingConnecting),
        ],
      );
    }
    return Text(l10n.pairingReadyHint);
  }
}
