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

  test('setMonoFontSize persists, reloads, and clamps', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    await cubit.load();
    expect(cubit.state.preferences.monoFontSize, kDefaultMonoFontSize);

    await cubit.setMonoFontSize(18);
    expect(cubit.state.preferences.monoFontSize, 18);

    await cubit.setMonoFontSize(99);
    expect(cubit.state.preferences.monoFontSize, kMonoFontSizeMax);
    await cubit.setMonoFontSize(1);
    expect(cubit.state.preferences.monoFontSize, kMonoFontSizeMin);

    final reloaded = LayoutCubit(repository: LayoutRepository(prefs));
    await reloaded.load();
    expect(reloaded.state.preferences.monoFontSize, kMonoFontSizeMin);
  });

  test('setUiFontSize persists and clamps', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    await cubit.load();
    expect(cubit.state.preferences.uiFontSize, kDefaultUiFontSize);

    await cubit.setUiFontSize(16);
    expect(cubit.state.preferences.uiFontSize, 16);

    await cubit.setUiFontSize(99);
    expect(cubit.state.preferences.uiFontSize, kUiFontSizeMax);

    final reloaded = LayoutCubit(repository: LayoutRepository(prefs));
    await reloaded.load();
    expect(reloaded.state.preferences.uiFontSize, kUiFontSizeMax);
  });

  test('uiFontSize out-of-range JSON falls back clamped', () {
    expect(
      LayoutPreferences.fromJson(const {'uiFontSize': 99}).uiFontSize,
      kUiFontSizeMax,
    );
    expect(
      LayoutPreferences.fromJson(const {'monoFontSize': 1}).monoFontSize,
      kMonoFontSizeMin,
    );
  });

  group('legacy multiplier → px migration', () {
    test('text-size presets fold into uiFontSize', () {
      expect(
        LayoutPreferences.fromJson(
          const {'typographyScale': 'standard'},
        ).uiFontSize,
        14,
      );
      expect(
        LayoutPreferences.fromJson(
          const {'typographyScale': 'compact'},
        ).uiFontSize,
        13, // round(14 × 0.92)
      );
      expect(
        LayoutPreferences.fromJson(
          const {'typographyScale': 'comfortable'},
        ).uiFontSize,
        15, // round(14 × 1.08)
      );
      expect(
        LayoutPreferences.fromJson(const {
          'typographyScale': 'custom',
          'typographyScaleCustomMultiplier': 1.5,
        }).uiFontSize,
        21, // round(14 × 1.5)
      );
    });

    test('mono migration includes the text preset factor', () {
      // round(14 × 0.92 × 0.85) = 11 — the draft's table omitted p; without
      // it this would wrongly be 12.
      expect(
        LayoutPreferences.fromJson(const {
          'typographyScale': 'compact',
          'monoFontScale': 0.85,
        }).monoFontSize,
        11,
      );
      expect(
        LayoutPreferences.fromJson(const {'monoFontScale': 1.15}).monoFontSize,
        16, // round(14 × 1.15) at standard text
      );
      expect(
        LayoutPreferences.fromJson(const {
          'typographyScale': 'custom',
          'typographyScaleCustomMultiplier': 1.5,
          'monoFontScale': 1.6,
        }).monoFontSize,
        kMonoFontSizeMax, // round(14 × 1.5 × 1.6) = 34 → clamped 28
      );
    });

    test('a fresh JSON has no legacy keys and lands on defaults', () {
      final prefs = LayoutPreferences.fromJson(const {});
      expect(prefs.uiFontSize, kDefaultUiFontSize);
      expect(prefs.monoFontSize, kDefaultMonoFontSize);
    });

    test('new px fields win over legacy keys; toJson drops legacy', () {
      final prefs = LayoutPreferences.fromJson(const {
        'uiFontSize': 20,
        'monoFontSize': 18,
        'typographyScale': 'compact',
        'monoFontScale': 0.85,
      });
      expect(prefs.uiFontSize, 20);
      expect(prefs.monoFontSize, 18);

      final json = prefs.toJson();
      expect(json['uiFontSize'], 20);
      expect(json['monoFontSize'], 18);
      expect(json.containsKey('typographyScale'), isFalse);
      expect(json.containsKey('typographyScaleCustomMultiplier'), isFalse);
      expect(json.containsKey('monoFontScale'), isFalse);
    });
  });

  test('AppTypographyScale px model pins mono independent of UI size', () {
    const scale = AppTypographyScale(multiplier: 1.2, monoPx: 15);
    expect(scale.mono, 15);
    expect(scale.terminal, 15);
    expect(scale.bodyMedium, 14 * 1.2);
    expect(scale.labelSmall, 11 * 1.2);
  });
}
