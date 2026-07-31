import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/terminal/terminal_mirror_takeover.dart';
import '../../services/terminal/terminal_session.dart';

/// Wraps a desktop terminal pane so it yields the grid while a phone mirrors it.
///
/// Listens to [TerminalSession.mirrorTakeover]. While a phone is attached:
/// - the pane's [TerminalView] is built [readOnly] (input is refused);
/// - the pane stops pushing SIGWINCH via [TerminalViewState.beginPtyHold], so
///   the desktop and phone never fight over the shared PTY's size;
/// - an opaque banner covers the pane — the desktop engine still renders at its
///   own container size (out of step with the phone-driven PTY), so hiding it
///   avoids showing garbled reflowed output.
///
/// When the last phone disconnects the takeover clears and
/// [TerminalViewState.endPtyHold] flushes one SIGWINCH at the desktop's current
/// grid, so the TUI redraws at the desktop size on its own.
class TerminalMirrorTakeoverScope extends StatefulWidget {
  const TerminalMirrorTakeoverScope({
    required this.session,
    required this.terminalViewKey,
    required this.builder,
    super.key,
  });

  final TerminalSession session;
  final GlobalKey<TerminalViewState> terminalViewKey;

  /// Builds the pane; [readOnly] must be threaded to the [TerminalView].
  final Widget Function(bool readOnly) builder;

  @override
  State<TerminalMirrorTakeoverScope> createState() =>
      _TerminalMirrorTakeoverScopeState();
}

class _TerminalMirrorTakeoverScopeState
    extends State<TerminalMirrorTakeoverScope> {
  TerminalMirrorTakeover? _takeover;
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _takeover = widget.session.mirrorTakeover.value;
    widget.session.mirrorTakeover.addListener(_onTakeover);
    if (_takeover != null) _acquireHold();
  }

  @override
  void didUpdateWidget(TerminalMirrorTakeoverScope old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      old.session.mirrorTakeover.removeListener(_onTakeover);
      _releaseHold(flush: false);
      _takeover = widget.session.mirrorTakeover.value;
      widget.session.mirrorTakeover.addListener(_onTakeover);
      if (_takeover != null) _acquireHold();
    }
  }

  void _onTakeover() {
    final next = widget.session.mirrorTakeover.value;
    final wasActive = _takeover != null;
    final isActive = next != null;
    if (wasActive && !isActive) {
      _releaseHold(flush: true);
    } else if (!wasActive && isActive) {
      _acquireHold();
    }
    setState(() => _takeover = next);
  }

  void _acquireHold() {
    if (_held) return;
    // The view may not be mounted on the very first frame; hold once it is.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _takeover == null || _held) return;
      widget.terminalViewKey.currentState?.beginPtyHold();
      _held = true;
    });
  }

  void _releaseHold({required bool flush}) {
    if (!_held) return;
    _held = false;
    widget.terminalViewKey.currentState?.endPtyHold(flush: flush);
  }

  @override
  void dispose() {
    widget.session.mirrorTakeover.removeListener(_onTakeover);
    // Pane is going away — no point flushing a SIGWINCH at a dead view.
    _releaseHold(flush: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final takeover = _takeover;
    final pane = widget.builder(takeover != null);
    if (takeover == null) return pane;
    return Stack(
      children: [
        pane,
        Positioned.fill(child: _TakeoverBanner(takeover: takeover)),
      ],
    );
  }
}

class _TakeoverBanner extends StatelessWidget {
  const _TakeoverBanner({required this.takeover});

  final TerminalMirrorTakeover takeover;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    return ColoredBox(
      color: cs.surface,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.phonelink, size: 32, color: cs.primary),
              SizedBox(height: spacing.md),
              Text(
                l10n.terminalMirrorTakeoverTitle,
                textAlign: TextAlign.center,
                style: styles.mdMediumColored(cs.onSurface),
              ),
              SizedBox(height: spacing.xs),
              Text(
                l10n.terminalMirrorTakeoverHint(takeover.cols, takeover.rows),
                textAlign: TextAlign.center,
                style: styles.smColored(cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
