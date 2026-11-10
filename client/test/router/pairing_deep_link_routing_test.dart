import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/router/app_router.dart';

void main() {
  test('a pairing deep link is routed away from the "not found" page', () {
    expect(
      pairingDeepLinkDestination(Uri.parse('teampilot://pair?code=abc')),
      '/home-v2',
    );
  });

  test('the slash form Android delivers is recognized too', () {
    expect(
      pairingDeepLinkDestination(Uri.parse('teampilot://pair/?code=abc')),
      '/home-v2',
    );
  });

  test('ordinary routes are left alone', () {
    expect(pairingDeepLinkDestination(Uri.parse('/home-v2')), isNull);
    expect(
      pairingDeepLinkDestination(Uri.parse('/home-v2/workspace/w1')),
      isNull,
    );
    expect(pairingDeepLinkDestination(Uri.parse('https://example.com')), isNull);
  });
}
