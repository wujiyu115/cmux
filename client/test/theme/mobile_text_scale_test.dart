import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('the phone boost lands after the clamp, not before', () {
    // The load-bearing detail. A 3x phone drives os * dpr to 3.0, which the
    // clamp already pins to kTypographyCustomMultiplierMax. Folding the boost in
    // beforehand (3.0 * 1.15 = 3.45) would clamp back to the same ceiling and
    // the phone would silently get no boost at all.
    const dpr = 3.0;
    final desktopLike = autoTextScaleForSystem(1.0, dpr);
    final phone = autoTextScaleForSystem(1.0, dpr, mobile: true);

    expect(desktopLike, kTypographyCustomMultiplierMax);
    expect(phone, kTypographyCustomMultiplierMax * kMobileTextScaleBoost);
    expect(phone, greaterThan(desktopLike));
  });

  test('mobile defaults to off so desktop is untouched', () {
    for (final dpr in [1.0, 1.5, 2.0, 3.0]) {
      expect(
        autoTextScaleForSystem(1.0, dpr),
        autoTextScaleForSystem(1.0, dpr, mobile: false),
        reason: 'dpr $dpr',
      );
    }
  });

  test('the boost is a plain multiple at every unsaturated dpr too', () {
    // Below the ceiling the clamp is inert, so the boost is a clean factor —
    // this pins that the mobile branch multiplies rather than replacing.
    for (final dpr in [1.0, 1.5]) {
      expect(
        autoTextScaleForSystem(1.0, dpr, mobile: true),
        closeTo(autoTextScaleForSystem(1.0, dpr) * kMobileTextScaleBoost, 1e-9),
        reason: 'dpr $dpr',
      );
    }
  });

  test('the boost enlarges rather than shrinking', () {
    // Guards against someone "fixing" the phone by dividing.
    expect(kMobileTextScaleBoost, greaterThan(1.0));
  });

  test('a degenerate dpr or OS scale still yields a usable multiplier', () {
    expect(autoTextScaleForSystem(0, 0, mobile: true), kMobileTextScaleBoost);
    expect(autoTextScaleForSystem(-1, -1, mobile: true), kMobileTextScaleBoost);
  });
}
