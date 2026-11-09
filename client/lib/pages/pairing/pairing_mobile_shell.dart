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
import '../../services/app/ios_background_grace_service.dart';
import '../../services/pairing/pairing_offer.dart';
import '../../services/stt/stt_provider_factory.dart';
import '../../utils/logging/logger.dart';
import '../../widgets/app_toast/app_toast.dart';
import 'paired_hosts_page.dart';
import 'pairing_confirm_page.dart';
import 'pairing_mirror_page.dart';
import 'pairing_scan_page.dart';
import 'pairing_session_list_page.dart';
import 'pairing_tablet_layout.dart';
import 'pairing_tablet_shell.dart';

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
  final IosBackgroundGraceService _backgroundGrace =
      IosBackgroundGraceService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinks();
  }

  /// The LAN socket does not survive the OS freezing this process, and nothing
  /// wakes us to notice: the drop is only observable once we are back. So retry
  /// on resume instead of waiting out the backoff the user cannot see. iOS also
  /// gets a ~30s background-task assertion while a connection is live, which
  /// keeps the freeze — and the disconnect — off short switches away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_backgroundGrace.end());
      if (!mounted) return;
      context.read<PairingClientCubit>().onAppResumed();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _beginBackgroundGraceIfConnected();
    }
  }

  void _beginBackgroundGraceIfConnected() {
    if (!mounted) return;
    final phase = context.read<PairingClientCubit>().state.phase;
    final hasLiveConnection =
        phase == PairingClientPhase.connected ||
        phase == PairingClientPhase.mirroring;
    if (hasLiveConnection) unawaited(_backgroundGrace.begin());
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
        builder: (_) =>
            BlocProvider.value(value: cubit, child: const PairingScanPage()),
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
          builder: (context, state) => PairingBackLadder(
            state: state,
            child: _buildPhase(context, state),
          ),
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
      PairingNotice.fallbackOpenedTerminal =>
        l10n.pairingFallbackOpenedTerminal,
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

  /// The breakpoint the shell last rendered, **pinned for the lifetime of an
  /// open mirror** (see [_useTwoPane]).
  bool? _twoPane;

  /// Whether to render the two-pane tablet shell, decided from the window size
  /// but pinned while a mirror is open.
  ///
  /// Crossing the breakpoint with a mirror live (a split-screen divider dragged
  /// across 600pt on either platform) moves [PairingMirrorPage] to a different place in the tree, which
  /// rebuilds it with a fresh [TerminalEngine]. The engine has no scrollback of
  /// its own: it is fed the host's snapshot on `terminal.subscribe`, and the
  /// subscription's broadcast stream does not replay that snapshot to a second
  /// listener — so a re-parented mirror comes up blank until the program next
  /// writes. Pinning the layout until the mirror is closed keeps the engine, the
  /// scrollback and the composer draft alive; the next open uses the new size.
  bool _useTwoPane(PairingClientState state) {
    final tablet = PairingTabletLayout.isTablet(context);
    if (state.phase != PairingClientPhase.mirroring) return _twoPane = tablet;
    return _twoPane ??= tablet;
  }

  Widget _buildPhase(BuildContext context, PairingClientState state) {
    // Tablet (iPad / Android large screen): the list survives opening a terminal, so `connected` and
    // `mirroring` are the same two-pane shell with a different right pane. The
    // `MediaQuery` read here is what makes a rotated / resized iPad reflow
    // instead of leaving the phone stack stretched to 1366pt.
    final twoPane =
        state.phase == PairingClientPhase.connected ||
        state.phase == PairingClientPhase.mirroring;
    if (twoPane && _useTwoPane(state)) {
      return PairingTabletShell(state: state);
    }
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

/// Android hardware back for the connected half of the pairing flow.
///
/// The ladder the on-screen arrows already walk is mirror -> session list ->
/// hosts. Two of those three steps are claimed by a pane's own [PopScope]
/// ([PairingMirrorPage] closes the mirror, [PairingConfirmPage] cancels the
/// pending offer); the session list has no [PopScope] of its own, so before this
/// wrapper the back gesture fell through to the router and backgrounded the app
/// while the screen's own back arrow left the desktop. That mismatch is what
/// this widget removes — the hardware gesture now walks the same ladder, one
/// step per press.
///
/// Every phase still leaves [PopScope.canPop] at the pane's value: a pane that
/// says `canPop: false` wins the route's disposition regardless of this widget,
/// so a mirror-backed pane is never popped by a parent claiming the pop first.
class PairingBackLadder extends StatelessWidget {
  const PairingBackLadder({
    super.key,
    required this.state,
    required this.child,
  });

  final PairingClientState state;
  final Widget child;

  /// The phase nothing else handles: connected, nothing mirrored. `idle` (the
  /// paired-hosts root) intentionally keeps popping, which is how Android exits
  /// the app from its home surface.
  bool get _claimsBack => state.phase == PairingClientPhase.connected;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_claimsBack,
      onPopInvokedWithResult: (didPop, _) {
        // A pane deeper in the tree already claimed this press (mirror /
        // confirm): it has reacted, so reacting again would drop two levels at
        // once.
        if (didPop || !_claimsBack) return;
        unawaited(context.read<PairingClientCubit>().cancel());
      },
      child: child,
    );
  }
}
