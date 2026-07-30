import '../../models/run/run_ui_intent.dart';
import '../../models/ssh_profile.dart';
import '../../models/workspace_folder.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../io/filesystem.dart';
import '../ssh/ssh_client_factory.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_context.dart';
import '../terminal/workspace_terminal_run_service.dart';
import 'launch_adapter_client.dart';
import 'launch_config_store.dart';
import 'launch_type_registry.dart';
import 'process_run_executor.dart';
import 'run_platform.dart';
import 'run_session_manager.dart';
import 'shell_script_launcher.dart';

/// [RunPlatform] plus the retained entry-closed listener tear-off for cleanup.
class CreatedWorkspaceRunPlatform {
  const CreatedWorkspaceRunPlatform({
    required this.platform,
    required this.onEntryClosed,
  });

  final RunPlatform platform;

  /// Same tear-off passed to [TerminalRunDepsResolver.addEntryClosedListener].
  final void Function(String entryId) onEntryClosed;
}

/// Builds a per-workspace [RunPlatform] (launch config store + built-in launch
/// types + session manager) scoped to one workspace tab.
class WorkspaceRunPlatformFactory {
  WorkspaceRunPlatformFactory({
    Filesystem? fs,
    Future<RuntimeContext> Function(String targetId)? resolveWorkContext,
    SshProfileRepository? sshProfileRepository,
    SshClientFactory? sshClientFactory,
    TerminalRunDepsResolver? terminalRunDeps,
  }) : _fs = fs,
       _resolveWorkContext = resolveWorkContext,
       _sshProfileRepository = sshProfileRepository,
       _sshClientFactory = sshClientFactory,
       terminalRunDeps = terminalRunDeps ?? TerminalRunDepsResolver();

  final Filesystem? _fs;
  final Future<RuntimeContext> Function(String targetId)? _resolveWorkContext;
  final SshProfileRepository? _sshProfileRepository;
  final SshClientFactory? _sshClientFactory;

  /// Filled after [WorkspaceShellConnector] exists (see app_shell bootstrap).
  final TerminalRunDepsResolver terminalRunDeps;

  Filesystem get _filesystem => _fs ?? AppStorage.fs;

  Future<CreatedWorkspaceRunPlatform> create({
    required String workspaceId,
    void Function(RunUiIntent intent)? emitUiIntent,
  }) async {
    final registry = LaunchTypeRegistry.withBuiltIns();
    final adapterClient = LaunchAdapterClient(
      extensionPathResolver: (_) => '',
    );
    final store = LaunchConfigStore(
      io: TargetAwareLaunchConfigIo(resolveFilesystem: _filesystemForTarget),
    );
    final executor = ProcessRunExecutor(sshSpawner: _sshSpawner);
    RunSessionManager? sessionManagerRef;
    final sessionManager = RunSessionManager(
      executor: RunShellScriptLauncher(
        workspaceId: workspaceId,
        terminalRunDeps: terminalRunDeps,
        processExecutor: executor,
        emitUiIntent: emitUiIntent,
        registerTerminalSession: ({
          required String entryId,
          required String sessionId,
        }) {
          sessionManagerRef?.registerTerminalSession(
            entryId: entryId,
            sessionId: sessionId,
          );
        },
      ),
      launchAdapterClient: adapterClient,
      resolveLaunchType: registry.get,
    );
    sessionManagerRef = sessionManager;
    // Retain the tear-off so removeScope/dispose can remove by identity.
    final onEntryClosed = sessionManager.markExitedForTerminalEntry;
    terminalRunDeps.addEntryClosedListener(onEntryClosed);
    final platform = RunPlatform(
      store: store,
      registry: registry,
      sessionManager: sessionManager,
      adapterClient: adapterClient,
    );
    return CreatedWorkspaceRunPlatform(
      platform: platform,
      onEntryClosed: onEntryClosed,
    );
  }

  Future<Filesystem> _filesystemForTarget(String targetId) async {
    final resolver = _resolveWorkContext;
    if (resolver == null ||
        targetId == WorkspaceFolder.localTargetId ||
        targetId.trim().isEmpty) {
      return _filesystem;
    }
    final ctx = await resolver(targetId);
    return ctx.filesystem;
  }

  Future<ProcessRunHandle> _sshSpawner({
    required String sshProfileId,
    required String shellCommand,
  }) async {
    final profiles = _sshProfileRepository;
    final factory = _sshClientFactory;
    if (profiles == null || factory == null) {
      throw StateError('SSH process execution is not configured');
    }
    final SshProfile? profile = await profiles.findById(sshProfileId);
    if (profile == null) {
      throw StateError('SSH profile not found for this run target');
    }
    final client = await factory.clientForStorage(profile);
    final session = await client.execute(shellCommand);
    return SshProcessRunHandle(session);
  }

}
