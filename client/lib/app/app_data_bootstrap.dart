import 'dart:async';

import '../cubits/chat_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../models/layout_preferences.dart';
import '../models/workspace.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/session_repository.dart';
import '../router/app_router.dart';
import '../services/app/ui_interactive_warmup.dart';
import '../services/workspace/workspace_icon_warmup.dart';
import '../services/home_workspace/home_workspace_ui_cache.dart';
import '../utils/ui/yield_ui_frame.dart';
import '../services/workspace/default_workspace_service.dart';
import '../utils/logging/logger.dart';

typedef BootLog = void Function(String message);

/// Orchestrates app-data loading: workspace index first, everything else warm.
abstract final class AppDataBootstrap {
  AppDataBootstrap._();

  /// Hydrates launch profiles + workspace index before the home shell is shown.
  static Future<void> hydrateNativeHomeIndex({
    required BootLog boot,
    required ChatCubit chatCubit,
    required SessionRepository sessionRepo,
    required LayoutCubit layoutCubit,
  }) async {
    await Future.wait([
      _timed(
        boot,
        'loadWorkspaceIndex',
        () => chatCubit.loadWorkspaceIndex(sessionRepo),
      ),
    ]);
    await _reapplyWorkspaceEntry(
      boot: boot,
      layoutCubit: layoutCubit,
      chatCubit: chatCubit,
    );

    boot(
      'hydrateNativeHomeIndex index ready '
      'workspaces=${chatCubit.state.workspaces.length} '
    );

    await _seedDefaultWorkspace(
      boot: boot,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      layoutCubit: layoutCubit,
    );
  }

  static Future<void> _seedDefaultWorkspace({
    required BootLog boot,
    required ChatCubit chatCubit,
    required SessionRepository sessionRepo,
    required LayoutCubit layoutCubit,
  }) async {
    await _ensureDefaultWorkspace(
      boot,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
    );
    await _reapplyWorkspaceEntry(
      boot: boot,
      layoutCubit: layoutCubit,
      chatCubit: chatCubit,
    );
    boot(
      'defaultWorkspaceSeed complete '
      'workspaces=${chatCubit.state.workspaces.length}',
    );
  }

  static Future<void> _reapplyWorkspaceEntry({
    required BootLog boot,
    required LayoutCubit layoutCubit,
    required ChatCubit chatCubit,
  }) async {
    final preferences = layoutCubit.state.preferences;
    reapplyWorkspaceEntryFromPreferences(
      preferences,
      knownWorkspaceIds: {
        for (final workspace in chatCubit.state.workspaces)
          workspace.workspaceId,
      },
    );

    if (preferences.workspaceEntryMode == WorkspaceEntryMode.lastWorkspace) {
      final workspaceId = preferences.lastOpenedWorkspaceId.trim();
      if (workspaceId.isNotEmpty &&
          chatCubit.state.workspaces.any((w) => w.workspaceId == workspaceId)) {
        await _timed(
          boot,
          'prefetchSessionsForEntryWorkspace',
          () => chatCubit.ensureSessionsForWorkspace(workspaceId),
        );
      }
    }
  }

  /// SSH home reinstall + parallel team/workspace index — blocks until the home
  /// shell can list workspaces and identities. Sessions load on demand.
  static Future<void> bootstrapHomeIndex({
    required BootLog boot,
    required SshProfileCubit sshProfileCubit,
    required ChatCubit chatCubit,
    required SessionRepository sessionRepo,
    required LayoutCubit layoutCubit,
    required bool isSshMode,
    required String? homeSshProfileId,
    required bool Function(String id) sshProfileExists,
    required Future<void> Function() reinstallStorageContext,
  }) async {
    final phaseSw = Stopwatch()..start();
    boot('bootstrapHomeIndex start');

    final sshLoad = sshProfileCubit.load(notifyActiveProfileChanged: false);

    if (isSshMode) {
      await sshLoad;
      boot('bootstrapHomeIndex ssh profiles loaded');
      if (homeSshProfileId != null && sshProfileExists(homeSshProfileId)) {
        boot('bootstrapHomeIndex reinstalling home storage context (ssh)');
        await reinstallStorageContext();
        boot('bootstrapHomeIndex home storage context reinstalled');
      }
      await Future.wait([
        _timed(
          boot,
          'loadWorkspaceIndex',
          () => chatCubit.loadWorkspaceIndex(sessionRepo),
        ),
      ]);
    } else {
      await Future.wait([
        _timed(
          boot,
          'loadWorkspaceIndex',
          () => chatCubit.loadWorkspaceIndex(sessionRepo),
        ),
      ]);
      unawaited(_timed(boot, 'sshProfiles', () => sshLoad));
    }

    await _reapplyWorkspaceEntry(
      boot: boot,
      layoutCubit: layoutCubit,
      chatCubit: chatCubit,
    );

    await _seedDefaultWorkspace(
      boot: boot,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      layoutCubit: layoutCubit,
    );

    boot(
      'bootstrapHomeIndex complete +${phaseSw.elapsedMilliseconds}ms '
      'workspaces=${chatCubit.state.workspaces.length} '
      'sessions=${chatCubit.state.sessions.length}',
    );
  }

