import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/voice_input_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../repositories/voice_input_repository.dart';
import '../../../services/stt/stt_provider.dart';
import '../../../utils/debounce/debounces.dart';
import '../../../utils/logging/logger_utils.dart';
import '../../../utils/ui/app_keys.dart';

/// The cloud-only part of the voice settings page: the credential fields for
/// the chosen backend, a connection test, and the privacy note.
///
/// Split out from the page shell because it only exists for a cloud backend and
/// carries its own stateful field controllers.
class VoiceCredentialsSection extends StatelessWidget {
  const VoiceCredentialsSection({super.key, required this.provider});

  final SttProviderType provider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            spacing.lg,
            spacing.lg,
            spacing.sm,
          ),
          child: Text(l10n.voiceInputCredentials, style: styles.mdMedium),
        ),
        for (final field in _fieldsFor(provider))
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.xs,
              spacing.lg,
              spacing.xs,
            ),
            // Keyed by the field enum so flipping the provider radio builds a
            // fresh state with the correct seed, rather than reusing the prior
            // provider's `_CredentialFieldState` by position and persisting its
            // stale text under this field's keychain slot.
            child: _CredentialField(key: ValueKey(field), field: field),
          ),
        const _TestConnectionTile(),
        // The pairing channel is end-to-end encrypted, but voice audio goes
        // straight from the phone to the cloud provider and never traverses it.
        // Only on-device recognition sends nothing, so this note renders only
        // for a cloud backend (this widget is not built for `system`).
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            spacing.sm,
            spacing.lg,
            spacing.lg,
          ),
          child: Text(
            l10n.voiceInputCloudPrivacyNote,
            style: styles.sm.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// The credential fields each backend needs, in the order they are shown.
List<VoiceCredentialField> _fieldsFor(SttProviderType provider) =>
    switch (provider) {
      SttProviderType.system => const [],
      SttProviderType.volcengine => const [
        VoiceCredentialField.volcAppId,
        VoiceCredentialField.volcAccessToken,
      ],
      SttProviderType.aliyun => const [
        VoiceCredentialField.aliyunAccessKeyId,
        VoiceCredentialField.aliyunAccessKeySecret,
        VoiceCredentialField.aliyunAppKey,
      ],
    };

String _fieldLabel(AppLocalizations l10n, VoiceCredentialField field) =>
    switch (field) {
      VoiceCredentialField.volcAppId => l10n.voiceInputVolcAppId,
      VoiceCredentialField.volcAccessToken => l10n.voiceInputVolcAccessToken,
      VoiceCredentialField.aliyunAccessKeyId => l10n.voiceInputAliyunAccessKeyId,
      VoiceCredentialField.aliyunAccessKeySecret =>
        l10n.voiceInputAliyunAccessKeySecret,
      VoiceCredentialField.aliyunAppKey => l10n.voiceInputAliyunAppKey,
    };

/// A single credential input. Seeds its controller from current state, persists
/// through a debounce on change and immediately on submit — the established
/// form idiom in `session_config_section.dart`.
class _CredentialField extends StatefulWidget {
  const _CredentialField({super.key, required this.field});

  final VoiceCredentialField field;

  @override
  State<_CredentialField> createState() => _CredentialFieldState();
}

class _CredentialFieldState extends State<_CredentialField> {
  late final TextEditingController _controller;
  late final Debouncer _debouncer;

  /// Only the secrets are hidden. The identifiers stay readable so a user can
  /// check what they pasted; an access token read over a shoulder is a billable
  /// credential.
  bool get _obscure =>
      widget.field == VoiceCredentialField.volcAccessToken ||
      widget.field == VoiceCredentialField.aliyunAccessKeySecret;

  @override
  void initState() {
    super.initState();
    final credentials = context.read<VoiceInputCubit>().state.credentials;
    _controller = TextEditingController(text: credentials.field(widget.field));
    _debouncer = Debouncer(
      tag: 'voice-cred-${widget.field.name}',
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _persist(String value) =>
      context.read<VoiceInputCubit>().setCredential(widget.field, value);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      key: AppKeys.voiceSettingsCredentialField(widget.field.name),
      controller: _controller,
      obscureText: _obscure,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: _fieldLabel(l10n, widget.field),
      ),
      onChanged: (value) => _debouncer(() => _persist(value)),
      onSubmitted: (value) {
        _debouncer.cancel();
        _persist(value);
      },
    );
  }
}

/// Runs [VoiceInputCubit.testConnection] and reports the result in a snack bar.
/// Owns a local [_testing] flag to disable itself while a test is in flight —
/// pure local UI state, so `setState` is correct here.
class _TestConnectionTile extends StatefulWidget {
  const _TestConnectionTile();

  @override
  State<_TestConnectionTile> createState() => _TestConnectionTileState();
}

class _TestConnectionTileState extends State<_TestConnectionTile> {
  bool _testing = false;

  Future<void> _test() async {
    // Capture everything context-derived before the await: using `context`
    // afterwards trips use_build_context_synchronously, and the page may have
    // been popped by then.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final cubit = context.read<VoiceInputCubit>();
    setState(() => _testing = true);
    try {
      final ms = await cubit.testConnection();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.voiceInputTestPassed(ms))),
      );
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        'Voice connection test failed ($error)',
        error: error,
        stackTrace: stackTrace,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.voiceInputTestFailed)),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      key: AppKeys.voiceSettingsTestButton,
      leading: const Icon(Icons.wifi_tethering),
      title: Text(l10n.voiceInputTestConnection),
      trailing: _testing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      enabled: !_testing,
      onTap: _testing ? null : _test,
    );
  }
}
