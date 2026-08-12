import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/notification/pairing_mirror_notification_tap.dart';

void main() {
  test('handlePairingMirrorNotificationTap opens the named mirror', () async {
    final opened = <String>[];

    await handlePairingMirrorNotificationTap(
      payload: 'pairing-mirror:ws:pane-1',
      openMirror: (id) async => opened.add(id),
    );

    expect(opened, ['ws:pane-1']);
  });

  test('handlePairingMirrorNotificationTap ignores foreign payloads', () async {
    final opened = <String>[];

    for (final payload in [
      null,
      '  ',
      'pairing-mirror:',
      'pairing-mirror:   ',
      '/home-v2/workspace/ws-1',
      'ws:pane-1',
    ]) {
      await handlePairingMirrorNotificationTap(
        payload: payload,
        openMirror: (id) async => opened.add(id),
      );
    }

    expect(opened, isEmpty);
  });

  test('isPairingMirrorPayload only claims the mirror scheme', () {
    expect(isPairingMirrorPayload('pairing-mirror:ws:pane-1'), isTrue);
    expect(isPairingMirrorPayload('  pairing-mirror:ws:pane-1  '), isTrue);
    expect(isPairingMirrorPayload('/home-v2/workspace/ws-1'), isFalse);
    expect(isPairingMirrorPayload(null), isFalse);
    expect(isPairingMirrorPayload(''), isFalse);
  });
}
