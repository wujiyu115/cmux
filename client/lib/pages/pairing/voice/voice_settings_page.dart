import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/voice_input_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../services/stt/stt_locales.dart';
import '../../../services/stt/stt_provider.dart';
import '../../../utils/ui/app_keys.dart';
import 'voice_credentials_section.dart';

/// Voice-input settings for the mobile pairing client: which recognition
/// backend, which language, the cloud credentials, and a one-tap connection
/// test.
///
/// Reached from the phone's settings sheet and from the composer mic (a long
/// press, or a tap while the chosen backend is unconfigured). The cubit is
/// provided once at the pairing shell and re-provided across the route boundary
/// by [route] so the settings the user edits here are the same ones the mic
/// reads.
class VoiceSettingsPage extends StatelessWidget {
  const VoiceSettingsPage({super.key});

  /// Route helper so callers cannot forget to re-provide the cubit across the
  /// route boundary.
  static Route<void> route(VoiceInputCubit cubit) => MaterialPageRoute(
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: const VoiceSettingsPage(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      key: AppKeys.voiceSettingsPage,
      appBar: AppBar(title: Text(l10n.voiceInputSettings)),
      body: BlocBuilder<VoiceInputCubit, VoiceInputState>(
        // Settings never need to repaint while a recognition session starts or
        // stops; only these three fields change what this page renders, and
        // VoiceInputState has no value equality so every emit is distinct.
        buildWhen: (a, b) =>
            a.provider != b.provider ||
            a.localeId != b.localeId ||
            a.credentials != b.credentials,
        builder: (context, state) {
          final cubit = context.read<VoiceInputCubit>();
          return ListView(
            children: [
              _SectionHeader(title: l10n.voiceInputProvider),
              RadioGroup<SttProviderType>(
                groupValue: state.provider,
                onChanged: (type) {
                  if (type != null) cubit.setProvider(type);
                },
                child: Column(
                  children: [
                    for (final type in SttProviderType.values)
                      RadioListTile<SttProviderType>(
                        key: AppKeys.voiceSettingsProviderTile(type.name),
                        value: type,
                        title: Text(_providerLabel(l10n, type)),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              _LanguageRow(state: state),
              if (state.provider != SttProviderType.system) ...[
                const Divider(height: 1),
                VoiceCredentialsSection(provider: state.provider),
              ],
            ],
          );
        },
      ),
    );
  }
}

String _providerLabel(AppLocalizations l10n, SttProviderType type) =>
    switch (type) {
      SttProviderType.system => l10n.voiceInputProviderSystem,
      SttProviderType.volcengine => l10n.voiceInputProviderVolcengine,
      SttProviderType.aliyun => l10n.voiceInputProviderAliyun,
    };

/// A section title above a group of rows.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.lg, spacing.lg, spacing.lg, spacing.sm),
      child: Text(title, style: styles.mdMedium),
    );
  }
}

/// The recognition-language row: shows the pinned language (or "follow the
/// system") and opens a picker listing the languages the chosen backend
/// supports.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({required this.state});

  final VoiceInputState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<VoiceInputCubit>();
    return ListTile(
      key: AppKeys.voiceSettingsLanguageTile,
      leading: const Icon(Icons.language),
      title: Text(l10n.voiceInputLanguage),
      subtitle: Text(_subtitle(l10n)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _pick(context, cubit),
    );
  }

  String _subtitle(AppLocalizations l10n) {
    if (state.localeId.isEmpty) return l10n.voiceInputLanguageDefault;
    for (final locale in sttLocalesFor(state.provider)) {
      if (locale.id == state.localeId) return locale.name;
    }
    return l10n.voiceInputLanguageDefault;
  }

  void _pick(BuildContext context, VoiceInputCubit cubit) {
    final l10n = context.l10n;
    // Capture the cubit rather than reading it inside the sheet: the modal
    // route mounts under the Navigator, above the BlocProvider, so a
    // context.read there would not find the cubit.
    final locales = sttLocalesFor(state.provider);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            // First row is "follow the system", whose value is the empty
            // string. Language names below are deliberately not localized —
            // each row reads as the language it selects.
            ListTile(
              title: Text(l10n.voiceInputLanguageDefault),
              onTap: () {
                cubit.setLocaleId('');
                Navigator.of(sheetContext).pop();
              },
            ),
            for (final locale in locales)
              ListTile(
                title: Text(locale.name),
                onTap: () {
                  cubit.setLocaleId(locale.id);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}
