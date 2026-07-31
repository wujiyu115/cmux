import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../utils/ui/app_keys.dart';

/// Live, interactive mirror of a desktop session (orca `h/[hostId]/session`).
///
/// A fresh [TerminalEngine] renders the host's snapshot-then-live PTY bytes;
/// the view is **not** read-only, so keystrokes flow back to the desktop PTY as
/// input frames and viewport changes (rotation / soft keyboard) send resize
/// frames. Mirror-only: this phone never spawns a local PTY.
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
    final cubit = context.read<PairingClientCubit>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cubit.leaveMirror();
      },
      child: Scaffold(
        key: AppKeys.pairingMirrorPage,
        appBar: AppBar(
          title: ValueListenableBuilder<String>(
            valueListenable: _engine.title,
            builder: (context, title, _) => Text(title),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: cubit.leaveMirror,
          ),
        ),
        body: SafeArea(
          child: TerminalView(
            _engine,
            controller: _controller,
            autofocus: true,
            padding: const EdgeInsets.all(4),
            onPtyResize: (columns, rows) => cubit.sendResize(columns, rows),
          ),
        ),
      ),
    );
  }
}
