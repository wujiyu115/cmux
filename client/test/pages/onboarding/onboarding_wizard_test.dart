import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/onboarding/onboarding_wizard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('onboardingStepsForPlatform', () {
    test('desktop has the appearance step only', () {
      expect(onboardingStepsForPlatform(), [OnboardingStepKind.appearance]);
    });
  });
}