  /// Auxiliary warm phase (post-index UI-frame yield point).
  static Future<void> warmAuxiliaryData({
    required BootLog boot,
    required ChatCubit chatCubit,
    required SessionRepository sessionRepo,
  }) async {
    final phaseSw = Stopwatch()..start();
    boot('warmAuxiliaryData start');
    await yieldUiFrame();
    boot('warmAuxiliaryData complete +${phaseSw.elapsedMilliseconds}ms');
    await yieldUiFrame();
  }

  /// Fonts, glyph cache, and terminal engine — time-sliced for spinner fluidity.
  static Future<void> warmUiInteractive({
    required BootLog boot,
    required LayoutPreferences layoutPreferences,
  }) async {
    await _timed(
      boot,
      'uiInteractive',
      () => UiInteractiveWarmup.run(layoutPreferences: layoutPreferences),
    );
    await yieldUiFrame();
  }

  /// SSH profiles, feature flags, and onboarding gate — must
  /// finish before the router mounts so no second spinner appears on entry.
  static Future<bool> prepareInteractiveShell({
    required BootLog boot,
    required AppSettingsRepository appSettings,
    required SshProfileCubit sshProfileCubit,
    required HomeWorkspaceUiCache homeWorkspaceUiCache,
    required List<Workspace> workspaces,
  }) async {
    final phaseSw = Stopwatch()..start();
    boot('prepareInteractiveShell start');

    await _timed(
      boot,
      'sshProfiles',
      () => sshProfileCubit.load(notifyActiveProfileChanged: false),
    );
    await yieldUiFrame();
    await _timed(boot, 'homeWorkspaceUi', homeWorkspaceUiCache.warm);
    await yieldUiFrame();
    await _timed(
      boot,
      'workspaceIcons',
      () => WorkspaceIconWarmup.warm(workspaces),
    );

    await yieldUiFrame();

    final showOnboarding = !(await appSettings.loadHasCompletedOnboarding());
    boot(
      'prepareInteractiveShell complete +${phaseSw.elapsedMilliseconds}ms '
      'showOnboarding=$showOnboarding',
    );
    return showOnboarding;
  }

  /// Full reload after home-target or SSH-profile switch.
  static Future<void> reloadAll({
    required BootLog boot,
    required SshProfileCubit sshProfileCubit,
    required ChatCubit chatCubit,
    required SessionRepository sessionRepo,
    required LayoutCubit layoutCubit,
    required bool isSshMode,
    required String? homeSshProfileId,
    required bool Function(String id) sshProfileExists,
    required Future<void> Function() reinstallStorageContext,
  }) async {
    await bootstrapHomeIndex(
      boot: boot,
      sshProfileCubit: sshProfileCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      layoutCubit: layoutCubit,
      isSshMode: isSshMode,
      homeSshProfileId: homeSshProfileId,
      sshProfileExists: sshProfileExists,
      reinstallStorageContext: reinstallStorageContext,
    );
    await warmAuxiliaryData(
      boot: boot,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
    );
    await _timed(
      boot,
      'loadWorkspaceData',
      () => chatCubit.loadWorkspaceData(sessionRepo),
    );
  }

  static Future<T> _timed<T>(
    BootLog boot,
    String name,
    Future<T> Function() fn,
  ) async {
    final sw = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      appLogger.i('[boot] $name +${sw.elapsedMilliseconds}ms');
    }
  }

  static Future<void> _ensureDefaultWorkspace(
    BootLog boot, {
    required ChatCubit chatCubit,
    required SessionRepository sessionRepo,
  }) async {
    final mutated = await _timed(
      boot,
      'defaultWorkspaceEnsure',
      () => DefaultWorkspaceService.ensureDefault(
        sessionRepo,
        knownWorkspaces: chatCubit.state.workspaces,
      ),
    );
    if (mutated) {
      await _timed(
        boot,
        'loadWorkspaceIndexAfterSeed',
        () => chatCubit.loadWorkspaceIndex(sessionRepo),
      );
    }
  }
}
