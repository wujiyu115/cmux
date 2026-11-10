import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../repositories/pairing_settings_repository.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import 'mobile_chrome.dart';
import 'mobile_settings_page.dart';
import 'paired_host_row.dart';
import 'pairing_network_strip.dart';
import 'pairing_tablet_layout.dart';

/// Mobile home: the desktops this phone has paired with, laid out as the
/// Orca-style activity feed — a large page title, one section, and a rounded
/// card per section whose last row is the add action. Settings is the second
/// destination in the nav rather than a header glyph.
///
/// Tablet (iPad / Android large screen): the nav moves from the bottom bar to a
/// leading rail and the feed caps itself at a readable width — six inches of
/// empty row is not a layout, and a two-item bar under a 1024pt page reads as a
/// phone stretched sideways.
///
/// The add affordance exists twice on purpose: the floating "+" is the
/// thumb-reachable action, and the in-card row is discoverable while reading the
/// list. Both open the QR scanner.
class PairedHostsPage extends StatefulWidget {
  const PairedHostsPage({required this.onScan, super.key});

  /// Opens the QR scanner (host injects navigation; keeps this page routing-free).
  final VoidCallback onScan;

  @override
  State<PairedHostsPage> createState() => _PairedHostsPageState();
}

class _PairedHostsPageState extends State<PairedHostsPage> {
  MobileTab _tab = MobileTab.activity;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PairingClientCubit, PairingClientState>(
      buildWhen: (a, b) =>
          a.pairedDesktops != b.pairedDesktops || a.localIp != b.localIp,
      builder: (context, state) {
        // Built lazily: the settings tab needs cubits (layout / voice) that the
        // activity feed does not, and an IndexedStack would force them on every
        // home build.
        final body = _tab == MobileTab.activity
            ? _ActivityFeed(
                desktops: state.pairedDesktops,
                localIp: state.localIp,
                onScan: widget.onScan,
              )
            : const MobileSettingsPage(embedded: true);
        return Scaffold(
          key: AppKeys.pairedHostsPage,
          // Tablet (iPad / Android): the destinations move to a leading rail and
          // the feed is capped and centred rather than crossing 1366pt. On a
          // phone this is the bottom bar and the full window, unchanged.
          body: SafeArea(
            bottom: false,
            child: PairingTabletLayout.isTablet(context)
                ? Row(
                    children: [
                      MobileNavRail(
                        current: _tab,
                        onSelected: (tab) => setState(() => _tab = tab),
                      ),
                      Expanded(
                        child: PairingTabletReadableContent(child: body),
                      ),
                    ],
                  )
                : PairingTabletReadableContent(child: body),
          ),
          floatingActionButton: _tab == MobileTab.activity
              ? FloatingActionButton(
                  key: AppKeys.mobileAddDesktopButton,
                  onPressed: widget.onScan,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  elevation: 0,
                  highlightElevation: 0,
                  shape: const CircleBorder(),
                  child: const Icon(Icons.add, size: 28),
                )
              : null,
          bottomNavigationBar: PairingTabletLayout.isTablet(context)
              ? null
              : MobileBottomNav(
                  current: _tab,
                  onSelected: (tab) => setState(() => _tab = tab),
                ),
        );
      },
    );
  }
}

class _ActivityFeed extends StatelessWidget {
  const _ActivityFeed({
    required this.desktops,
    required this.localIp,
    required this.onScan,
  });

  final List<PairedDesktop> desktops;
  final String? localIp;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
      children: [
        Text(
          l10n.mobileTabActivity,
          // Reference page title: 30 / 700, tight tracking.
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          l10n.pairingDesktops,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        _DesktopCard(
          desktops: desktops,
          onScan: onScan,
          cubit: context.read<PairingClientCubit>(),
        ),
        if (localIp != null && localIp!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: PairingNetworkStrip(localIp: localIp),
          ),
        ],
      ],
    );
  }
}

class _DesktopCard extends StatelessWidget {
  const _DesktopCard({
    required this.desktops,
    required this.onScan,
    required this.cubit,
  });

  final List<PairedDesktop> desktops;
  final VoidCallback onScan;
  final PairingClientCubit cubit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hairline = mobileHairlineColor(context);
    return Material(
      color: mobileCardColor(context),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (desktops.isEmpty)
            const _EmptyIntro()
          else
            for (var i = 0; i < desktops.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: hairline),
              PairedHostRow(
                desktop: desktops[i],
                onTap: () => cubit.connectToDesktop(desktops[i]),
                onRemove: () => _removeWithUndo(context, desktops[i]),
              ),
            ],
          Divider(height: 1, thickness: 1, color: hairline),
          MobileCardActionRow(
            key: AppKeys.pairingScanCtaButton,
            icon: Icons.add,
            label: context.l10n.pairingPairDesktop,
            onTap: onScan,
            foreground: cs.primary,
          ),
        ],
      ),
    );
  }

  /// Removing a pinned host key means re-scanning the desktop's QR to get it
  /// back, so the delete is always paired with an undo affordance.
  void _removeWithUndo(BuildContext context, PairedDesktop desktop) {
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

class _EmptyIntro extends StatelessWidget {
  const _EmptyIntro();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_2, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.pairingNoPairedDesktops,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pairingEmptyHint,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
