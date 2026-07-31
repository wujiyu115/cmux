import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import 'connection_log_view.dart';
import 'pairing_host_glyph.dart';
import 'pairing_nav_bar.dart';
import 'pairing_stage_steps.dart';

/// Pairing confirmation: the host being paired, a determinate step rail fed by
/// real [PairingStage] events, and the connection log for LAN diagnosis. The
/// ~25s hard timeout lives in the cubit so a bad network gives an actionable
/// failure instead of an endless spinner.
class PairingConfirmPage extends StatelessWidget {
  const PairingConfirmPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PairingClientCubit, PairingClientState>(
      builder: (context, state) {
        final l10n = context.l10n;
        final cubit = context.read<PairingClientCubit>();
        final spacing = context.tpSpacing;
        final connecting = state.phase == PairingClientPhase.confirmConnecting;
        final isError = state.phase == PairingClientPhase.error;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) cubit.cancel();
          },
          child: Scaffold(
            key: AppKeys.pairingConfirmPage,
            body: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PairingNavBar(
                    title: l10n.pairingConfirmTitle,
                    onBack: cubit.cancel,
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        spacing.lg,
                        spacing.lg,
                        spacing.lg,
                        spacing.lg,
                      ),
                      children: [
                        _HostCard(state: state),
                        SizedBox(height: spacing.xl),
                        Text(
                          l10n.pairingStepProgressTitle,
                          style: TpTextStyles.of(context).xsColored(
                            Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: spacing.md),
                        TpStepRail(
                          key: AppKeys.pairingStepRail,
                          items: buildPairingStageItems(
                            l10n: l10n,
                            statuses: state.stageStatuses,
                          ),
                        ),
                        SizedBox(height: spacing.md),
                        const ConnectionLogView(),
                      ],
                    ),
                  ),
                  _Footer(
                    connecting: connecting,
                    isError: isError,
                    error: state.error,
                    onConnect: cubit.confirmPairing,
                    onCancel: cubit.cancel,
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

class _HostCard extends StatelessWidget {
  const _HostCard({required this.state});

  final PairingClientState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final offer = state.pendingOffer;
    // Once a candidate wins, show the address that actually connected — the
    // offer's first entry is often a dead route the dial already skipped. While
    // still dialing there is no winner yet, so name the first candidate.
    final url =
        state.activeHostUrl ??
        (offer?.wsUrls.isNotEmpty ?? false ? offer!.wsUrls.first : null);
    final mono = appMonoTextStyle(
      context,
      fontSize: 12,
      color: cs.onSurfaceVariant,
    );

    return TpCard.outlined(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PairingHostGlyph(),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.activeHostName ?? l10n.pairingDesktopFallback,
                      style: styles.mdSemibold,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (url != null) ...[
                      SizedBox(height: spacing.xxs),
                      Text(
                        url,
                        style: mono,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // TTL only applies to a fresh QR offer; a reconnect uses a stored
          // device token that doesn't expire on a timer.
          if (offer != null) ...[
            SizedBox(height: spacing.md),
            Text(l10n.pairingCodeTtlHint, style: mono),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.connecting,
    required this.isError,
    required this.error,
    required this.onConnect,
    required this.onCancel,
  });

  final bool connecting;
  final bool isError;
  final String? error;
  final VoidCallback onConnect;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            spacing.md,
            spacing.lg,
            spacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isError)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 18, color: cs.error),
                    SizedBox(width: spacing.sm),
                    Expanded(
                      child: Text(
                        error ?? l10n.pairingFailed,
                        style: styles.smColored(cs.error),
                      ),
                    ),
                  ],
                )
              // While connecting the button already says so — repeating it here
              // would just be the same sentence twice.
              else if (!connecting)
                Text(l10n.pairingReadyHint, style: styles.mutedSm),
              if (!connecting) SizedBox(height: spacing.md),
              TpButton(
                key: AppKeys.pairingConnectButton,
                onPressed: connecting ? null : onConnect,
                child: connecting
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: spacing.sm),
                          Text(l10n.pairingConnecting),
                        ],
                      )
                    : Text(isError ? l10n.pairingRetry : l10n.pairingConnect),
              ),
              SizedBox(height: spacing.xs),
              TpButton(
                key: AppKeys.pairingConfirmCancelButton,
                variant: TpButtonVariant.ghost,
                onPressed: onCancel,
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
