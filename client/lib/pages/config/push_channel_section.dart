import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/bark_push_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/bark_push_settings.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/ui/app_keys.dart';

/// Settings block for the Bark push channel: the one delivery path that still
/// works when no phone is connected to this desktop.
///
/// Lives next to the idle-notification switches because it is the same question
/// ("how do I hear that an agent needs me"), just a different transport.
class PushChannelSection extends StatefulWidget {
  const PushChannelSection({super.key});

  @override
  State<PushChannelSection> createState() => _PushChannelSectionState();
}

class _PushChannelSectionState extends State<PushChannelSection> {
  final _serverController = TextEditingController();
  final _keyController = TextEditingController();
  final _persist = Debouncer(
    tag: 'bark-push-persist',
    duration: const Duration(milliseconds: 600),
  );

  /// Last values pushed into the controllers from cubit state. Without this the
  /// debounced save round-trips through state and resets the caret mid-typing.
  String _syncedServer = '';
  String _syncedKey = '';
  var _seeded = false;

  /// True while [_sync] is writing into the controllers, which happens during
  /// build — the key listener must not call setState in that window.
  var _syncing = false;

  @override
  void initState() {
    super.initState();
    // The test button's enabled state reads the field, and the field's own save
    // is debounced — without this the button stays greyed out for 600ms after
    // the user finishes typing the key, which reads as "it didn't take".
    _keyController.addListener(_onKeyChanged);
  }

  void _onKeyChanged() {
    if (_syncing || !mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _keyController.removeListener(_onKeyChanged);
    _persist.dispose();
    _serverController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  /// Seeds the fields once the keychain read lands, and thereafter only when the
  /// value changed somewhere other than these fields.
  void _sync(BarkPushState state) {
    if (!state.loaded) return;
    _syncing = true;
    try {
      _syncFields(state);
    } finally {
      _syncing = false;
    }
  }

  void _syncFields(BarkPushState state) {
    if (!_seeded) {
      _seeded = true;
      _serverController.text = state.settings.serverUrl;
      _keyController.text = state.deviceKey;
      _syncedServer = state.settings.serverUrl;
      _syncedKey = state.deviceKey;
      return;
    }
    if (state.settings.serverUrl != _syncedServer) {
      _syncedServer = state.settings.serverUrl;
      if (_serverController.text != _syncedServer) {
        _serverController.text = _syncedServer;
      }
    }
    if (state.deviceKey != _syncedKey) {
      _syncedKey = state.deviceKey;
      if (_keyController.text != _syncedKey) {
        _keyController.text = _syncedKey;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<BarkPushCubit>();
    return BlocBuilder<BarkPushCubit, BarkPushState>(
      builder: (context, state) {
        _sync(state);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A stack, not a trailing control: "Only when no phone is
            // connected" does not fit a row's trailing slot at any realistic
            // settings-pane width, and an ellipsised mode is unreadable.
            TpPreferenceStack(
              title: l10n.barkPushModeTitle,
              subtitle: l10n.barkPushModeDescription,
              body: DropdownButton<BarkPushMode>(
                key: AppKeys.barkPushModeDropdown,
                value: state.settings.mode,
                isExpanded: true,
                onChanged: (mode) {
                  if (mode != null) unawaited(cubit.setMode(mode));
                },
                items: [
                  for (final mode in BarkPushMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(
                        _modeLabel(context, mode),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              showDividerBelow: true,
            ),
            TpPreferenceStack(
              title: l10n.barkPushServerTitle,
              subtitle: l10n.barkPushServerDescription,
              body: TextField(
                key: AppKeys.barkPushServerField,
                controller: _serverController,
                decoration: const InputDecoration(
                  hintText: BarkPushSettings.defaultServerUrl,
                  hintMaxLines: 1,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
                onChanged: (value) =>
                    _persist(() => unawaited(cubit.setServerUrl(value))),
                onSubmitted: (value) => unawaited(cubit.setServerUrl(value)),
              ),
              showDividerBelow: true,
            ),
            TpPreferenceStack(
              title: l10n.barkPushDeviceKeyTitle,
              subtitle: l10n.barkPushDeviceKeyDescription,
              body: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: AppKeys.barkPushDeviceKeyField,
                      controller: _keyController,
                      decoration: const InputDecoration(
                        hintMaxLines: 1,
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                      ),
                      onChanged: (value) =>
                          _persist(() => unawaited(cubit.setDeviceKey(value))),
                      onSubmitted: (value) =>
                          unawaited(cubit.setDeviceKey(value)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TpButton(
                    key: AppKeys.barkPushTestButton,
                    // Flush whatever is in the fields first: the debounce means
                    // a key typed and immediately tested would otherwise be
                    // sent as the previous one.
                    onPressed:
                        state.testing || _keyController.text.trim().isEmpty
                        ? null
                        : () async {
                            _persist.cancel();
                            await cubit.setServerUrl(_serverController.text);
                            await cubit.setDeviceKey(_keyController.text);
                            await cubit.sendTest();
                          },
                    child: state.testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.barkPushTest),
                  ),
                ],
              ),
              showDividerBelow: false,
            ),
            if (state.lastTest case final outcome?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _TestOutcomeLine(outcome: outcome),
              ),
          ],
        );
      },
    );
  }

  String _modeLabel(BuildContext context, BarkPushMode mode) => switch (mode) {
    BarkPushMode.off => context.l10n.barkPushModeOff,
    BarkPushMode.whenDisconnected => context.l10n.barkPushModeDisconnected,
    BarkPushMode.always => context.l10n.barkPushModeAlways,
  };
}

class _TestOutcomeLine extends StatelessWidget {
  const _TestOutcomeLine({required this.outcome});

  final BarkTestOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    // The server's own words follow the localized headline: a Bark failure is
    // almost always "failed to get device token: key invalid", which no string
    // of ours could say more usefully.
    final text = outcome.ok
        ? l10n.barkPushTestOk
        : '${l10n.barkPushTestFailed}: ${outcome.failure}';
    return Row(
      key: AppKeys.barkPushTestOutcome,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          outcome.ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 16,
          color: outcome.ok ? cs.primary : cs.error,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              color: outcome.ok ? cs.onSurfaceVariant : cs.error,
            ),
          ),
        ),
      ],
    );
  }
}
