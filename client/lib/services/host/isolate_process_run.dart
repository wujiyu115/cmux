import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Runs a one-shot subprocess on a helper isolate.
///
/// Why not `Process.run` directly: on Windows the native `CreateProcess` part
/// of a spawn executes on the calling isolate's thread. Normally that is a few
/// dozen ms, but when process creation saturates (e.g. a WSL distro launching
/// a large agent CLI whose hooks interop-spawn helper processes), the same
/// call can queue for tens of seconds — freezing the UI isolate the whole
/// time. `Process.runSync` here blocks only the helper isolate.
///
/// `Process.run` semantics are preserved: encodings, environment, and error
/// type (`ProcessException`) survive the isolate hop, and stdout/stderr come
/// back decoded with [systemEncoding] unless overridden.
Future<ProcessResult> isolateProcessRun(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
}) {
  return Isolate.run(
    () => Process.runSync(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      stdoutEncoding: stdoutEncoding ?? systemEncoding,
      stderrEncoding: stderrEncoding ?? systemEncoding,
    ),
  );
}
