import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../cubits/mobile_toolbar_cubit.dart';
import '../../cubits/pairing_client_cubit.dart';
import '../../repositories/mobile_toolbar_repository.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import 'mobile_toolbar/mobile_composer_panel.dart';
import 'mobile_toolbar/mobile_keyboard_toolbar.dart';
import 'pairing_nav_bar.dart';

/// Live, interactive mirror of a desktop session.
///
/// A fresh [TerminalEngine] renders the host's snapshot-then-live PTY bytes; the
/// view is **not** read-only, so keystrokes flow back to the desktop PTY as input
/// frames and viewport changes (rotation / soft keyboard) send resize frames.
/// Mirror-only: this phone never spawns a local PTY.
class PairingMirrorPage extends StatefulWidget {
  const PairingMirrorPage({super.key});

  @override
  State<PairingMirrorPage> createState() => _PairingMirrorPageState();
}

class _PairingMirrorPageState extends State<PairingMirrorPage> {
  late final TerminalEngine _engine;
  late final TerminalController _controller;
  late final MobileToolbarCubit _toolbar;

  /// The composer's draft outlives the panel: flipping to the key bar unmounts
  /// the panel, and the half-typed command has to still be there on the way
  /// back. It dies with the page, which is why it is not persisted.
  final _composerText = TextEditingController();
  final _composerFocus = FocusNode();
  StreamSubscription<Uint8List>? _hostOutput;
  StreamSubscription<Uint8List>? _localInput;

  /// Last geometry the host acknowledged, shown in the nav bar so a mismatched
  /// mirror (phone rotated, desktop resized) is visible rather than mysterious.
  ({int cols, int rows})? _geometry;

  @override
  void initState() {
    super.initState();
    _engine = TerminalEngine(config: TerminalConfig.defaults());
    _controller = TerminalController();

    final cubit = context.read<PairingClientCubit>();
    // Host → engine: snapshot then live bytes, already ordered by the host.
    final sub = cubit.activeSubscription;
    _hostOutput = sub?.output.listen(_engine.feed);
    // Engine → host: keystrokes / paste / mouse reports become input frames.
    _localInput = _engine.output.listen(cubit.sendInput);

    // Toolbar keys bypass the engine and go straight out as input frames, so
    // they work whether or not the terminal holds focus.
    _toolbar = MobileToolbarCubit(
      repository: SharedPrefsMobileToolbarRepository(
        context.read<SharedPreferences>(),
      ),
      sendInput: cubit.sendInput,
    );
    _toolbar.load();
  }

  @override
  void dispose() {
    _hostOutput?.cancel();
    _localInput?.cancel();
    _controller.dispose();
    _engine.dispose();
    _composerText.dispose();
    _composerFocus.dispose();
    _toolbar.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<PairingClientCubit>();
    final geometry = _geometry;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cubit.leaveMirror();
      },
      child: Scaffold(
        key: AppKeys.pairingMirrorPage,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              ValueListenableBuilder<String>(
                valueListenable: _engine.title,
                builder: (context, title, _) => PairingNavBar(
                  title: title,
                  onBack: cubit.leaveMirror,
                  trailing: geometry == null
                      ? null
                      : Text(
                          '${geometry.cols}×${geometry.rows}',
                          textAlign: TextAlign.right,
                          style: appMonoTextStyle(
                            context,
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              Expanded(
                child: TerminalView(
                  _engine,
                  controller: _controller,
                  autofocus: true,
                  padding: const EdgeInsets.all(4),
                  onPtyResize: (columns, rows) {
                    cubit.sendResize(columns, rows);
                    if (geometry?.cols == columns && geometry?.rows == rows) {
                      return;
                    }
                    setState(() => _geometry = (cols: columns, rows: rows));
                  },
                ),
              ),
              BlocProvider.value(
                value: _toolbar,
                child: BlocBuilder<MobileToolbarCubit, MobileToolbarState>(
                  // The state re-emits on every key tap; only the mode decides
                  // which panel is mounted.
                  buildWhen: (before, after) => before.mode != after.mode,
                  builder: (context, state) => switch (state.mode) {
                    MobileInputMode.keys => const MobileKeyboardToolbar(),
                    MobileInputMode.composer => MobileComposerPanel(
                      controller: _composerText,
                      focusNode: _composerFocus,
                    ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
