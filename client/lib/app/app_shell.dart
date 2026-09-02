import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cubits/app_bootstrap_cubit.dart';
import 'app_data_bootstrap.dart';
import '../cubits/app_update_cubit.dart';
import '../cubits/agent_attention_cubit.dart';
import '../cubits/chat_cubit.dart';
import '../services/agent_status/agent_status_http_handler.dart';
import '../services/agent_status/agent_attention_state.dart';
import '../services/agent_status/agent_status_seat_lookup.dart';
import '../services/agent_status/agent_status_gateway.dart';
import '../services/agent_status/agent_hook_install_service.dart';
import '../services/notification/agent_attention_notification_service.dart';
import '../services/editor_platform/editor_platform.dart';
import '../cubits/notification_cubit.dart';
import '../cubits/command_log_cubit.dart';
import '../cubits/shortcut_cubit.dart';
import '../cubits/editor_cubit.dart';
import '../cubits/workbench/workbench_cubit.dart';
import '../services/workbench/workbench_editor_opener.dart';
import '../services/workbench/workbench_shell_launcher.dart';
import '../services/workbench/workbench_strip_navigator.dart';
import '../services/editor/markdown_view_mode_store.dart';
import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/workspace_groups_cubit.dart';
import '../cubits/workspace_tools_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../cubits/ssh_connection_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../models/runtime_target.dart';
import '../models/ssh_profile.dart';
import '../models/workspace_folder.dart';
import '../models/workspace_topology.dart';
import '../services/app/boot_progress.dart';
import '../services/app/boot_splash.dart';
import '../utils/ui/yield_ui_frame.dart';
import '../l10n/app_localizations.dart';
import '../pages/system/app_bootstrap_loading_page.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/layout_repository.dart';
import '../repositories/session_preferences_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_known_host_repository.dart';
import '../repositories/ssh_profile_repository.dart';
import '../repositories/pairing_key_store.dart';
import '../repositories/pairing_settings_repository.dart';
import '../cubits/pairing_client_cubit.dart';
import '../cubits/pairing_host_cubit.dart';
import '../services/app/platform_utils.dart';
import '../services/io/filesystem.dart';
import '../services/pairing/agent_notice_message.dart';
import '../services/pairing/device_registry.dart';
import '../services/pairing/lan_pairing_server.dart';
import '../services/pairing/pairing_crypto.dart';
import '../services/pairing/pairing_host_dir_browser.dart';
import '../services/pairing/pairing_git_view.dart';
import '../services/pairing/filesystem_upload_target.dart';
import '../services/pairing/pairing_upload_target.dart';
import '../services/pairing/pairing_workspace_index.dart';
import '../services/pairing/session_catalog.dart';
import '../repositories/user_terminal_theme_repository.dart';
import '../router/app_router.dart';
import '../services/storage/app_storage.dart';
import '../services/perf/live_perf_driver.dart';
import '../services/home_workspace/home_workspace_ui_cache.dart';
import '../services/cli/toolchain_executable_discovery.dart';
import '../services/commands/command_bus.dart';
import '../services/commands/layout_command_registrar.dart';
import '../services/commands/quick_open_command_registrar.dart';
import '../services/commands/run_command_registrar.dart';
import '../services/commands/session_command_registrar.dart';
import '../services/commands/shortcuts_ui_commands.dart';
import '../pages/home_workspace/workspace_chrome_commands.dart';
import '../pages/home_workspace/home_workspace_route.dart';
import '../services/app/connection_mode_service.dart';
import '../services/storage/runtime_context.dart';
import '../services/storage/runtime_context_resolver.dart';
import '../services/storage/runtime_context_registry.dart';
import '../services/storage/home_target_controller.dart';
import '../services/storage/workspace_directory_picker.dart';
import '../services/storage/home_target_store.dart';
import '../services/storage/runtime_target_registry.dart';
import '../services/storage/targets_repository.dart';
import '../cubits/bark_push_cubit.dart';
import '../repositories/bark_push_repository.dart';
import '../services/notification/bark_push_dispatcher.dart';
import '../services/notification/bark_push_sender.dart';
import '../services/notification/mobile_agent_notice_presenter.dart';
import '../services/notification/notification_recorder.dart';
import '../services/notification/terminal_idle_notification_service.dart';
import '../services/terminal/command_log_sink.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/ssh/ssh_client_factory.dart';
import '../services/ssh/ssh_connection_events.dart';
import '../widgets/ssh/ssh_host_key_prompt_dialog.dart';
import '../services/ssh/ssh_profile_connection_coordinator.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../services/file_tree/workspace_file_tree_store.dart';
import '../services/git/git_repo_store.dart';
import '../services/git/git_service.dart';
import '../models/git_status.dart';
import '../services/workspace/workspace_tools_scope_registry.dart';
import '../services/workspace/workspace_run_registry.dart';
import '../services/run/workspace_run_platform_factory.dart';
import '../services/workspace/workspace_worktree_registry.dart';
import '../services/terminal/workspace_shell_connector.dart';
import '../services/terminal/workspace_terminal_registry.dart';
import '../services/terminal/workspace_terminal_run_service.dart';
import '../services/terminal/workspace_terminal_session_ops.dart';
import '../theme/terminal/user_terminal_theme_registry.dart';
import '../utils/logging/logger.dart';
import 'ui_zoom_baseline.dart';

/// Localized copy read from the live router context, for strings raised outside
/// any widget tree (the Bark test push). Null during startup / teardown, when
/// there is no context to localize against — callers fall back to English rather
/// than showing a placeholder.
AppLocalizations? _l10nOrNull() {
  final context = appRouter.routerDelegate.navigatorKey.currentContext;
  if (context == null || !context.mounted) return null;
  return Localizations.of<AppLocalizations>(context, AppLocalizations);
}

/// Fully wired app dependencies produced after async bootstrap.
class AppShell {
  AppShell({
    required this.homeTargetController,
    required this.directoryPicker,
    this.pairingHostCubit,
    this.pairingClientCubit,
    required this.chatCubit,
    required this.agentAttentionCubit,
    required this.agentStatusSeatLookup,
    required this.notificationCubit,
    required this.commandLogCubit,
    required this.editorCubit,
    required this.workbenchCubit,
    required this.workbenchEditorOpener,
    required this.workbenchShellLauncher,
    required this.sessionRepo,
    required this.sshProfileRepo,
    required this.sshCredentialStore,
    required this.sshKnownHostRepo,
    required this.transportFactory,
    required this.workspaceTerminalRegistry,
    required this.workspaceShellConnector,
    required this.workspaceTerminalSessionOps,
    required this.workspaceTerminalRunService,
    required this.gitRepoStore,
    required this.workspaceFileTreeStore,
    required this.workspaceWorktreeRegistry,
    required this.workspaceToolsScopeRegistry,
    required this.workspaceRunRegistry,
    required this.sshClientFactory,
    required this.sshProfileConnectionCoordinator,
    required this.connectionModeService,
    required this.configCubit,
    required this.layoutCubit,
    required this.workspaceGroupsCubit,
    required this.workspaceToolsCubit,
    required this.sessionPreferencesCubit,
    required this.barkPushCubit,
    required this.appUpdateCubit,
    required this.sshProfileCubit,
    required this.sshConnectionCubit,
    required this.appSettings,
    required this.reinstallStorageContext,
    required this.bootstrapAppData,
    required this.homeWorkspaceUiCache,
    required this.commandBus,
    required this.shortcutCubit,
    required this.workspaceChromeCommands,
    required this.runCommandHost,
    required this.quickOpenHost,
    required this.uiZoomBaseline,
  });
  final HomeWorkspaceUiCache homeWorkspaceUiCache;
  final HomeTargetController homeTargetController;
  final WorkspaceDirectoryPicker directoryPicker;

