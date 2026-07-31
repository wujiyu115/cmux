import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_offer.dart';
import '../../utils/logging/logger.dart';
import 'paired_hosts_page.dart';
import 'pairing_confirm_page.dart';
import 'pairing_mirror_page.dart';
import 'pairing_scan_page.dart';
import 'pairing_session_list_page.dart';

/// Mobile app root: a slim, self-contained shell that swaps between the pairing
/// screens by [PairingClientPhase]. Replaces the desktop workspace shell on
/// Android / iOS — mobile is a pure LAN mirror/control client, no local PTY,
/// no SSH thin-client.
///
/// Also owns the `teampilot://pair?code=…` deep link: an incoming link (cold
/// start or while running) parses to a [PairingOffer] and jumps straight to the
/// confirm screen, matching orca's `pair.tsx` redirect.
class PairingMobileShell extends StatefulWidget {
  const PairingMobileShell({super.key});

  @override
  State<PairingMobileShell> createState() => _PairingMobileShellState();
}

class _PairingMobileShellState extends State<PairingMobileShell> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleLink(initial);
    } on Object catch (e) {
      appLogger.d('pairing deep link (initial) failed: $e');
    }
    _linkSub = _appLinks.uriLinkStream.listen(
      _handleLink,
      onError: (Object e) => appLogger.d('pairing deep link stream error: $e'),
    );
  }

  void _handleLink(Uri uri) {
    final offer = PairingOffer.tryParse(uri.toString());
    if (offer == null || !mounted) return;
    context.read<PairingClientCubit>().beginPairing(offer);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _openScanner(BuildContext context) async {
    final cubit = context.read<PairingClientCubit>();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: cubit,
          child: const PairingScanPage(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PairingClientCubit, PairingClientState>(
      listenWhen: (a, b) => a.notice != b.notice && b.notice != null,
      listener: _showNotice,
      child: BlocBuilder<PairingClientCubit, PairingClientState>(
        buildWhen: (a, b) =>
            a.phase != b.phase || a.activeCatalogId != b.activeCatalogId,
        builder: _buildPhase,
      ),
    );
  }

  void _showNotice(BuildContext context, PairingClientState state) {
    final notice = state.notice;
    if (notice == null) return;
    final l10n = context.l10n;
    final message = switch (notice) {
      PairingNotice.activateFailed => l10n.pairingActivateFailed,
      PairingNotice.fallbackOpenedTerminal => l10n.pairingFallbackOpenedTerminal,
    };
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
    context.read<PairingClientCubit>().clearNotice();
  }

  Widget _buildPhase(BuildContext context, PairingClientState state) {
    switch (state.phase) {
          case PairingClientPhase.idle:
            return PairedHostsPage(onScan: () => _openScanner(context));
          case PairingClientPhase.confirmAwaiting:
          case PairingClientPhase.confirmConnecting:
          case PairingClientPhase.error:
            return const PairingConfirmPage();
          case PairingClientPhase.connected:
            return const PairingSessionListPage();
          case PairingClientPhase.mirroring:
            // Key on the session so a new mirror gets a fresh engine.
            return PairingMirrorPage(
              key: ValueKey('mirror-${state.activeCatalogId}'),
            );
    }
  }
}
