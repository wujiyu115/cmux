import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/repositories/layout_repository.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('layout cubit persists preferences', () async {
    final cubit = LayoutCubit(
      repository: LayoutRepository(await SharedPreferences.getInstance()),
    );
    await cubit.load();

    await cubit.setThemeMode('dark');
    expect(cubit.state.preferences.themeMode, 'dark');
  });

  test('setEditorPreviewTabs persists and reloads', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    await cubit.load();

    await cubit.setEditorPreviewTabs(false);
    expect(cubit.state.preferences.editorPreviewTabs, isFalse);

    final reloaded = LayoutCubit(repository: LayoutRepository(prefs));
    await reloaded.load();
    expect(reloaded.state.preferences.editorPreviewTabs, isFalse);
  });

  test('setMonoFontScale persists, reloads, and clamps', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    await cubit.load();
    expect(cubit.state.preferences.monoFontScale, kDefaultMonoFontScale);

    await cubit.setMonoFontScale(1.3);
    expect(cubit.state.preferences.monoFontScale, 1.3);

    await cubit.setMonoFontScale(99);
    expect(cubit.state.preferences.monoFontScale, kMonoFontScaleMax);
    await cubit.setMonoFontScale(0.1);
    expect(cubit.state.preferences.monoFontScale, kMonoFontScaleMin);

    final reloaded = LayoutCubit(repository: LayoutRepository(prefs));
    await reloaded.load();
    expect(reloaded.state.preferences.monoFontScale, kMonoFontScaleMin);
  });

  test('monoFontScale out-of-range JSON falls back clamped', () {
    final prefs = LayoutPreferences.fromJson(const {
      'monoFontScale': 5,
    });
    expect(prefs.monoFontScale, kMonoFontScaleMax);
  });

  test('AppTypographyScale monoFontScale scales mono roles only', () {
    const scale = AppTypographyScale(
      multiplier: 1.2,
      monoFontScale: 1.5,
    );
    expect(scale.mono, 14 * 1.2 * 1.5);
    expect(scale.terminal, 14 * 1.2 * 1.5);
    expect(scale.bodyMedium, 14 * 1.2);
    expect(scale.labelSmall, 11 * 1.2);
  });
}