  /// Desktop LAN pairing host; null on mobile (pure client) platforms.
  final PairingHostCubit? pairingHostCubit;

  /// Mobile pairing client; null on desktop (host) platforms.
  final PairingClientCubit? pairingClientCubit;
  final ChatCubit chatCubit;
  final AgentAttentionCubit agentAttentionCubit;
  final AgentStatusSeatLookup agentStatusSeatLookup;
  final NotificationCubit notificationCubit;
  final CommandLogCubit commandLogCubit;
  final EditorCubit editorCubit;
  final WorkbenchCubit workbenchCubit;
  final WorkbenchEditorOpener workbenchEditorOpener;
  final WorkbenchShellLauncher workbenchShellLauncher;
  final SessionRepository sessionRepo;
  final SshProfileRepository sshProfileRepo;
  final SshCredentialStore sshCredentialStore;
  final SshKnownHostRepository sshKnownHostRepo;
  final TerminalTransportFactory transportFactory;
  final WorkspaceTerminalRegistry workspaceTerminalRegistry;
  final WorkspaceShellConnector workspaceShellConnector;
  final WorkspaceTerminalSessionOps workspaceTerminalSessionOps;
  final WorkspaceTerminalRunService workspaceTerminalRunService;
  final GitRepoStore gitRepoStore;
  final WorkspaceFileTreeStore workspaceFileTreeStore;
  final WorkspaceWorktreeRegistry workspaceWorktreeRegistry;
  final WorkspaceToolsScopeRegistry workspaceToolsScopeRegistry;
  final WorkspaceRunRegistry workspaceRunRegistry;
  final SshClientFactory sshClientFactory;
  final SshProfileConnectionCoordinator sshProfileConnectionCoordinator;
  final ConnectionModeService connectionModeService;
  final ConfigCubit configCubit;
  final LayoutCubit layoutCubit;
  final WorkspaceGroupsCubit workspaceGroupsCubit;
  final WorkspaceToolsCubit workspaceToolsCubit;
  final SessionPreferencesCubit sessionPreferencesCubit;
  final BarkPushCubit barkPushCubit;
  final AppUpdateCubit appUpdateCubit;
  final SshProfileCubit sshProfileCubit;
  final SshConnectionCubit sshConnectionCubit;
  final AppSettingsRepository appSettings;
  final Future<void> Function() reinstallStorageContext;
  final Future<void> Function() bootstrapAppData;
  final CommandBus commandBus;
  final ShortcutCubit shortcutCubit;
  final WorkspaceChromeCommands workspaceChromeCommands;
  final RunCommandHost runCommandHost;
  final QuickOpenHost quickOpenHost;
  final UiZoomBaseline uiZoomBaseline;
}

