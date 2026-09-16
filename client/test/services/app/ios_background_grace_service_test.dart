import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/app/ios_background_grace_service.dart';

void main() {
  const channel = MethodChannel('teampilot/background_grace');

  IosBackgroundGraceService serviceWithHandler(
    Future<Object?>? Function(MethodCall call) handler,
  ) {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler);
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    return IosBackgroundGraceService(channel: channel, enabled: true);
  }

  test('begin invokes the channel once and marks the assertion held', () async {
    final calls = <MethodCall>[];
    final service = serviceWithHandler((call) async {
      calls.add(call);
      return 1;
    });

    await service.begin();
    expect(service.isHeld, isTrue);
    expect(calls.map((c) => c.method), ['beginBackgroundTask']);

    // Idempotent: a second begin (e.g. hidden then paused) never stacks
    // assertions.
    await service.begin();
    expect(calls, hasLength(1));
  });

  test('begin when the runtime grants no time is not held', () async {
    final service = serviceWithHandler((call) async => -1);

    await service.begin();
    expect(service.isHeld, isFalse);
  });

  test('end releases the assertion and becomes a no-op afterwards', () async {
    final calls = <MethodCall>[];
    final service = serviceWithHandler((call) async {
      calls.add(call);
      return 1;
    });

    await service.begin();
    await service.end();
    expect(service.isHeld, isFalse);
    expect(calls.map((c) => c.method), [
      'beginBackgroundTask',
      'endBackgroundTask',
    ]);

    await service.end();
    expect(calls, hasLength(2));
  });

  test('end without begin never touches the channel', () async {
    final calls = <MethodCall>[];
    final service = serviceWithHandler((call) async {
      calls.add(call);
      return 1;
    });

    await service.end();
    expect(calls, isEmpty);
  });

  test('a missing native handler is swallowed, not thrown', () async {
    // Simulates an app build where the Swift handler is absent: begin must
    // degrade to the pre-grace behavior instead of crashing the lifecycle
    // observer.
    TestWidgetsFlutterBinding.ensureInitialized();
    final service = IosBackgroundGraceService(
      channel: const MethodChannel('teampilot/background_grace_missing'),
      enabled: true,
    );

    await service.begin();
    expect(service.isHeld, isFalse);
    await service.end();
  });

  test('a disabled service (non-iOS) never touches the channel', () async {
    final calls = <MethodCall>[];
    serviceWithHandler((call) async {
      calls.add(call);
      return 1;
    });
    // enabled defaults to Platform.isIOS, false on the test host.
    final disabled = IosBackgroundGraceService(channel: channel);

    await disabled.begin();
    await disabled.end();
    expect(calls, isEmpty);
    expect(disabled.isHeld, isFalse);
  });
}
