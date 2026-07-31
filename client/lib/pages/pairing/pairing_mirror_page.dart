import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
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
  }

  @override
  void dispose() {
    _hostOutput?.cancel();
    _localInput?.cancel();
    _controller.dispose();
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
              _MirrorBar(
                hint: l10n.pairingMirrorInputHint,
                ctrlCTooltip: l10n.pairingSendCtrlC,
                onCtrlC: () => cubit.sendInput(const [0x03]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MirrorBar extends StatelessWidget {
  const _MirrorBar({
    required this.hint,
    required this.ctrlCTooltip,
    required this.onCtrlC,
  });

  final String hint;
  final String ctrlCTooltip;
  final VoidCallback onCtrlC;

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
          padding: EdgeInsets.symmetric(
            horizontal: spacing.lg,
            vertical: spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hint,
                  style: appMonoTextStyle(
                    context,
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: spacing.sm),
              // Interrupting a runaway process is the one control a phone
              // keyboard makes awkward, so it gets a dedicated key.
              TpIconButton(
                key: AppKeys.pairingMirrorCtrlCButton,
                icon: Icons.do_not_disturb_on_outlined,
                tooltip: ctrlCTooltip,
                size: 44,
                onTap: onCtrlC,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