Future<AppShell> buildAppShell({
  required SharedPreferences preferences,
  required String nativeAppDataPath,
  Future<String>? defaultWorkspaceDirectoryFuture,
  Future<void>? homeIndexPrefetchFuture,
  AppBootstrapCubit? bootstrapCubit,
}) async {
  final bootSw = Stopwatch()..start();
  // Mirrored to BootProgress as well as the log: on iOS the log file is
  // unreachable on a stock device, and the bootstrap gate is the only surface
  // that can say which stage a stalled startup is sitting on.
  void boot(String phase) {
    BootProgress.mark(phase);
    appLogger.i('[boot] +${bootSw.elapsedMilliseconds}ms $phase');
  }

  boot('start');
  final documentsFuture =
      defaultWorkspaceDirectoryFuture ??
      DefaultWorkspaceDirectory.resolve(preferences: preferences);
  final appSettings = SharedPrefsAppSettingsRepository(preferences);
  final sessionPreferencesCubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(preferences),
  );
  // Mobile never runs a local shell (Android/iOS are SSH-only), so probing the
  // device filesystem for toolchains would only burn boot time.
  if (hasDesktopWindow) {
    boot('scheduling toolchain discovery (background)');
    unawaited(() async {
      final toolchainPaths = await ToolchainExecutableDiscovery().locateLocal();
      sessionPreferencesCubit.mergeLocatedToolchains(toolchainPaths);
      appLogger.i(
        '[boot] toolchain discovery complete '
        '(${toolchainPaths.length} toolchain, background)',
      );
    }());
  }
  boot('loading session preferences and workspace directory');
  final parallel = await Future.wait<Object?>([
    sessionPreferencesCubit.load(),
    documentsFuture,
  ]);
  final defaultWorkspaceDirectory = parallel[1]! as String;
  boot('session preferences and workspace directory ready');

  final sshCredentialStore = const SecureSshCredentialStore(
    FlutterSecureKeyValueStore(),
  );
  // Bark push channel. Built here because it needs both the preferences and the
  // keychain store; the dispatcher is wired further down, once the pairing host
  // exists to answer "is a phone connected".
  final barkPushSender = BarkPushSender();
  final barkPushCubit = BarkPushCubit(
    repository: SharedPrefsBarkPushRepository(
      preferences: preferences,
      secureStore: const FlutterSecureKeyValueStore(),
    ),
    sender: barkPushSender,
    testTitle: () => _l10nOrNull()?.barkPushTestTitle ?? 'TeamPilot',
    testBody: () => _l10nOrNull()?.barkPushTestBody ?? 'Push channel works.',
  );
  unawaited(barkPushCubit.load());

  final sshKnownHostRepo = SharedPrefsSshKnownHostRepository(preferences);
  final sshConnectionEvents = SshConnectionEvents();
  final sshClientFactory = SshClientFactory(
    credentialStore: sshCredentialStore,
    knownHostRepository: sshKnownHostRepo,
    events: sshConnectionEvents,
    onHostKeyPrompt: showSshHostKeyPrompt,
  );

  // P1: the home target (the machine the control plane runs on) is the single
  // authority, stored device-local in HomeTargetStore. distro/profile are
  // encoded in the id; there is no connectionMode/windowsStorageBackend knob.
  final homeTargetStore = HomeTargetStore(preferences);
  RuntimeTarget homeTargetFromId(String id) => switch (runtimeKindOfId(id)) {
    RuntimeKind.ssh => RuntimeTarget.ssh(
      sshProfileIdOfId(id) ?? '',
      label: 'SSH',
    ),
    RuntimeKind.wsl => RuntimeTarget.wsl(wslDistroOfId(id) ?? ''),
    RuntimeKind.local => RuntimeTarget.local(),
  };
  // Stored id wins; otherwise platform default. Desktop home is always local
  // (Windows can pick wsl in the picker); Android with no stored ssh home falls
  // to local and is held at the create-profile gate until a home is chosen.
  var homeTarget = homeTargetFromId(homeTargetStore.load());
  RuntimeTarget defaultTargetResolver() => homeTarget;

  final sshProfileRepo = SshProfileRepository();
  late final SessionRepository sessionRepo;
  late final ChatCubit chatCubit;
  late final EditorCubit editorCubit;
  late final SessionLifecycleService sessionLifecycleService;
  late final ConnectionModeService connectionModeService;
  late final Future<void> Function() reinstallStorageContext;

  late final Future<void> Function() reloadAllAppData;

  late final SshProfileCubit sshProfileCubit;
  final homeWorkspaceUiCache = HomeWorkspaceUiCache();
  sshProfileCubit = SshProfileCubit(
    profileRepository: sshProfileRepo,
    credentialStore: sshCredentialStore,
    invalidateProfileConnection: sshClientFactory.disconnectProfile,
    onActiveProfileChanged: () async {
      await reinstallStorageContext();
      await reloadAllAppData();
    },
  );

  // P1: targets.json is a pure target catalog (no default/migrate); the home
  // target authority is the device-local homeTargetStore read above. The
  // registry is used by the picker UI to list selectable targets.
  final targetsRepo = TargetsRepository();
  SshProfile? sshProfileById(String id) =>
      sshProfileCubit.state.profiles.where((p) => p.id == id).firstOrNull;
  final runtimeTargetRegistry = RuntimeTargetRegistry(
    repo: targetsRepo,
    sshProfileRepo: sshProfileRepo,
    isWindows: Platform.isWindows,
    isAndroid: Platform.isAndroid,
  );

  // P2: de-singleton. One resolver + a per-target context registry. The home
  // context (control plane) is materialized once and pushed onto AppStorage;
  // work-plane contexts are resolved lazily per workspace target id.
  final runtimeContextResolver = RuntimeContextResolver(
    sshClientFactory: sshClientFactory,
    nativeAppDataPath: nativeAppDataPath,
    nativeHome:
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
    nativeCwd: defaultWorkspaceDirectory,
  );
  final runtimeContextRegistry = RuntimeContextRegistry(
    resolver: runtimeContextResolver,
    homeTarget: defaultTargetResolver(),
    sshProfileById: sshProfileById,
    onEvict: (targetId) async {
      final pid = sshProfileIdOfId(targetId);
      if (pid != null) sshClientFactory.disconnectProfile(pid);
    },
  );
  boot('installing home runtime context');
  final ensureHomeSw = Stopwatch()..start();
  await runtimeContextRegistry.ensureHome();
  boot('home runtime context ensured +${ensureHomeSw.elapsedMilliseconds}ms');
  AppStorage.bindHome(runtimeContextRegistry.home());
  boot(
    'home context installed '
    '(${AppStorage.context.mode}, home=${homeTarget.id}, '
    'root=${AppStorage.appDataRoot})',
  );

  // Persists the chosen home id, rebinds the registry home, and republishes it
  // on AppStorage.
  Future<void> setHomeTarget(String id) async {
    await homeTargetStore.save(id);
    homeTarget = homeTargetFromId(id);
    await runtimeContextRegistry.dispose(id);
    await runtimeContextRegistry.rebindHome(homeTarget);
    AppStorage.bindHome(runtimeContextRegistry.home());
  }

  connectionModeService = ConnectionModeService(
    defaultTargetResolver: defaultTargetResolver,
    hasSshProfiles: () => sshProfileCubit.state.hasProfiles,
  );

  // Re-resolve the home context (e.g. after an ssh profile's details change):
  // evict the cached context for the home id, rebind, republish.
  reinstallStorageContext = () async {
    await runtimeContextRegistry.dispose(defaultTargetResolver().id);
    await runtimeContextRegistry.rebindHome(defaultTargetResolver());
    AppStorage.bindHome(runtimeContextRegistry.home());
  };

  sessionLifecycleService = SessionLifecycleService(
    storageRootsResolver: () async => AppStorage.context,
    // P2: launch resolves the work-plane on the workspace's target machine.
    workContextResolver: runtimeContextRegistry.forTarget,
  );
  sessionRepo = SessionRepository();
  boot('prefetching home index snapshots');
  bootstrapCubit?.beginHomeIndex();
  final homeIndexPrefetch =
      homeIndexPrefetchFuture ??
      Future.wait([sessionRepo.loadWorkspacesIndex()]);
  final appUpdateCubit = AppUpdateCubit(settings: appSettings);
  final layoutCubit = LayoutCubit(repository: LayoutRepository(preferences));
  final workspaceGroupsCubit = WorkspaceGroupsCubit();
  unawaited(workspaceGroupsCubit.load());
  // User-imported terminal themes must be in memory before the first terminal
  // paints: `teampilotTerminalTheme` is synchronous and resolves imported ids
  // through this registry.
  await _loadUserTerminalThemes();
  final workspaceToolsCubit = WorkspaceToolsCubit();
  final workspaceTerminalRegistry = WorkspaceTerminalRegistry();
  final gitRepoStore = GitRepoStore();
  final workspaceFileTreeStore = WorkspaceFileTreeStore();
  final workspaceWorktreeRegistry = WorkspaceWorktreeRegistry();
  final workspaceToolsScopeRegistry = WorkspaceToolsScopeRegistry();
  final workspaceRunRegistry = WorkspaceRunRegistry(
    platformFactory: WorkspaceRunPlatformFactory(
      resolveWorkContext: sessionLifecycleService.resolveWorkContextForTargetId,
      sshProfileRepository: sshProfileRepo,
      sshClientFactory: sshClientFactory,
    ),
  );
  final configCubit = ConfigCubit();
  final commandBus = CommandBus();
  final shortcutCubit = ShortcutCubit();
  final workspaceChromeCommands = WorkspaceChromeCommands();
  final runCommandHost = RunCommandHost();
  final quickOpenHost = QuickOpenHost();
  final uiZoomBaseline = UiZoomBaseline();
  registerShortcutsUiCommands(commandBus);
  registerCommandPaletteCommand(commandBus);
  registerRunCommands(commandBus, runCommandHost);
  registerQuickOpenCommands(commandBus, quickOpenHost);

  final transportFactory = TerminalTransportFactory(
    sshProfileRepository: sshProfileRepo,
    sshCredentialStore: sshCredentialStore,
    sshKnownHostRepository: sshKnownHostRepo,
    sshClientFactory: sshClientFactory,
  );

  // Built before the connectors that stamp seat identity: workspace panes need
  // the bound loopback port at plan time, so the listener must already be up.
  // Mobile is a pure pairing/mirror client: it never runs a local agent CLI, so
  // the loopback listener would only ever reject. Keep the object (the seat
  // stamping sites are all `isStarted`-gated) and skip the bind.
  final agentStatusGateway = AgentStatusGateway();
  if (hasDesktopWindow) {
    await agentStatusGateway.ensureStarted();
  }
  final agentStatusSeatLookup = AgentStatusSeatLookup();
  final agentAttentionCubit = AgentAttentionCubit();
  // Agent-attention edges destined for paired phones. Owned here rather than by
  // the pairing stack so it survives LanPairingServer being rebuilt on every
  // enable toggle; never closed, like the registry listener further down.
  final agentNotices = StreamController<PairingAgentNotice>.broadcast();

  // `nativeAppDataPath` and not `AppStorage.appDataRoot`: with a WSL home target
  // the latter is already an in-distro POSIX path, and writing it through the
  // local filesystem would create `/home/<u>/…` on the Windows drive.
  final agentHookInstallService = AgentHookInstallService(
    hostAppDataRoot: nativeAppDataPath,
    resolveWslPaths: (distro) async {
      // forTarget caches per target id, which also sidesteps the single-slot
      // static cache in RuntimeContextResolver._queryWslHome.
      final ctx = await runtimeContextRegistry.forTarget(
        RuntimeTarget.wsl(distro),
      );
      return (home: ctx.home, appDataRoot: ctx.appDataRoot);
    },
  );

  final workspaceShellConnector = WorkspaceShellConnector(
    transportFactory: transportFactory,
    sshProfileRepository: sshProfileRepo,
    sshUseLoginShell: () =>
        sessionPreferencesCubit.state.preferences.sshUseLoginShell,
    agentStatusGateway: agentStatusGateway,
    agentStatusSeatLookup: agentStatusSeatLookup,
    agentAttentionCubit: agentAttentionCubit,
    onWslDistroLaunch: agentHookInstallService.ensureWslDistro,
  );
  // Terminal inject deps after connector: registry was created earlier.
  final workspaceTerminalSessionOps = WorkspaceTerminalSessionOps();
  final workspaceTerminalRunService = WorkspaceTerminalRunService();
  workspaceRunRegistry.setTerminalRunDeps(
    TerminalRunDeps(
      registry: workspaceTerminalRegistry,
      connector: workspaceShellConnector,
      ops: workspaceTerminalSessionOps,
      runService: workspaceTerminalRunService,
    ),
  );

  // Install the shared agent lifecycle hooks on the host (idempotent,
  // best-effort): additively merges gateway-forwarding entries into the user's
  // ~/.claude/settings.json, ~/.qoder/settings.json, and ~/.codex/hooks.json,
  // and drops the forwarder scripts under the host <teampilotRoot>/agent-hooks/.
  // Panes stamp seat identity env at connect; the hook reads it at run time
  // (see agent_hook_installer.dart). WSL distros are installed lazily on first
  // launch into them, via onWslDistroLaunch above. Skipped on mobile: there is
  // no local CLI to read the hooks, and when Android happens to set HOME it
  // would write junk into the app sandbox.
  if (hasDesktopWindow) {
    unawaited(agentHookInstallService.installHost());
  }

  agentStatusGateway.attachAgentStatusHandler(
    AgentStatusHttpHandler(
      attention: agentAttentionCubit,
      resolveCli: agentStatusSeatLookup.resolveCli,
      resolveSkipPermissions: agentStatusSeatLookup.resolveSkipPermissions,
    ),
  );

  chatCubit = ChatCubit(
    agentStatusGateway: agentStatusGateway,
    agentStatusSeatLookup: agentStatusSeatLookup,
    agentAttentionCubit: agentAttentionCubit,
    sessionRepository: sessionRepo,
    lifecycleService: sessionLifecycleService,
    layoutCubit: layoutCubit,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    cliExecutableResolver: sessionPreferencesCubit.resolveExecutable,
    transportFactory: transportFactory,
    sshProfileResolver: () => sshProfileCubit.state.selectedProfile,
    sshProfileById: sshProfileById,
    sshDefaultWorkingDirectoryResolver: () =>
        sessionPreferencesCubit.state.preferences.defaultSshWorkingDirectory,
    sshUseLoginShellResolver: () =>
        sessionPreferencesCubit.state.preferences.sshUseLoginShell,
    defaultTargetResolver: defaultTargetResolver,
    terminalScrollbackLinesResolver: () =>
        sessionPreferencesCubit.state.preferences.terminalScrollbackLines,
  );

  // Bound after [WorkbenchCubit] exists; togglePanel no-ops until then.
  WorkbenchShellLauncher? workbenchShellLauncher;
  registerLayoutCommands(
    commandBus,
    layoutCubit,
    uiZoomBaseline: () => uiZoomBaseline.value,
    onTogglePanel: () async {
      await workbenchShellLauncher?.focusOrCreateDefaultShell();
    },
  );

  final sshProfileConnectionCoordinator = SshProfileConnectionCoordinator(
    factory: sshClientFactory,
    events: sshConnectionEvents,
    profileResolver: sshProfileById,
    onDisconnect: (profileId, error, stackTrace) {
      appLogger.w(
        '[ssh] profile $profileId transport closed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    },
    onReconnectSessionPlane: chatCubit.reconnectSshProfile,
  );

  final sshConnectionCubit = SshConnectionCubit(
    factory: sshClientFactory,
    coordinator: sshProfileConnectionCoordinator,
    selectProfileOnConnect: Platform.isAndroid
        ? (id) => sshProfileCubit.selectProfile(id)
        : null,
  );

  final notificationCubit = NotificationCubit();
  final notificationBootstrap = notificationCubit.load();
  NotificationRecorder.install(notificationCubit);

  final commandLogCubit = CommandLogCubit();
  CommandLogSink.install(commandLogCubit);
  // Retention sweep first, so the window never lists a day about to be deleted.
  final commandLogBootstrap = commandLogCubit.applyRetention().then(
    (_) => commandLogCubit.load(),
  );
  // Terminal OSC notifications name their workspace; resolved lazily because
  // workspaces are still loading when the terminal registry is built.
  workspaceTerminalRegistry.workspaceLabelResolver = (workspaceId) =>
      chatCubit.state.workspaces
          .where((w) => w.workspaceId == workspaceId)
          .firstOrNull
          ?.effectiveDisplay ??
      '';

  // Poll embedded terminals for working → idle edges (agent turn finished) and
  // raise OS + in-app notifications, gated by the notifyOnSessionIdle setting.
  // Covers plain workspace/IDE shells; chat agent panes are covered by the
  // status-hook driven service below (disjoint surfaces — no double-fire).
  TerminalIdleNotificationService(
    registry: workspaceTerminalRegistry,
    // Panes whose agent reports through the status hook are notified
    // semantically by the service below — suppress the PTY-burst duplicate.
    // Keyed on "has actually reported", not "was stamped": every non-ssh pane
    // carries the env, but a pane running `npm build` must keep its idle notice.
    reportsAgentStatus: (paneId) {
      final seatId = WorkspaceShellConnector.seatIdFor(paneId);
      return agentAttentionCubit.state.seats.containsKey(
        agentSeatKey(sessionId: seatId, memberId: seatId),
      );
    },
  ).start();

  // Turn agent lifecycle edges (done / interrupted / waiting) reported by the
  // Claude status hook into OS + in-app notifications. Foreground the active
  // chat tab is watching is suppressed; attribution names its workspace.
  AgentAttentionNotificationService(
    attention: agentAttentionCubit,
    isForegroundSeat: (sessionId, memberId) {
      // Workspace-terminal seats are panes, not chat sessions: the user is
      // "watching" one when its workspace tab is active and it is the focused
      // pane. Not checked: whether the terminal panel is collapsed — same
      // assumption TerminalIdleNotificationService already makes.
      final paneId = WorkspaceShellConnector.paneIdOfSeat(sessionId);
      if (paneId != null) {
        final located = workspaceTerminalRegistry.locatePane(paneId);
        if (located == null) return false;
        final (group, _) = located;
        return chatCubit.tabStore.activeWorkspaceId == group.workspaceId &&
            group.activeId == paneId;
      }
      final s = chatCubit.state;
      return s.activeSessionId == sessionId;
    },
    resolveAttribution: (sessionId, memberId) {
      final s = chatCubit.state;
      final paneId = WorkspaceShellConnector.paneIdOfSeat(sessionId);
      if (paneId != null) {
        final located = workspaceTerminalRegistry.locatePane(paneId);
        if (located == null) return null;
        final (group, _) = located;
        final paneLabel =
            s.workspaces
                .where((w) => w.workspaceId == group.workspaceId)
                .firstOrNull
                ?.effectiveDisplay ??
            '';
        return AgentNoticeAttribution(
          title: group.paneAttribution(paneId),
          workspaceId: group.workspaceId,
          workspaceLabel: paneLabel,
          // Explicit: `ws:<paneId>` is not a session id, so the default
          // session-location composition would build a dead route. Carry the
          // pane id so the tap can select this pane's shell tab.
          location: HomeWorkspaceRoute.paneLocation(
            workspaceId: group.workspaceId,
            paneId: paneId,
          ),
        );
      }
      final session = s.sessions
          .where((e) => e.sessionId == sessionId)
          .firstOrNull;
      if (session == null) return null;
      final label =
          s.workspaces
              .where((w) => w.workspaceId == session.workspaceId)
              .firstOrNull
              ?.effectiveDisplay ??
          '';
      final sessionTitle = session.display.trim();
      return AgentNoticeAttribution(
        // Headline the session (task); fall back to the workspace name.
        title: sessionTitle.isNotEmpty ? sessionTitle : label,
        workspaceId: session.workspaceId,
        workspaceLabel: label,
      );
    },
    // Mirror every notice to paired phones. `catalogId` is stamped later, where
    // the SessionCatalog lives; published even when attribution is null (pane
    // not located) so the phone can still fall back to the localized kind title.
    onAgentNotice: (notice, attribution) {
      if (agentNotices.isClosed) return;
      agentNotices.add(
        PairingAgentNotice(
          kind: switch (notice.kind) {
            AgentNoticeKind.done => PairingAgentNoticeKind.done,
            AgentNoticeKind.interrupted => PairingAgentNoticeKind.interrupted,
            AgentNoticeKind.waiting => PairingAgentNoticeKind.waiting,
          },
          seatId: notice.sessionId,
          workspaceId: attribution?.workspaceId ?? '',
          workspaceLabel: attribution?.workspaceLabel.trim() ?? '',
          title: attribution?.title.trim() ?? '',
          atMs: notice.at.millisecondsSinceEpoch,
        ),
      );
    },
  ).start();

  boot('loading layout');
  await layoutCubit.load();
  await shortcutCubit.load();
  unawaited(notificationBootstrap);
  unawaited(commandLogBootstrap);
  boot('layout ready (home index prefetched in background)');
  applyWorkspaceEntryMode(
    layoutCubit.state.preferences.workspaceEntryMode,
    lastOpenedWorkspaceId: layoutCubit.state.preferences.lastOpenedWorkspaceId,
  );
  boot('buildAppShell complete');
  bootstrapCubit?.markShellReady();
  boot('buildAppShell shell ready');

  reloadAllAppData = () => AppDataBootstrap.reloadAll(
    boot: boot,
    sshProfileCubit: sshProfileCubit,
    chatCubit: chatCubit,
    sessionRepo: sessionRepo,
    layoutCubit: layoutCubit,
    isSshMode: connectionModeService.isSshMode,
    homeSshProfileId: defaultTargetResolver().sshProfileId,
    sshProfileExists: (id) => sshProfileById(id) != null,
    reinstallStorageContext: reinstallStorageContext,
  );

  Future<void> bootstrapAppData() async {
    await notificationBootstrap;
    final indexReady = bootstrapCubit?.state.homeIndexReady ?? false;
    if (!indexReady) {
      bootstrapCubit?.beginHomeIndex();
    }
    boot('bootstrapAppData start');
    if (!indexReady) {
      boot('awaiting home index snapshots');
      await homeIndexPrefetch;
      if (connectionModeService.isSshMode) {
        await AppDataBootstrap.bootstrapHomeIndex(
          boot: boot,
          sshProfileCubit: sshProfileCubit,
          chatCubit: chatCubit,
          sessionRepo: sessionRepo,
          layoutCubit: layoutCubit,
          isSshMode: connectionModeService.isSshMode,
          homeSshProfileId: defaultTargetResolver().sshProfileId,
          sshProfileExists: (id) => sshProfileById(id) != null,
          reinstallStorageContext: reinstallStorageContext,
        );
      } else {
        await AppDataBootstrap.hydrateNativeHomeIndex(
          boot: boot,
          chatCubit: chatCubit,
          sessionRepo: sessionRepo,
          layoutCubit: layoutCubit,
        );
      }
      bootstrapCubit?.markHomeIndexReady();
    }
    await yieldUiFrame();
    boot(
      'bootstrapAppData index ready '
      'workspaces=${chatCubit.state.workspaces.length} '
      '(sessions load on demand)',
    );
    await AppDataBootstrap.warmUiInteractive(
      boot: boot,
      layoutPreferences: layoutCubit.state.preferences,
    );
    bootstrapCubit?.beginWarmAuxiliary();
    await AppDataBootstrap.warmAuxiliaryData(
      boot: boot,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
    );
    final showOnboarding = await AppDataBootstrap.prepareInteractiveShell(
      boot: boot,
      appSettings: appSettings,
      sshProfileCubit: sshProfileCubit,
      homeWorkspaceUiCache: homeWorkspaceUiCache,
      workspaces: chatCubit.state.workspaces,
    );
    bootstrapCubit?.markAppReady(showOnboardingWizard: showOnboarding);
    LivePerfDriver.instance?.markAppReady();
    boot('bootstrapAppData complete');
  }

  editorCubit = EditorCubit();
  // Fire-and-forget: warm the common tree-sitter grammars so the first file
  // open paints colored instead of cold. Never blocks app start.
  unawaited(EditorPlatform.bootstrap());
  final workbenchCubit = WorkbenchCubit();
  final markdownViewModes = MarkdownViewModeStore();
  final workbenchEditorOpener = WorkbenchEditorOpener(
    editor: editorCubit,
    workbench: workbenchCubit,
    chat: chatCubit,
    markdownViewModes: markdownViewModes,
    readMarkdownOpenMode: () => layoutCubit.state.preferences.markdownOpenMode,
  );
  final resolvedShellLauncher = WorkbenchShellLauncher(
    workbench: workbenchCubit,
    chat: chatCubit,
    registry: workspaceTerminalRegistry,
    connector: workspaceShellConnector,
    layout: layoutCubit,
    sessionOps: workspaceTerminalSessionOps,
  );
  workbenchShellLauncher = resolvedShellLauncher;
  registerSessionCommands(
    commandBus,
    chatCubit,
    WorkbenchStripNavigator(workbench: workbenchCubit, chat: chatCubit),
    resolvedShellLauncher,
  );

  // P1: switching the home target persists the id, rebinds the home context,
  // then reinstalls + reloads all remote-backed app data (same chain the old
  // backend/profile switches used).
  Future<void> switchHomeTarget(String id) async {
    await setHomeTarget(id); // persists + rebinds home + republishes AppStorage
    await reloadAllAppData();
  }

  final homeTargetController = HomeTargetController(
    registry: runtimeTargetRegistry,
    current: defaultTargetResolver,
    switchTo: switchHomeTarget,
  );

  // Target-aware directory picker for workspace dialogs: resolves the chosen
  // target's filesystem (real SSH connect for ssh targets) and lists targets.
  final directoryPicker = WorkspaceDirectoryPicker(
    resolveContext: runtimeContextRegistry.forTarget,
    listTargets: () => runtimeTargetRegistry.listTargets(),
  );

  // --- Pairing host (desktop only) ------------------------------------------
  // Builds the LAN pairing stack behind the config toggle. The mobile client
  // never reaches here (isPairingHost is false on Android/iOS).
  PairingHostCubit? pairingHostCubit;
  final pairingHostIdentity = isPairingHost
      ? await _loadPairingHostIdentity()
      : null;
  if (pairingHostIdentity != null) {
    final pairingKeyStore = pairingHostIdentity.store;
    final hostStaticKey = pairingHostIdentity.key;
    final pairingSettings = SharedPrefsPairingSettingsRepository(preferences);
    final deviceRegistry = DeviceRegistry(pairingKeyStore);
    final sessionCatalog = SessionCatalog()
      ..addSource(() => _workspaceCatalogEntries(workspaceTerminalRegistry));
    // Push `session.changed` to mirrored phones whenever terminal panes open or
    // close. The registry lives for the app's lifetime, so this listener is
    // intentionally never detached.
    workspaceTerminalRegistry.changes.addListener(sessionCatalog.notifyChanged);
    // Stamp mirrorability where the catalog knowledge lives. A seat id for a
    // workspace pane IS its catalogId (`ws:<paneId>` on both sides), so this is
    // a pure lookup; chat-session seats and dead panes stay null and the phone
    // then notifies without offering navigation. `map` preserves isBroadcast, so
    // per-connection subscriptions keep working.
    final agentNoticeWire = agentNotices.stream.map(
      (notice) => sessionCatalog.resolve(notice.seatId) != null
          ? notice.withCatalogId(notice.seatId)
          : notice,
    );
    // Every workspace on disk, so the phone can list (and open a terminal in)
    // workspaces that currently have nothing running.
    Future<List<PairingWorkspaceInfo>> pairingWorkspaceIndex() async {
      final workspaces = await sessionRepo.loadWorkspacesIndex();
      return [
        for (final workspace in workspaces)
          PairingWorkspaceInfo(
            workspaceId: workspace.workspaceId,
            title: workspace.effectiveDisplay,
            groupId: workspace.groupId,
          ),
      ];
    }

    // Every workspace group on disk, so the phone can render workspaces folded
    // by group and offer them as create targets.
    Future<List<PairingGroupInfo>> pairingGroupIndex() async {
      return [
        for (final g in workspaceGroupsCubit.state.groups)
          PairingGroupInfo(id: g.id, name: g.name, order: g.order),
      ];
    }

    // Which machines the phone may bind a folder to — itself, its WSL distros,
    // its SSH profiles. Memoized: `workspace.list` is re-served on every
    // `session.changed` (the listener above), and listTargets() shells out to
    // `wsl.exe -l -q` on each call, so an un-cached provider would spawn a
    // subprocess per connected phone every time a terminal pane opens or closes.
    // A short TTL still lets a freshly added SSH profile show up without a
    // restart. Cheap by construction: listTargets reads config and enumerates
    // distros, it never connects — only RuntimeContextRegistry.forTarget does.
    DateTime? pairingTargetsCachedAt;
    var pairingTargetsCache = const <PairingTargetInfo>[];
    Future<List<PairingTargetInfo>> pairingTargetIndex() async {
      final cachedAt = pairingTargetsCachedAt;
      final now = DateTime.now();
      if (cachedAt != null &&
          now.difference(cachedAt) < const Duration(seconds: 30)) {
        return pairingTargetsCache;
      }
      final targets = await runtimeTargetRegistry.listTargets();
      pairingTargetsCache = [
        for (final target in targets)
          PairingTargetInfo(
            id: target.id,
            label: target.label,
            kind: target.kind.name,
          ),
      ];
      pairingTargetsCachedAt = now;
      return pairingTargetsCache;
    }

    // Rejects a target the desktop does not have. Not defensive boilerplate:
    // WorkspaceDirectoryPicker.targetById falls back to the *local* machine for
    // an id it does not know, so an id that disappeared between `workspace.list`
    // and now (an uninstalled distro, a deleted SSH profile) would silently
    // ensureDir a POSIX path onto the Windows disk — creating C:\home\me\proj —
    // and then persist the dead targetId, leaving a workspace whose terminal
    // dies on launch. Returns the id to act on; empty means "default plane".
    Future<String> pairingResolveTargetId(String? raw) async {
      final id = raw?.trim() ?? '';
      if (id.isEmpty || id == RuntimeTarget.localId) return id;
      final known = await pairingTargetIndex();
      if (!known.any((target) => target.id == id)) {
        throw ArgumentError('unknown runtime target: $id');
      }
      return id;
    }

    // The filesystem a phone-supplied target names. An empty id is a phone that
    // predates machine selection: keep the home plane so its behaviour is
    // unchanged.
    Future<Filesystem> pairingFilesystemFor(String targetId) async =>
        targetId.isEmpty
        ? AppStorage.fs
        : directoryPicker.filesystemFor(targetId);

    // Host-side directory browser: the phone picks an existing folder on one of
    // the desktop's machines to create a workspace over.
    final pairingDirBrowser = PairingHostDirBrowser(
      resolveTargetId: pairingResolveTargetId,
      filesystemFor: pairingFilesystemFor,
      homeFor: directoryPicker.homeFor,
      defaultLocalRoot: DefaultWorkspaceDirectory.resolveDefaultWorkspacePath,
    );

    // Create a workspace over the phone-picked folder; file it under a group
    // when one was chosen. `allowDuplicate` mirrors the desktop "New Workspace"
    // action (multiple workspaces may target one directory). Routed through
    // ChatCubit rather than the repository so the desktop chrome — which renders
    // `ChatCubit.state.workspaces` — shows the new workspace immediately instead
    // of only after a restart, and so a follow-up `pairingActivate` finds it.
    Future<String> pairingCreateWorkspace({
      required String folderPath,
      String? title,
      String? groupId,
      String? targetId,
    }) async {
      // Validate before touching disk, and create the directory on the machine
      // the folder claims to live on — not on the desktop's own.
      final resolvedTargetId = await pairingResolveTargetId(targetId);
      await (await pairingFilesystemFor(
        resolvedTargetId,
      )).ensureDir(folderPath);
      final workspaceId = await chatCubit.createWorkspace(
        [
          WorkspaceFolder(
            path: folderPath,
            // This one field is what makes the workspace's terminal open on that
            // machine: defaultSessionSpecFor resolves the runtime target from the
            // folder alone (workspace_terminal_session_spec.dart:81-95). No
            // defaultShell needed — pinning one would short-circuit that.
            targetId: resolvedTargetId.isEmpty
                ? WorkspaceFolder.localTargetId
                : resolvedTargetId,
          ),
        ],
        sessionRepo,
        display: title ?? '',
        allowDuplicate: true,
      );
      if (groupId != null && groupId.isNotEmpty) {
        await chatCubit.updateWorkspaceMetadata(
          sessionRepo,
          workspaceId,
          groupId: groupId,
        );
      }
      return workspaceId;
    }

    // Create a group through the cubit so the desktop sidebar refreshes too.
    Future<String> pairingCreateGroup(String name) =>
        workspaceGroupsCubit.addGroup(name);

    // Host-side activation: hand the phone a live pane to mirror. An already
    // running pane is reused; anything else opens this workspace's default
    // terminal, which is also how a workspace with nothing running becomes
    // mirrorable.
    Future<PairingActivationResult?> pairingActivate(
      PairingActivationRequest request,
    ) async {
      final paneId = request.paneId;
      if (paneId != null &&
          sessionCatalog.resolve(PairedSessionRef.paneCatalogId(paneId)) !=
              null) {
        // Surface the reused pane's workspace on the desktop too (no-op when
        // its tab is already open, or when no HomeShell is mounted).
        workspaceChromeCommands.openWorkspaceTab?.call(request.workspaceId);
        return PairingActivationResult(
          catalogId: PairedSessionRef.paneCatalogId(paneId),
        );
      }
      final entry = await resolvedShellLauncher.openDefaultShellForWorkspace(
        request.workspaceId,
      );
      if (entry == null) return null;
      // A phone can spin up a terminal in a workspace the desktop never opened;
      // open (and activate) that tab so the desktop renders the fresh pane
      // instead of silently running it headless.
      workspaceChromeCommands.openWorkspaceTab?.call(request.workspaceId);
      return PairingActivationResult(
        catalogId: PairedSessionRef.paneCatalogId(entry.id),
        // The phone asked for a specific dead pane and got a fresh terminal.
        fallback: paneId != null,
      );
    }

    // Which machine a mirrored pane's cwd lives on. Resolving it lives here
    // rather than in the pairing layer: this is the only place that has both the
    // session repository and the runtime-context registry.
    Future<RuntimeContext> pairingPaneContext(
      String workspaceId,
      String cwd,
    ) async {
      final workspaces = await sessionRepo.loadWorkspacesIndex();
      final workspace = workspaces
          .where((w) => w.workspaceId == workspaceId)
          .firstOrNull;
      final folders = workspace?.folders ?? const <WorkspaceFolder>[];
      // matchSubpaths so a pane launched in a subdirectory of a folder still
      // resolves to that folder's target.
      final targetId =
          targetIdForFolderPaths(folders, [cwd], matchSubpaths: true) ??
          (folders.isEmpty ? RuntimeTarget.localId : folders.first.targetId);
      return sessionLifecycleService.resolveWorkContextForTargetId(targetId);
    }

    // Phone → desktop media upload. Opens the destination up front (which is
    // what makes `no_target` land before a 512 MiB video crosses the LAN) and
    // hands back a target the receiver streams into.
    //
    // [cwd] only picks the *machine*: the bytes land in that machine's staging
    // directory, not in the pane's working directory, so an upload never appears
    // in the user's git status. The phone gets the absolute path back and quotes
    // it into the composer, so an agent can still be pointed at the file.
    Future<PairingUploadTarget> pairingUploadOpener({
      required String workspaceId,
      required String cwd,
      required String filename,
    }) async {
      final context = await pairingPaneContext(workspaceId, cwd);
      final filesystem = context.filesystem;
      return openFilesystemUploadTarget(
        filesystem: filesystem,
        directory: await uploadStagingDirectory(filesystem),
        filename: filename,
      );
    }

    // Phone → desktop "what changed". `GitService.forContext` already speaks
    // local / WSL / SSH, so the pane's machine is the only thing to resolve.
    //
    // The repository root is resolved explicitly rather than reusing the pane's
    // cwd: `GitFileChange.path` is relative to the root, and a pane sitting in a
    // subdirectory would otherwise have every diff path resolved against the
    // wrong base.
    Future<({GitService git, String root})?> pairingGitRepo(
      String workspaceId,
      String cwd,
    ) async {
      final context = await pairingPaneContext(workspaceId, cwd);
      final git = GitService.forContext(context);
      final root = await git.repoRoot(cwd);
      if (root == null || root.isEmpty) return null;
      return (git: git, root: root);
    }

    Future<PairingGitChanges> pairingGitChanges({
      required String workspaceId,
      required String cwd,
    }) async {
      final repo = await pairingGitRepo(workspaceId, cwd);
      if (repo == null) return PairingGitChanges.notARepository;
      final status = await repo.git.status(repo.root);
      if (!status.isRepository) return PairingGitChanges.notARepository;
      // Staged wins on a path present in both areas: the phone's list is "what
      // changed against HEAD", and for a file staged-added then edited again
      // that is an addition, not a modification. Dropping the duplicate matters
      // more than which letter it keeps — a partly-staged file is in both.
      final byPath = <String, GitFileChange>{};
      for (final change in [...status.staged, ...status.unstaged]) {
        byPath.putIfAbsent(change.path, () => change);
      }
      final paths = byPath.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return PairingGitChanges(
        isRepository: true,
        branch: status.branch ?? '',
        files: [
          for (final path in paths)
            PairingGitFile(
              path: path,
              badge: byPath[path]!.badge,
              untracked: byPath[path]!.kind == GitChangeKind.untracked,
            ),
        ],
      );
    }

    Future<String> pairingGitDiff({
      required String workspaceId,
      required String cwd,
      required String path,
      required bool untracked,
    }) async {
      final repo = await pairingGitRepo(workspaceId, cwd);
      if (repo == null) return '';
      return repo.git.diffAgainstHead(repo.root, path, untracked: untracked);
    }

    LanPairingServer serverFactory() => LanPairingServer(
      hostStaticKey: hostStaticKey,
      registry: deviceRegistry,
      catalog: sessionCatalog,
      hostName: Platform.localHostname,
      uploadOpener: pairingUploadOpener,
      workspaceIndex: pairingWorkspaceIndex,
      activator: pairingActivate,
      dirBrowser: pairingDirBrowser.browse,
      workspaceCreator: pairingCreateWorkspace,
      groupCreator: pairingCreateGroup,
      groupIndex: pairingGroupIndex,
      targetIndex: pairingTargetIndex,
      gitChanges: pairingGitChanges,
      gitDiff: pairingGitDiff,
      agentNotices: agentNoticeWire,
    );
    pairingHostCubit = PairingHostCubit(
      settings: pairingSettings,
      registry: deviceRegistry,
      serverFactory: serverFactory,
    );
    unawaited(pairingHostCubit.init());
  }

  // Bark delivery rides the same notice feed that paired phones do, so it is
  // already downstream of the `notifyOnSessionIdle` master switch. Deliberately
  // *not* gated on the pairing host running: push is the path that works when
  // nothing is connected, which includes a desktop with pairing turned off.
  final barkPushDispatcher = BarkPushDispatcher(
    sender: barkPushSender,
    target: barkPushCubit.target,
    // Read through the variable, not captured by value: on a client build there
    // is no host cubit at all, and on a host build this closure runs long after
    // bootstrap assigned it.
    hasConnectedPhone: () => pairingHostCubit?.hasConnectedPhone ?? false,
  );
  agentNotices.stream.listen(barkPushDispatcher.handle);

  // --- Pairing client (mobile only) -----------------------------------------
  // Pure LAN mirror/control client; never binds a server. Desktop skips this.
  PairingClientCubit? pairingClientCubit;
  if (isPairingClient) {
    final pairingSettings = SharedPrefsPairingSettingsRepository(preferences);
    // Host-pushed agent edges become local phone notifications, localized here
    // (not on the desktop) so the phone's own language wins.
    final agentNoticePresenter = MobileAgentNoticePresenter();
    // Android's Photo Picker needs no runtime permission and no manifest entry,
    // which is why AndroidManifest.xml has no READ_MEDIA_IMAGES / READ_MEDIA_VIDEO
    // — do not add them. The permission-based flow would mean a runtime dialog on
    // API 33+ and a Play data-safety declaration for whole-library access, for a
    // feature that only ever needs the one file the user picked. Devices without
    // Play services fall back to ACTION_GET_CONTENT, which still works.
    final imagePicker = ImagePickerPlatform.instance;
    if (imagePicker is ImagePickerAndroid) {
      imagePicker.useAndroidPhotoPicker = true;
    }
    pairingClientCubit = PairingClientCubit(
      settings: pairingSettings,
      onAgentNotice: agentNoticePresenter.show,
    );
    unawaited(pairingClientCubit.loadPairedDesktops());
    unawaited(pairingClientCubit.loadNetworkInfo());
  }

  return AppShell(
    homeTargetController: homeTargetController,
    directoryPicker: directoryPicker,
    pairingHostCubit: pairingHostCubit,
    pairingClientCubit: pairingClientCubit,
    chatCubit: chatCubit,
    agentAttentionCubit: agentAttentionCubit,
    agentStatusSeatLookup: agentStatusSeatLookup,
    notificationCubit: notificationCubit,
    commandLogCubit: commandLogCubit,
    editorCubit: editorCubit,
    workbenchCubit: workbenchCubit,
    workbenchEditorOpener: workbenchEditorOpener,
    workbenchShellLauncher: resolvedShellLauncher,
    sessionRepo: sessionRepo,
    sshProfileRepo: sshProfileRepo,
    sshCredentialStore: sshCredentialStore,
    sshKnownHostRepo: sshKnownHostRepo,
    transportFactory: transportFactory,
    workspaceTerminalRegistry: workspaceTerminalRegistry,
    workspaceShellConnector: workspaceShellConnector,
    workspaceTerminalSessionOps: workspaceTerminalSessionOps,
    workspaceTerminalRunService: workspaceTerminalRunService,
    gitRepoStore: gitRepoStore,
    workspaceFileTreeStore: workspaceFileTreeStore,
    workspaceWorktreeRegistry: workspaceWorktreeRegistry,
    workspaceToolsScopeRegistry: workspaceToolsScopeRegistry,
    workspaceRunRegistry: workspaceRunRegistry,
    sshClientFactory: sshClientFactory,
    sshProfileConnectionCoordinator: sshProfileConnectionCoordinator,
    connectionModeService: connectionModeService,
    configCubit: configCubit,
    layoutCubit: layoutCubit,
    workspaceGroupsCubit: workspaceGroupsCubit,
    workspaceToolsCubit: workspaceToolsCubit,
    sessionPreferencesCubit: sessionPreferencesCubit,
    barkPushCubit: barkPushCubit,
    appUpdateCubit: appUpdateCubit,
    sshProfileCubit: sshProfileCubit,
    sshConnectionCubit: sshConnectionCubit,
    appSettings: appSettings,
    reinstallStorageContext: reinstallStorageContext,
    bootstrapAppData: bootstrapAppData,
    homeWorkspaceUiCache: homeWorkspaceUiCache,
    commandBus: commandBus,
    shortcutCubit: shortcutCubit,
    workspaceChromeCommands: workspaceChromeCommands,
    runCommandHost: runCommandHost,
    quickOpenHost: quickOpenHost,
    uiZoomBaseline: uiZoomBaseline,
  );
}

/// The pairing host's keychain-backed store plus its static X25519 key.
typedef _PairingHostIdentity = ({PairingKeyStore store, PairingKeyPair key});

/// Loads the pairing host's static key, generating and persisting one on first
/// run.
///
/// Returns null when the keychain is unreachable — it can be locked, the user
/// can deny access, and on macOS the ad-hoc-signed build has no team-scoped
/// keychain entitlement at all. Pairing is optional and behind a config toggle,
/// so a keychain failure disables it rather than failing startup for the whole
/// app. A corrupt stored key lands here too, which leaves pairing off until it
/// is cleared by hand.
Future<_PairingHostIdentity?> _loadPairingHostIdentity() async {
  final store = SecurePairingKeyStore(const FlutterSecureKeyValueStore());
  try {
    final storedKey = await store.loadStaticPrivateKey();
    if (storedKey != null) {
      return (
        store: store,
        key: PairingKeyPair.fromPrivateBytes(PairingCrypto.unb64u(storedKey)),
      );
    }
    final generated = PairingKeyPair.generate();
    await store.saveStaticPrivateKey(generated.privateKeyB64);
    return (store: store, key: generated);
  } catch (error, stackTrace) {
    appLogger.w(
      '[pairing] keychain unavailable; LAN pairing host disabled',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}

/// Read-only projection of the workspace terminal registry into catalog entries.
List<SessionCatalogEntry> _workspaceCatalogEntries(
  WorkspaceTerminalRegistry registry,
) {
  final entries = <SessionCatalogEntry>[];
  for (final group in registry.groups) {
    for (final entry in group.entries) {
      if (!entry.session.isRunning) continue;
      entries.add(
        SessionCatalogEntry(
          PairedSessionRef(
            catalogId: PairedSessionRef.paneCatalogId(entry.id),
            title: entry.titleLabel.isEmpty ? entry.cwd : entry.titleLabel,
            subtitle: entry.cwd,
            workspaceId: group.workspaceId,
            paneId: entry.id,
          ),
          entry.session,
        ),
      );
    }
  }
  return entries;
}

/// Loads user-imported terminal themes into [UserTerminalThemeRegistry].
///
/// A failure here must not block startup: with an empty registry an imported
/// `terminalThemeMode` simply falls back to the adaptive scheme.
Future<void> _loadUserTerminalThemes() async {
  try {
    final themes = await UserTerminalThemeRepository().loadAll();
    UserTerminalThemeRegistry.instance.replaceAll(themes);
  } on Object catch (error, stackTrace) {
    appLogger.w(
      '[bootstrap] failed to load user terminal themes',
      error: error,
      stackTrace: stackTrace,
    );
    UserTerminalThemeRegistry.instance.clear();
  }
}

class TeamPilotBootstrap extends StatefulWidget {
  const TeamPilotBootstrap({
    super.key,
    required this.preferences,
    required this.nativeAppDataPath,
    required this.defaultWorkspaceDirectoryFuture,
    required this.homeIndexPrefetchFuture,
    required this.bootstrapCubit,
    required this.childBuilder,
  });

  final SharedPreferences preferences;
  final String nativeAppDataPath;
  final Future<String> defaultWorkspaceDirectoryFuture;
  final Future<void> homeIndexPrefetchFuture;
  final AppBootstrapCubit bootstrapCubit;
  final Widget Function(AppShell shell) childBuilder;

  @override
  State<TeamPilotBootstrap> createState() => _TeamPilotBootstrapState();
}

class _TeamPilotBootstrapState extends State<TeamPilotBootstrap> {
  AppShell? _shell;
  Object? _error;
  var _retrying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_start());
    });
  }

  Future<void> _start() async {
    final bootSw = Stopwatch()..start();
    try {
      appLogger.i('[boot] +0ms TeamPilotBootstrap starting buildAppShell');
      final shell = await buildAppShell(
        preferences: widget.preferences,
        nativeAppDataPath: widget.nativeAppDataPath,
        defaultWorkspaceDirectoryFuture: widget.defaultWorkspaceDirectoryFuture,
        homeIndexPrefetchFuture: widget.homeIndexPrefetchFuture,
        bootstrapCubit: widget.bootstrapCubit,
      );
      if (!mounted) return;
      await yieldUiFrame();
      await shell.bootstrapAppData();
      if (!mounted) return;
      appLogger.i(
        '[boot] +${bootSw.elapsedMilliseconds}ms bootstrap complete '
        'workspaces=${shell.chatCubit.state.workspaces.length}',
      );
      // Build the app UI first so it paints underneath the splash overlay.
      // Yield across SplashDeferredShell mount before fading the splash away.
      setState(() {
        _shell = shell;
        _error = null;
        _retrying = false;
      });
      await yieldUiFrame();
      await yieldUiFrame();
      await yieldUiFrame();
      await yieldUiFrame();
      if (!mounted) return;
      await completeBootSplashTransition();
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[boot] buildAppShell failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      await completeBootSplashTransition();
      if (!mounted) return;
      setState(() {
        _error = error;
        _retrying = false;
      });
    }
  }

  Future<void> _switchToNativeStorageAndRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    // Home target failed to install (e.g. WSL unavailable) — fall back to the
    // local device as home and retry bootstrap.
    await HomeTargetStore(widget.preferences).save(RuntimeTarget.localId);
    await _start();
  }

  bool get _canFallbackToNativeStorage {
    if (!Platform.isWindows || _error == null) return false;
    return runtimeKindOfId(HomeTargetStore(widget.preferences).load()) ==
        RuntimeKind.wsl;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                final l10n = AppLocalizations.of(context);
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.bootstrapStartupFailed(_error.toString())),
                      if (_canFallbackToNativeStorage) ...[
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _retrying
                              ? null
                              : _switchToNativeStorageAndRetry,
                          child: _retrying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.bootstrapUseNativeStorageInstead),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    final shell = _shell;
    if (shell == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AppBootstrapLoadingPage(),
      );
    }
    return widget.childBuilder(shell);
  }
}
