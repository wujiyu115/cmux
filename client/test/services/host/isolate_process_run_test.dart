import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/isolate_process_run.dart';

(String, List<String>) get _echoCommand =>
    Platform.isWindows ? ('cmd', ['/c', 'echo', 'isolate-ok']) : ('echo', [
      'isolate-ok',
    ]);

(String, List<String>) get _slowCommand => Platform.isWindows
    ? ('ping', ['-n', '3', '127.0.0.1'])
    : ('sleep', ['2']);

void main() {
  test('returns exit code and stdout of the subprocess', () async {
    final (executable, arguments) = _echoCommand;

    final result = await isolateProcessRun(executable, arguments);

    expect(result.exitCode, 0);
    expect((result.stdout as String).trim(), 'isolate-ok');
  });

  test('propagates ProcessException for a missing executable', () async {
    await expectLater(
      isolateProcessRun('definitely-not-an-executable-xyz', const []),
      throwsA(isA<ProcessException>()),
    );
  });

  test('keeps the calling isolate responsive while the subprocess runs', () async {
    // Regression guard for the WSL saturation freeze: spawning wsl.exe while
    // a WSL distro launches a large CLI can queue in CreateProcess for tens
    // of seconds, which blocks the calling isolate's thread. The wait must
    // live on the helper isolate so the UI isolate keeps servicing events.
    // (Limitation: this catches a regression back to a direct
    // `Process.runSync` on the calling isolate, where no timer would fire;
    // it cannot catch a regression to plain `Process.run`, whose stall only
    // manifests under OS-level process-creation saturation.)
    final (executable, arguments) = _slowCommand;
    var ticks = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      ticks++;
    });
    addTearDown(timer.cancel);

    final result = await isolateProcessRun(executable, arguments);

    expect(result.exitCode, 0);
    // `ping -n 3` / `sleep 2` take ~2s, i.e. ~40 tick windows.
    expect(ticks, greaterThan(10));
  });
}
