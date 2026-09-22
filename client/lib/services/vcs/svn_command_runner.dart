import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../cli/cli_tool_locator.dart';
import '../git/git_command_runner.dart' show GitCommandResult;
import '../host/host_one_shot_runner.dart';
import '../ssh/ssh_run_result.dart';
import '../storage/remote_file_store.dart';
import '../storage/runtime_context.dart';

export '../git/git_command_runner.dart' show GitCommandResult;

/// Executes svn against a working directory on local disk, WSL, or SSH.
///
/// Mirrors [GitCommandRunner]: one `svn <args> -- <dir-relative targets>`
/// invocation per call, UTF-8 output, non-zero exits surfaced through
/// [GitCommandResult] (aliased name kept so parsers/expectations read the
/// same shape for both VCSes).
abstract interface class SvnCommandRunner {
  Future<bool> get isAvailable;

  Future<GitCommandResult> runInDirectory(String dir, List<String> args);
}

GitCommandResult _resultFromHost(HostRunResult result) {
  return GitCommandResult(
    exitCode: result.exitCode,
    stdout: result.stdout,
    stderr: result.stderr,
  );
}

HostProcessRunner _hostProcessRunnerFrom(ProcessRunner runner) {
  return (
    executable,
    arguments, {
    workingDirectory,
    environment,
    includeParentEnvironment = true,
    stdoutEncoding,
    stderrEncoding,
  }) {
    return runner(
      executable,
      arguments,
      stdoutEncoding: stdoutEncoding ?? const Utf8Codec(allowMalformed: true),
      stderrEncoding: stderrEncoding ?? const Utf8Codec(allowMalformed: true),
    );
  };
}

/// `svn` with no global `-C` flag: every caller passes the wc root as
/// [SvnCommandRunner.runInDirectory]'s dir via the host's working directory.
class LocalSvnCommandRunner implements SvnCommandRunner {
  LocalSvnCommandRunner({
    ProcessRunner runner = cliToolDefaultProcessRun,
    CliToolLocator? svnLocator,
    HostOneShotRunner? hostRunner,
  }) : _runner = runner,
       _svnLocator = svnLocator ?? const CliToolLocator('svn') {
    _host =
        hostRunner ??
        LocalHostOneShotRunner(processRunner: _hostProcessRunnerFrom(runner));
  }

  final ProcessRunner _runner;
  final CliToolLocator _svnLocator;
  late final HostOneShotRunner _host;

  static Future<String?>? _locateFuture;

  static void debugResetExecutableCache() => _locateFuture = null;

  Future<String?> get _svn =>
      _locateFuture ??= _svnLocator.locate(runner: _runner);

  @override
  Future<bool> get isAvailable async => (await _svn) != null;

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args) async {
    final svn = await _svn;
    if (svn == null) {
      return const GitCommandResult(
        exitCode: 127,
        stdout: '',
        stderr: 'svn executable not found on PATH',
      );
    }
    final result = await _host.run(
      HostRunRequest(
        executable: svn,
        arguments: args,
        workingDirectory: dir,
      ),
    );
    return _resultFromHost(result);
  }
}

class WslSvnCommandRunner implements SvnCommandRunner {
  WslSvnCommandRunner({
    String? distro,
    ProcessRunner? wslRunner,
    HostOneShotRunner? hostRunner,
  }) : _distro = distro?.trim(),
       _host =
           hostRunner ??
           WslHostOneShotRunner(
             distro: distro,
             processRunner: _hostProcessRunnerFrom(
               wslRunner ?? cliToolDefaultProcessRun,
             ),
           );

  final String? _distro;
  final HostOneShotRunner _host;

  /// Per-distro availability probe cache (mirrors [WslGitCommandRunner]).
  static final Map<String, Future<bool>> _availableByDistro = {};

  static void debugResetAvailabilityCache() => _availableByDistro.clear();

  @override
  Future<bool> get isAvailable =>
      _availableByDistro[_distro ?? ''] ??= _probeAvailability();

  Future<bool> _probeAvailability() async {
    final result = await _host.run(
      const HostRunRequest(
        executable: 'sh',
        arguments: ['-lc', 'command -v svn || which svn 2>/dev/null'],
      ),
    );
    return result.succeeded && result.stdout.trim().isNotEmpty;
  }

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args) async {
    final result = await _host.run(
      HostRunRequest(executable: 'svn', arguments: args, workingDirectory: dir),
    );
    return _resultFromHost(result);
  }
}

class RemoteSvnCommandRunner implements SvnCommandRunner {
  RemoteSvnCommandRunner({
    RemoteFileStore? store,
    Future<SSHRunResult> Function(String command)? execShell,
    HostOneShotRunner? hostRunner,
    String? hostKey,
  }) : assert(
         store != null || execShell != null,
         'store or execShell required',
       ),
       _execShell = execShell ?? store!.execShell,
       _hostKey = hostKey ?? '',
       _host =
           hostRunner ??
           RemoteHostOneShotRunner(execShell: execShell ?? store!.execShell);

  final Future<SSHRunResult> Function(String command) _execShell;
  final HostOneShotRunner _host;
  final String _hostKey;

  /// Per-host availability probe cache (mirrors [RemoteGitCommandRunner]).
  static final Map<String, Future<bool>> _availableByHost = {};

  static void debugResetAvailabilityCache() => _availableByHost.clear();

  @override
  Future<bool> get isAvailable =>
      _availableByHost[_hostKey] ??= _probeAvailability();

  Future<bool> _probeAvailability() async {
    final result = await _execShell(
      'command -v svn || which svn 2>/dev/null',
    );
    if (sshRunFailed(result)) return false;
    return utf8.decode(result.stdout, allowMalformed: true).trim().isNotEmpty;
  }

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args) async {
    final result = await _host.run(
      HostRunRequest(executable: 'svn', arguments: args, workingDirectory: dir),
    );
    return _resultFromHost(result);
  }
}

/// Picks the svn runner for the active [RuntimeContext] storage backend.
SvnCommandRunner svnCommandRunnerForContext(RuntimeContext ctx) {
  return switch (ctx.mode) {
    StorageBackendMode.ssh => RemoteSvnCommandRunner(
      store: ctx.remoteFileStore!,
      hostKey: ctx.target.id,
    ),
    StorageBackendMode.wsl => WslSvnCommandRunner(distro: ctx.target.wslDistro),
    StorageBackendMode.native => LocalSvnCommandRunner(),
  };
}
