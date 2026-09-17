import 'dart:async';
import 'dart:io';

import '../../models/runtime_target.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../host/host_shell_argv.dart';
import '../host/host_wsl_argv.dart';
import '../quick_open/quick_open_index.dart';
import '../run/process_run_executor.dart';
import '../ssh/ssh_client_factory.dart';
import '../storage/runtime_context.dart';
import '../workspace/workspace_tools_scope.dart';
import 'builtin_search_engine.dart';
import 'ripgrep_search_engine.dart';
import 'search_query.dart';
import 'search_result_models.dart';

/// Per-plane search facade: for each workspace target slice it prefers
/// ripgrep (`rg --json`, VS Code-style — scanned in rg's threads, results
/// streamed, kill = cancel) and falls back to the built-in scanner when rg
/// is unavailable on that plane. Multi-slice (mixed local + ssh) workspaces
/// run one engine per slice concurrently and merge.
class WorkspaceSearchService {
  WorkspaceSearchService({
    required QuickOpenIndexRegistry indexRegistry,
    SshProfileRepository? sshProfiles,
    SshClientFactory? sshClientFactory,
    SearchProcessSpawner? localSpawner,
    this.probeTimeout = const Duration(seconds: 5),
    this.executable = 'rg',
  }) : builtinEngine = BuiltinSearchEngine(indexRegistry: indexRegistry),
       _sshProfiles = sshProfiles,
       _sshClientFactory = sshClientFactory,
       _localSpawner = localSpawner ?? _defaultLocalSpawner;

  final BuiltinSearchEngine builtinEngine;
  final SshProfileRepository? _sshProfiles;
  final SshClientFactory? _sshClientFactory;
  final SearchProcessSpawner _localSpawner;
  final Duration probeTimeout;
  final String executable;

  /// targetId → ripgrep availability (probed once per target per session).
  final _rgAvailable = <String, Future<bool>>{};

  /// Runs [query] across every resolved slice of [scope].
  ///
  /// [pattern] is the pre-validated compiled regex ([SearchQuery.compilePattern]).
  SearchRunHandle search({
    required WorkspaceToolsScopeState scope,
    required SearchQuery query,
    required RegExp pattern,
  }) {
    final slices = [
      for (final slice in scope.targetSlices)
        if (slice.roots.where((r) => r.trim().isNotEmpty).isNotEmpty) slice,
    ];
    final primaryTargetId = slices.isEmpty ? null : slices.first.targetId;

    final children = <SearchRunHandle>[];
    final done = Future.wait(
      slices.map((slice) async {
        final ctx = slice.tools.context;
        final roots = slice.roots
            .where((r) => r.trim().isNotEmpty)
            .toList(growable: false);
        final useRg = await ripgrepAvailable(slice.targetId, ctx);
        if (useRg) {
          final run = RipgrepSearchEngine(
            spawner: _spawnerFor(ctx),
            executable: executable,
          ).search(
            query: query,
            pattern: pattern,
            targetId: slice.targetId,
            pathContext: ctx.filesystem.pathContext,
            roots: roots,
            workingDirectory: roots.first,
            primaryTargetId: primaryTargetId,
          );
          children.add(run);
          return run.results;
        }
        final run = builtinEngine.search(
          query: query,
          pattern: pattern,
          targetId: slice.targetId,
          fs: ctx.filesystem,
          roots: roots,
          primaryTargetId: primaryTargetId,
        );
        children.add(run);
        return run.results;
      }),
    ).then((sliceResults) => _merge(sliceResults));

    return SearchRunHandle(
      results: done,
      cancel: () {
        // Children register as they spawn; cancel the ones already running
        // (later ones get cancelled by their own superseded-generation logic).
        for (final child in List.of(children)) {
          child.cancel();
        }
      },
    );
  }

  static SearchResults _merge(List<SearchResults> parts) {
    if (parts.isEmpty) {
      return SearchResults.empty(engine: SearchEngineKind.ripgrep);
    }
    final files = <SearchFileResult>[];
    var total = 0;
    var truncated = false;
    // Builtin if any slice fell back — the status line notice then shows.
    var engine = SearchEngineKind.ripgrep;
    for (final part in parts) {
      files.addAll(part.files);
      total += part.totalMatches;
      truncated = truncated || part.truncated;
      if (part.engine == SearchEngineKind.builtin) {
        engine = SearchEngineKind.builtin;
      }
    }
    return SearchResults(
      files: files,
      totalMatches: total,
      truncated: truncated,
      engine: engine,
    );
  }

  /// Probes `rg --version` once per target; a failed/slow probe (remote
  /// planes) caches as unavailable so searches never stall on it again.
  Future<bool> ripgrepAvailable(String targetId, RuntimeContext ctx) {
    final cached = _rgAvailable[targetId];
    if (cached != null) return cached;
    final future = _probeRipgrep(ctx);
    _rgAvailable[targetId] = future;
    // A crashed probe must not poison the cache with an error.
    return future.catchError((Object _) => false);
  }

  Future<bool> _probeRipgrep(RuntimeContext ctx) async {
    try {
      final handle = await _spawnerFor(ctx)(
        executable: executable,
        arguments: const ['--version'],
        workingDirectory: '',
      );
      List<int> firstChunk;
      try {
        firstChunk = await handle.stdout.first.timeout(probeTimeout);
      } on Object {
        firstChunk = const <int>[];
      }
      handle.kill();
      handle.exitCode.ignore();
      return firstChunk.isNotEmpty;
    } on Object {
      return false;
    }
  }

  /// Builds the plane-appropriate process spawner from a [RuntimeContext]:
  /// native `Process.start`, `wsl.exe [-d distro] [--cd …]` argv, or SSH
  /// exec through the pooled storage client.
  SearchProcessSpawner _spawnerFor(RuntimeContext ctx) {
    switch (ctx.target.kind) {
      case RuntimeKind.local:
        return _localSpawner;
      case RuntimeKind.wsl:
        final distro = ctx.target.wslDistro;
        return ({required executable, required arguments, required workingDirectory}) async {
          final argv = HostWslArgv.processInvocation(
            distro: distro,
            workingDirectory: workingDirectory,
            executable: executable,
            arguments: arguments,
          );
          final process = await Process.start('wsl.exe', argv);
          return _LocalProcessRunHandle(process);
        };
      case RuntimeKind.ssh:
        return ({required executable, required arguments, required workingDirectory}) async {
          final profiles = _sshProfiles;
          final factory = _sshClientFactory;
          final profileId = ctx.target.sshProfileId?.trim() ?? '';
          if (profiles == null || factory == null || profileId.isEmpty) {
            throw StateError('SSH search is not configured');
          }
          final profile = await profiles.findById(profileId);
          if (profile == null) {
            throw StateError('SSH profile not found: $profileId');
          }
          final client = await factory.clientForStorage(profile);
          final command = HostShellArgv.command(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
          );
          final session = await client.execute(command);
          return SshProcessRunHandle(session);
        };
    }
  }

  static Future<ProcessRunHandle> _defaultLocalSpawner({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    final cwd = workingDirectory.trim();
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: cwd.isEmpty ? null : cwd,
    );
    return _LocalProcessRunHandle(process);
  }
}

/// [ProcessRunHandle] over a local [Process] (the executor's own handle is
/// private; this one stays local to the search service).
class _LocalProcessRunHandle implements ProcessRunHandle {
  _LocalProcessRunHandle(this._process);

  final Process _process;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  void kill() => _process.kill();
}
