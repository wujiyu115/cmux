import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cubits/app_bootstrap_cubit.dart';
import 'app_data_bootstrap.dart';
import '../cubits/app_update_cubit.dart';
import '../cubits/agent_attention_cubit.dart';
import '../cubits/chat_cubit.dart';
import '../services/agent_status/agent_status_http_handler.dart';
import '../services/agent_status/agent_status_seat_lookup.dart';
import '../services/agent_status/agent_status_gateway.dart';
import '../services/agent_status/claude_hook_installer.dart';
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
import '../cubits/github_account_cubit.dart';
import '../config/github_oauth_config.dart';
import '../models/runtime_target.dart';
import '../models/ssh_profile.dart';
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
import '../services/pairing/device_registry.dart';
import '../services/pairing/lan_pairing_server.dart';
import '../services/pairing/pairing_crypto.dart';
import '../services/pairing/pairing_workspace_index.dart';
import '../services/pairing/session_catalog.dart';
import '../models/app_session.dart';
import '../models/workspace.dart';
import '../repositories/user_terminal_theme_repository.dart';
import '../router/app_router.dart';
import '../services/storage/app_storage.dart';
import '../services/perf/live_perf_driver.dart';
import '../services/home_workspace/home_workspace_ui_cache.dart';
import '../services/cli/toolchain_executable_discovery.dart';
import '../services/commands/command_bus.dart';
import '../services/commands/layout_command_registrar.dart';
import '../services/commands/run_command_registrar.dart';
import '../services/commands/session_command_registrar.dart';
import '../services/commands/shortcuts_ui_commands.dart';
import '../services/commands/workspace_search_command_registrar.dart';
import '../pages/home_workspace/workspace_chrome_commands.dart';
import '../services/app/connection_mode_service.dart';
import '../services/storage/runtime_context_resolver.dart';
import '../services/storage/runtime_context_registry.dart';
import '../services/storage/home_target_controller.dart';
import '../services/storage/workspace_directory_picker.dart';
import '../services/storage/home_target_store.dart';
import '../services/storage/runtime_target_registry.dart';
import '../services/storage/targets_repository.dart';
import '../services/notification/notification_recorder.dart';
import '../services/notification/terminal_idle_notification_service.dart';
import '../services/terminal/command_log_sink.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/github/github_credentials_store.dart';
import '../services/github/github_device_flow_auth.dart';
import '../services/github/github_user_client.dart';
import '../services/ssh/ssh_client_factory.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ssh/ssh_connection_events.dart';
import '../widgets/ssh/ssh_host_key_prompt_dialog.dart';
import '../services/ssh/ssh_profile_connection_coordinator.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../services/file_tree/workspace_file_tree_store.dart';
import '../services/git/git_repo_store.dart';
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
    required this.appUpdateCubit,
    required this.sshProfileCubit,
    required this.sshConnectionCubit,
    required this.githubCredentialsStore,
    required this.githubAccountCubit,
    required this.appSettings,
    required this.reinstallStorageContext,
    required this.bootstrapAppData,
    required this.homeWorkspaceUiCache,
    required this.commandBus,
    required this.shortcutCubit,
    required this.workspaceChromeCommands,
    required this.runCommandHost,
    required this.workspaceSearchHost,
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
  final AppUpdateCubit appUpdateCubit;
  final SshProfileCubit sshProfileCubit;
  final SshConnectionCubit sshConnectionCubit;
  final GithubCredentialsStore githubCredentialsStore;
  final GithubAccountCubit githubAccountCubit;
  final AppSettingsRepository appSettings;
  final Future<void> Function() reinstallStorageContext;
  final Future<void> Function() bootstrapAppData;
  final CommandBus commandBus;
  final ShortcutCubit shortcutCubit;
  final WorkspaceChromeCommands workspaceChromeCommands;
  final RunCommandHost runCommandHost;
  final WorkspaceSearchHost workspaceSearchHost;
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
  void boot(String phase) =>
      appLogger.i('[boot] +${bootSw.elapsedMilliseconds}ms $phase');

  boot('start');
  final documentsFuture =
      defaultWorkspaceDirectoryFuture ??
      DefaultWorkspaceDirectory.resolve(preferences: preferences);
  final appSettings = SharedPrefsAppSettingsRepository(preferences);
  final sessionPreferencesCubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(preferences),
  );
  if (!Platform.isAndroid) {
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

  final githubCredentialsStore = GithubCredentialsStore(
    kv: const FlutterSecureKeyValueStore(),
  );
  final githubDeviceFlow = githubDeviceFlowAvailable
      ? GithubDeviceFlowAuth(clientId: githubOauthClientId)
      : null;
  final githubAccountCubit = GithubAccountCubit(
    store: githubCredentialsStore,
    deviceFlow: githubDeviceFlow,
    openUrl: (uri) async {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw StateError('Could not launch $uri');
    },
    fetchLogin: (token) => GithubUserClient().fetchLogin(token: token),
    deviceFlowAvailable: githubDeviceFlowAvailable,
  );
  unawaited(githubAccountCubit.hydrate());

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
  final workspaceSearchHost = WorkspaceSearchHost();
  final uiZoomBaseline = UiZoomBaseline();
  registerShortcutsUiCommands(commandBus);
  registerCommandPaletteCommand(commandBus);
  registerRunCommands(commandBus, runCommandHost);
  registerWorkspaceSearchCommands(commandBus, workspaceSearchHost);

  final transportFactory = TerminalTransportFactory(
    sshProfileRepository: sshProfileRepo,
    sshCredentialStore: sshCredentialStore,
    sshKnownHostRepository: sshKnownHostRepo,
    sshClientFactory: sshClientFactory,
  );

  final workspaceShellConnector = WorkspaceShellConnector(
    transportFactory: transportFactory,
    sshProfileRepository: sshProfileRepo,
    sshUseLoginShell: () =>
        sessionPreferencesCubit.state.preferences.sshUseLoginShell,
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

  final agentStatusGateway = AgentStatusGateway();
  await agentStatusGateway.ensureStarted();

  // Install the shared Claude lifecycle hook once (idempotent, best-effort):
  // additively merges gateway-forwarding entries into the user's
  // ~/.claude/settings.json and drops the global forwarder script under
  // <teampilotRoot>/agent-hooks/. Panes stamp seat identity env at connect;
  // the hook reads it at run time (see claude_hook_installer.dart).
  unawaited(
    ClaudeHookInstaller.forEnvironment(
      appDataRoot: AppStorage.appDataRoot,
    )?.install() ??
        Future<void>.value(),
  );

  final agentAttentionCubit = AgentAttentionCubit();
  final agentStatusSeatLookup = AgentStatusSeatLookup();
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
  ).start();

  // Turn agent lifecycle edges (done / interrupted / waiting) reported by the
  // Claude status hook into OS + in-app notifications. Foreground the active
  // chat tab is watching is suppressed; attribution names its workspace.
  AgentAttentionNotificationService(
    attention: agentAttentionCubit,
    isForegroundSeat: (sessionId, memberId) {
      final s = chatCubit.state;
      return s.activeSessionId == sessionId;
    },
    resolveAttribution: (sessionId, memberId) {
      final s = chatCubit.state;
      final session = s.sessions
          .where((e) => e.sessionId == sessionId)
          .firstOrNull;
      if (session == null) return null;
      final label = s.workspaces
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
    readMarkdownOpenMode: () =>
        layoutCubit.state.preferences.markdownOpenMode,
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
  if (isPairingHost) {
    final pairingKeyStore = SecurePairingKeyStore(
      const FlutterSecureKeyValueStore(),
    );
    final pairingSettings = SharedPrefsPairingSettingsRepository(preferences);
    final storedKey = await pairingKeyStore.loadStaticPrivateKey();
    final PairingKeyPair hostStaticKey;
    if (storedKey == null) {
      hostStaticKey = PairingKeyPair.generate();
      await pairingKeyStore.saveStaticPrivateKey(hostStaticKey.privateKeyB64);
    } else {
      hostStaticKey = PairingKeyPair.fromPrivateBytes(
        PairingCrypto.unb64u(storedKey),
      );
    }
    final deviceRegistry = DeviceRegistry(pairingKeyStore);
    final sessionCatalog = SessionCatalog()
      ..addSource(() => _workspaceCatalogEntries(workspaceTerminalRegistry));
    // Push `session.changed` to mirrored phones whenever terminal panes open or
    // close. The registry lives for the app's lifetime, so this listener is
    // intentionally never detached.
    workspaceTerminalRegistry.changes.addListener(sessionCatalog.notifyChanged);
    // Every workspace on disk, so the phone can list (and open a terminal in)
    // workspaces that currently have nothing running.
    Future<List<PairingWorkspaceInfo>> pairingWorkspaceIndex() async {
      final workspaces = await sessionRepo.loadWorkspacesIndex();
      return [
        for (final workspace in workspaces)
          PairingWorkspaceInfo(
            workspaceId: workspace.workspaceId,
            title: workspace.effectiveDisplay,
          ),
      ];
    }

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
        return PairingActivationResult(
          catalogId: PairedSessionRef.paneCatalogId(paneId),
        );
      }
      final entry = await resolvedShellLauncher.openDefaultShellForWorkspace(
        request.workspaceId,
      );
      if (entry == null) return null;
      return PairingActivationResult(
        catalogId: PairedSessionRef.paneCatalogId(entry.id),
        // The phone asked for a specific dead pane and got a fresh terminal.
        fallback: paneId != null,
      );
    }

    LanPairingServer serverFactory() => LanPairingServer(
      hostStaticKey: hostStaticKey,
      registry: deviceRegistry,
      catalog: sessionCatalog,
      hostName: Platform.localHostname,
      workspaceIndex: pairingWorkspaceIndex,
      activator: pairingActivate,
    );
    pairingHostCubit = PairingHostCubit(
      settings: pairingSettings,
      registry: deviceRegistry,
      serverFactory: serverFactory,
    );
    unawaited(pairingHostCubit.init());
  }

  // --- Pairing client (mobile only) -----------------------------------------
  // Pure LAN mirror/control client; never binds a server. Desktop skips this.
  PairingClientCubit? pairingClientCubit;
  if (isPairingClient) {
    final pairingSettings = SharedPrefsPairingSettingsRepository(preferences);
    pairingClientCubit = PairingClientCubit(settings: pairingSettings);
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
    appUpdateCubit: appUpdateCubit,
    sshProfileCubit: sshProfileCubit,
    sshConnectionCubit: sshConnectionCubit,
    githubCredentialsStore: githubCredentialsStore,
    githubAccountCubit: githubAccountCubit,
    appSettings: appSettings,
    reinstallStorageContext: reinstallStorageContext,
    bootstrapAppData: bootstrapAppData,
    homeWorkspaceUiCache: homeWorkspaceUiCache,
    commandBus: commandBus,
    shortcutCubit: shortcutCubit,
    workspaceChromeCommands: workspaceChromeCommands,
    runCommandHost: runCommandHost,
    workspaceSearchHost: workspaceSearchHost,
    uiZoomBaseline: uiZoomBaseline,
  );
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
