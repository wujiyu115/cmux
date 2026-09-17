import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('uiZoomMultiplierFor: standard is exactly 100%', () {
    expect(
      uiZoomMultiplierFor(scaleId: 'standard', customMultiplier: 1.0),
      1.0,
    );
  });

  test('uiZoomMultiplierFor: compact / comfortable presets', () {
    expect(
      uiZoomMultiplierFor(scaleId: 'compact', customMultiplier: 1.0),
      kUiZoomCompactMultiplier,
    );
    expect(
      uiZoomMultiplierFor(scaleId: 'comfortable', customMultiplier: 1.0),
      kUiZoomComfortableMultiplier,
    );
  });

  test('uiZoomMultiplierFor: custom clamps the stored multiplier', () {
    expect(
      uiZoomMultiplierFor(scaleId: 'custom', customMultiplier: 1.2),
      closeTo(1.2, 0.0001),
    );
    expect(
      uiZoomMultiplierFor(scaleId: 'custom', customMultiplier: 9.0),
      kUiZoomCustomMultiplierMax,
    );
    expect(
      uiZoomMultiplierFor(scaleId: 'custom', customMultiplier: 0.01),
      kUiZoomCustomMultiplierMin,
    );
  });

  test('clampUiZoom bounds the effective zoom', () {
    expect(clampUiZoom(0.1), kUiZoomMin);
    expect(clampUiZoom(9.0), kUiZoomMax);
    expect(clampUiZoom(1.2), 1.2);
  });

  test('AppTypographyScale.fromPx derives UI roles and pins mono', () {
    final scale = AppTypographyScale.fromPx(uiFontSize: 16, monoFontSize: 13);
    // UI roles derive from uiFontSize / 14.
    expect(scale.multiplier, closeTo(16 / 14, 1e-9));
    expect(scale.bodyMedium, closeTo(16, 1e-9));
    expect(scale.bodySmall, closeTo(12 * 16 / 14, 1e-9));
    // Mono faces render at exactly monoFontSize, independent of the UI size.
    expect(scale.mono, 13);
    expect(scale.terminal, 13);
  });

  test('px sizes clamp to the persisted ranges', () {
    expect(clampUiFontSize(99), kUiFontSizeMax);
    expect(clampUiFontSize(1), kUiFontSizeMin);
    expect(clampMonoFontSize(99), kMonoFontSizeMax);
    expect(clampMonoFontSize(1), kMonoFontSizeMin);
  });
}
