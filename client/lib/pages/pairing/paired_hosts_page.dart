import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../repositories/pairing_settings_repository.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import 'paired_host_row.dart';
import 'pairing_network_strip.dart';

/// Mobile home: the desktops this phone has paired with.
///
/// The scan CTA is pinned to the bottom in both the empty and populated states —
/// it is the only action on this screen, so it stays in one place instead of
/// migrating between an empty-state button and a floating one.
class PairedHostsPage extends StatelessWidget {
  const PairedHostsPage({required this.onScan, super.key});

  /// Opens the QR scanner (host injects navigation; keeps this page routing-free).
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PairingClientCubit, PairingClientState>(
      buildWhen: (a, b) =>
          a.pairedDesktops != b.pairedDesktops || a.localIp != b.localIp,
      builder: (context, state) {
        final l10n = context.l10n;
        final cs = Theme.of(context).colorScheme;
        final spacing = context.tpSpacing;
        final desktops = state.pairedDesktops;
        return Scaffold(
          key: AppKeys.pairedHostsPage,
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(count: desktops.length),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                  child: PairingNetworkStrip(localIp: state.localIp),
                ),
                Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                Expanded(
                  child: desktops.isEmpty
                      ? TpEmptyState(
                          icon: Icons.qr_code_2,
                          title: l10n.pairingNoPairedDesktops,
                          hint: l10n.pairingEmptyHint,
                          centered: true,
                        )
                      : _HostList(desktops: desktops),
                ),
                _Footer(onScan: onScan),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.lg, spacing.md, spacing.lg, spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              context.l10n.pairingDesktops,
              style: TpTextStyles.of(context).lgSemibold,
            ),
          ),
          Text(
            '$count',
            style: appMonoTextStyle(
              context,
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HostList extends StatelessWidget {
  const _HostList({required this.desktops});

  final List<PairedDesktop> desktops;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PairingClientCubit>();
    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: context.tpSpacing.lg),
      itemCount: desktops.length,
      separatorBuilder: (_, __) => const TpSeparator(),
      itemBuilder: (context, i) {
        final desktop = desktops[i];
        return PairedHostRow(
          desktop: desktop,
          onTap: () => cubit.connectToDesktop(desktop),
          onRemove: () => _removeWithUndo(context, cubit, desktop),
        );
      },
    );
  }

  /// Removing a pinned host key means re-scanning the desktop's QR to get it
  /// back, so the delete is always paired with an undo affordance.
  void _removeWithUndo(
    BuildContext context,
    PairingClientCubit cubit,
    PairedDesktop desktop,
  ) {
    final l10n = context.l10n;
    cubit.removeDesktop(desktop.id);
    AppToast.show(
      context,
      message: l10n.pairingRemovedUndo(desktop.name),
      duration: const Duration(milliseconds: 4200),
      action: TpToastAction(
        label: l10n.pairingUndo,
        onPressed: () => cubit.restoreDesktop(desktop),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
          child: TpButton(
            key: AppKeys.pairingScanCtaButton,
            onPressed: onScan,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.qr_code_scanner, size: 19),
                SizedBox(width: spacing.sm),
                Text(context.l10n.pairingScanToPair),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
