import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/pane_mode.dart';
import '../../repositories/pairing_settings_repository.dart';
import '../../services/pairing/host_settings_client.dart';
import '../../services/pairing/pairing_client.dart';
import '../../utils/ui/app_keys.dart';
import 'pairing_nav_bar.dart';

/// Edits the pane defaults of a paired desktop: what a window it creates next
/// is (a shell, or a conversation) and the command a conversation window runs.
///
/// These are *host* settings — they live on the desktop and decide what the
/// desktop does — so this page dials it for the duration of the edit instead of
/// reading local preferences. That is also why the mirror flow is untouched:
/// no mirror is open while you are in settings.
class HostPaneDefaultsPage extends StatefulWidget {
  const HostPaneDefaultsPage({
    super.key,
    required this.desktop,
    this.client = const HostSettingsClient(),
  });

  final PairedDesktop desktop;
  final HostSettingsClient client;

  static Route<void> route(
    PairedDesktop desktop, {
    HostSettingsClient client = const HostSettingsClient(),
  }) => MaterialPageRoute(
    builder: (_) => HostPaneDefaultsPage(desktop: desktop, client: client),
  );

  @override
  State<HostPaneDefaultsPage> createState() => _HostPaneDefaultsPageState();
}

class _HostPaneDefaultsPageState extends State<HostPaneDefaultsPage> {
  PairingPaneDefaults? _defaults;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final defaults = await widget.client.readPaneDefaults(widget.desktop);
      if (!mounted) return;
      setState(() {
        _defaults = defaults;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _busy = false;
      });
    }
  }

  /// Writes one change and adopts whatever the host reports back: an empty
  /// command comes home as the host's own default, not as the empty box.
  Future<void> _save({PaneMode? mode, String? chatAgentCommand}) async {
    final current = _defaults;
    if (current == null) return;
    final nextMode = mode ?? current.mode;
    final nextCommand = chatAgentCommand ?? current.chatAgentCommand;
    // Room to type or switch again while the write is in flight; the host's
    // answer (below) is what the page finally shows.
    setState(
      () => _defaults = PairingPaneDefaults(
        mode: nextMode,
        chatAgentCommand: nextCommand,
      ),
    );
    try {
      final applied = await widget.client.writePaneDefaults(
        widget.desktop,
        mode: nextMode,
        chatAgentCommand: nextCommand,
      );
      if (!mounted) return;
      setState(() {
        _defaults = applied;
        _error = null;
      });
      _toast(context.l10n.hostPaneDefaultsSaved);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
      _toast(context.l10n.hostPaneDefaultsFailed);
      await _load();
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;
    return Scaffold(
      key: AppKeys.hostPaneDefaultsPage,
      body: SafeArea(
        child: Column(
          children: [
            PairingNavBar.large(
              title: l10n.hostPaneDefaultsTitle,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(child: _buildBody(context, spacing)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, TpSpacing spacing) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    if (_busy) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            SizedBox(height: spacing.md),
            Text(l10n.hostSettingsConnecting),
          ],
        ),
      );
    }
    final error = _error;
    final defaults = _defaults;
    if (defaults == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.hostSettingsUnreachable,
                textAlign: TextAlign.center,
                style: TpTextStyles.of(context).smColored(cs.error),
              ),
              if (error != null) ...[
                SizedBox(height: spacing.sm),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
                ),
              ],
              SizedBox(height: spacing.md),
              TpButton(
                variant: TpButtonVariant.secondary,
                onPressed: _load,
                child: Text(l10n.pairingRetry),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.all(spacing.lg),
      children: [
        _hostHeader(context),
        SizedBox(height: spacing.md),
        TpCard.outlined(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpPreferenceRow(
                title: l10n.newPaneModeTitle,
                subtitle: l10n.hostPaneDefaultsModeDescription,
                trailing: TpSegmentedControl(
                  key: ValueKey('host-pane-mode-${defaults.mode.name}'),
                  labels: [l10n.newPaneModeTerminal, l10n.newPaneModeChat],
                  totalSwitches: 2,
                  initialLabelIndex: defaults.mode == PaneMode.chat ? 1 : 0,
                  minHeight: 36,
                  onToggle: (index) => _save(
                    mode: index == 1 ? PaneMode.chat : PaneMode.terminal,
                  ),
                ),
                showDividerBelow: true,
              ),
              TpPreferenceRow(
                title: l10n.chatAgentCommandTitle,
                subtitle: l10n.hostPaneDefaultsCommandDescription,
                trailing: SizedBox(
                  width: 148,
                  child: _HostCommandField(
                    value: defaults.chatAgentCommand,
                    onCommit: (value) => _save(chatAgentCommand: value),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.md),
        Text(
          l10n.hostPaneDefaultsFootnote,
          style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _hostHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.desktop_windows_outlined, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${widget.desktop.name} · ${widget.desktop.displayUrl}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TpTextStyles.of(context).smColored(cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// The command box. Saves on submit and on blur, and only follows the stored
/// value while the field is not focused — otherwise a host round-trip would
/// rewrite what the user is still typing.
class _HostCommandField extends StatefulWidget {
  const _HostCommandField({required this.value, required this.onCommit});

  final String value;
  final Future<void> Function(String) onCommit;

  @override
  State<_HostCommandField> createState() => _HostCommandFieldState();
}

class _HostCommandFieldState extends State<_HostCommandField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_HostCommandField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus &&
        widget.value != oldWidget.value &&
        widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  void _onFocusChange() {
    if (_focus.hasFocus) return;
    if (_controller.text == widget.value) return;
    widget.onCommit(_controller.text);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: AppKeys.hostPaneDefaultsCommandField,
      controller: _controller,
      focusNode: _focus,
      textAlign: TextAlign.end,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (value) {
        if (value != widget.value) widget.onCommit(value);
      },
      decoration: const InputDecoration(
        isDense: true,
        border: UnderlineInputBorder(),
      ),
    );
  }
}
