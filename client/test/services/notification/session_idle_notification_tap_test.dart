import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/notification/session_idle_notification_tap.dart';

void main() {
  test('handleSessionIdleNotificationTap navigates valid workspace payload',
      () async {
    final navigated = <String>[];
    final marked = <String>[];
    var focused = false;

    await handleSessionIdleNotificationTap(
      payload: '/home-v2/workspace/ws-1?session=sess-1',
      go: navigated.add,
      markReadMatchingPayload: (location) async => marked.add(location),
      focusWindow: () async {
        focused = true;
      },
    );

    expect(focused, isTrue);
    expect(navigated, ['/home-v2/workspace/ws-1?session=sess-1']);
    expect(marked, ['/home-v2/workspace/ws-1?session=sess-1']);
  });

  test('handleSessionIdleNotificationTap ignores empty or non-workspace payload',
      () async {
    final navigated = <String>[];
    final marked = <String>[];
    var focused = false;

    await handleSessionIdleNotificationTap(
      payload: null,
      go: navigated.add,
      markReadMatchingPayload: (location) async => marked.add(location),
      focusWindow: () async {
        focused = true;
      },
    );
    await handleSessionIdleNotificationTap(
      payload: '  ',
      go: navigated.add,
      markReadMatchingPayload: (location) async => marked.add(location),
      focusWindow: () async {
        focused = true;
      },
    );
    await handleSessionIdleNotificationTap(
      payload: '/config/layout',
      go: navigated.add,
      markReadMatchingPayload: (location) async => marked.add(location),
      focusWindow: () async {
        focused = true;
      },
    );

    expect(focused, isFalse);
    expect(navigated, isEmpty);
    expect(marked, isEmpty);
  });

  test('handleSessionIdleNotificationTap navigates when focusWindow throws',
      () async {
    // window_manager has no mobile implementation: on iOS the focus call throws
    // MissingPluginException, which must not swallow the navigation.
    final navigated = <String>[];

    await handleSessionIdleNotificationTap(
      payload: '/home-v2/workspace/ws-1',
      go: navigated.add,
      markReadMatchingPayload: (_) async =>
          throw Exception('MissingPluginException'),
      focusWindow: () async => throw Exception('MissingPluginException'),
    );

    expect(navigated, ['/home-v2/workspace/ws-1']);
  });
}
