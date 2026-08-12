import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../cubits/voice_input_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/voice_input_repository.dart';
import '../../services/pairing/pairing_offer.dart';
import '../../services/stt/stt_provider_factory.dart';
import '../../utils/logging/logger.dart';
import '../../widgets/app_toast/app_toast.dart';
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

class _PairingMobileShellState extends State<PairingMobileShell>
    with WidgetsBindingObserver {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinks();
  }

  /// The LAN socket does not survive the OS freezing this process, and nothing
  /// wakes us to notice: the drop is only observable once we are back. So retry
  /// on resume instead of waiting out the backoff the user cannot see.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || !mounted) return;
    context.read<PairingClientCubit>().onAppResumed();
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
    WidgetsBinding.instance.removeObserver(this);
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
    // Voice-input settings are a cross-screen preference: the mirror page is
    // rebuilt on every entry and would throw away the probed availability and
    // loaded credentials, and Task 10's settings entry lives on the home
    // screen where a mirror-owned cubit is out of scope. BlocProvider closes it.
    return BlocProvider<VoiceInputCubit>(
      create: (context) => VoiceInputCubit(
        repository: DefaultVoiceInputRepository(
          preferences: context.read<SharedPreferences>(),
          secureStore: const FlutterSecureKeyValueStore(),
        ),
        providerFactory: buildSttProvider,
      )..load(),
      child: BlocListener<PairingClientCubit, PairingClientState>(
        listenWhen: (a, b) => a.notice != b.notice && b.notice != null,
        listener: _showNotice,
        child: BlocBuilder<PairingClientCubit, PairingClientState>(
          buildWhen: (a, b) =>
              a.phase != b.phase ||
              a.activeCatalogId != b.activeCatalogId ||
              a.connectGeneration != b.connectGeneration,
          builder: _buildPhase,
        ),
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
      PairingNotice.connectionLost => l10n.pairingConnectionLost,
      PairingNotice.reconnected => l10n.pairingReconnected,
    };
    AppToast.show(
      context,
      message: message,
      variant: notice == PairingNotice.reconnected
          ? TpToastVariant.success
          : TpToastVariant.warning,
    );
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
            // Key on the session so a new mirror gets a fresh engine, and on the
            // connection generation so a reconnect rebinds to the *new*
            // subscription — the catalogId alone is unchanged across a drop.
            return PairingMirrorPage(
              key: ValueKey(
                'mirror-${state.activeCatalogId}-${state.connectGeneration}',
              ),
            );
    }
  }
}
