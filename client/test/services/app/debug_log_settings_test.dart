import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/services/app/debug_log_settings.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('is off until someone turns it on', () async {
    // Opt-in is the whole point: a phone that just runs the app should not be
    // accumulating diagnostic files nobody asked for.
    final preferences = await SharedPreferences.getInstance();
    expect(DebugLogSettings.read(preferences), isFalse);
  });

  test('round-trips both values', () async {
    final preferences = await SharedPreferences.getInstance();
    await DebugLogSettings.write(preferences, true);
    expect(DebugLogSettings.read(preferences), isTrue);
    await DebugLogSettings.write(preferences, false);
    expect(DebugLogSettings.read(preferences), isFalse);
  });

  test('survives a fresh SharedPreferences handle', () async {
    // main() reads it on the next launch, from a different instance.
    await DebugLogSettings.write(await SharedPreferences.getInstance(), true);
    expect(
      DebugLogSettings.read(await SharedPreferences.getInstance()),
      isTrue,
    );
  });
}
