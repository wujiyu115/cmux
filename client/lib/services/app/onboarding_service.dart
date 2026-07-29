import '../../cubits/app_provider_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../models/app_provider_config.dart';
import '../../repositories/app_settings_repository.dart';

/// Decides whether the first-run setup wizard should appear.
///
/// Only [AppSettingsRepository.hasCompletedOnboarding] controls this gate.
/// Partial wizard progress (saved preferences, provider imports, etc.) does
/// not skip onboarding — the flag is written in [OnboardingGate] when the user
/// finishes the last step.
class OnboardingService {
  OnboardingService({required AppSettingsRepository appSettings})
    : _appSettings = appSettings;
  final AppSettingsRepository _appSettings;

  Future<bool> shouldShowOnboarding() async {
    return !(await _appSettings.loadHasCompletedOnboarding());
  }

  /// Persists [presetId] as the onboarding default provider selection.
  static Future<void> applyDefaultPreset({
    required String presetId,
    required CliPresetsCubit cliPresetsCubit,
    required AppProviderCubit appProviderCubit,
  }) async {
    final trimmed = presetId.trim();
    if (trimmed.isEmpty) return;

    final preset = cliPresetsCubit.state.presetById(trimmed);
    if (preset == null) return;

    await appProviderCubit.setSelectedCli(preset.cli);
    appProviderCubit.selectProvider(preset.provider);
  }

}
