import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/onboarding/onboarding_wizard.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/app/onboarding_service.dart';
import 'package:teampilot/services/plugin/profile_plugin_linker_service.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('onboardingStepsForPlatform', () {
    test('desktop has the appearance step only', () {
      expect(onboardingStepsForPlatform(), [OnboardingStepKind.appearance]);
    });
  });

  group('OnboardingService', () {
    test('shows wizard for fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = OnboardingService(
        appSettings: SharedPrefsAppSettingsRepository(prefs),
      );

      expect(await service.shouldShowOnboarding(), isTrue);
    });

    test(
      'shows wizard when session preferences exist but onboarding incomplete',
      () async {
        SharedPreferences.setMockInitialValues({
          'flashskyai.session_preferences.v1': '{"connectionMode":"localPty"}',
        });
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPrefsAppSettingsRepository(prefs);
        final service = OnboardingService(appSettings: repo);

        expect(await service.shouldShowOnboarding(), isTrue);
        expect(await repo.loadHasCompletedOnboarding(), isFalse);
      },
    );

    test('skips wizard only when onboarding was completed', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);
      await repo.saveHasCompletedOnboarding(true);
      final service = OnboardingService(appSettings: repo);

      expect(await service.shouldShowOnboarding(), isFalse);
    });
  });

}
