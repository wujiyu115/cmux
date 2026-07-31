import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../cubits/config_cubit.dart';
import '../pages/config/config_workspace.dart';
import '../pages/home_workspace/home_workspace_shell.dart';
import '../pages/onboarding/onboarding_gate.dart';
import '../pages/pairing/pairing_mobile_shell.dart';
import '../pages/startup_gate.dart';
import '../services/app/platform_utils.dart';
import '../widgets/android_ssh_profile_selector.dart';
import 'android_shell_chrome.dart';
import '../models/layout_preferences.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/splash_deferred_shell.dart';

final _workspaceEntryNotifier = ValueNotifier<String>('/home-v2');

@visibleForTesting
String workspaceEntryLocationFor({
  required WorkspaceEntryMode mode,
  String? lastOpenedWorkspaceId,
}) {
  if (mode != WorkspaceEntryMode.lastWorkspace) {
    return '/home-v2';
  }
  final workspaceId = lastOpenedWorkspaceId?.trim() ?? '';
  if (workspaceId.isEmpty) {
    return '/home-v2';
  }
  return '/home-v2/workspace/$workspaceId';
}

/// Apply the user's startup view preference. Call after [LayoutCubit.load()]
/// during bootstrap, before the first route is resolved.
void applyWorkspaceEntryMode(
  WorkspaceEntryMode mode, {
  String? lastOpenedWorkspaceId,
}) {
  _workspaceEntryNotifier.value = workspaceEntryLocationFor(
    mode: mode,
    lastOpenedWorkspaceId: lastOpenedWorkspaceId,
  );
}

/// Re-apply [lastWorkspace] after workspace index loads so missing ids fall back.
void reapplyWorkspaceEntryFromPreferences(
  LayoutPreferences preferences, {
  Set<String>? knownWorkspaceIds,
}) {
  if (preferences.workspaceEntryMode != WorkspaceEntryMode.lastWorkspace) {
    return;
  }
  final workspaceId = preferences.lastOpenedWorkspaceId.trim();
  if (workspaceId.isEmpty) {
    applyWorkspaceEntryMode(WorkspaceEntryMode.home);
    return;
  }
  if (knownWorkspaceIds != null && !knownWorkspaceIds.contains(workspaceId)) {
    applyWorkspaceEntryMode(WorkspaceEntryMode.home);
    return;
  }
  applyWorkspaceEntryMode(
    WorkspaceEntryMode.lastWorkspace,
    lastOpenedWorkspaceId: workspaceId,
  );
}

final appRouter = GoRouter(
  refreshListenable: _workspaceEntryNotifier,
  initialLocation: _workspaceEntryNotifier.value,
  routes: [
    // App-wide gates run once above both workspace shells so first-run setup
    // and SSH startup checks apply regardless of entry mode.
    ShellRoute(
      builder: (context, state, child) => OnboardingGate(
        key: onboardingGateKey,
        child: StartupGate(child: child),
      ),
      routes: [
        // Apifox-style workspace home — title bar + open workspace tabs live in
        // [HomeShell]; [HomeWorkspaceBodyStack] owns the visible body.
        ShellRoute(
          builder: (context, state, child) => isPairingClient
              // Mobile is a pure pairing/mirror client — its own slim shell
              // replaces the desktop workspace tabs entirely.
              ? const PairingMobileShell()
              : SplashDeferredShell(
                  child: HomeShell(location: state.uri.toString()),
                ),
          routes: [
            GoRoute(
              path: '/home-v2',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SizedBox.shrink()),
            ),
            GoRoute(
              path: '/home-v2/workspace/:workspaceId/manage',
              redirect: (context, state) {
                final id = state.pathParameters['workspaceId'];
                if (id == null) return '/home-v2';
                final section = state.uri.queryParameters['section'];
                final profile = state.uri.queryParameters['profile'];
                final params = <String, String>{'view': 'manage'};
                if (section != null && section.isNotEmpty) {
                  params['section'] = section;
                }
                if (profile != null && profile.isNotEmpty) {
                  params['profile'] = profile;
                }
                return Uri(
                  path: '/home-v2/workspace/$id',
                  queryParameters: params,
                ).toString();
              },
            ),
            GoRoute(
              path: '/home-v2/workspace/:workspaceId',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SizedBox.shrink()),
            ),
          ],
        ),
        ShellRoute(
          builder: _settingsChromeShell,
          routes: [
            GoRoute(
              path: '/config',
              redirect: (context, state) {
                if (Platform.isAndroid) return null;
                return '/config/layout';
              },
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ConfigSettingsHubPage()),
            ),
            GoRoute(
              path: '/config/layout',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ConfigWorkspace(section: ConfigSection.layout),
              ),
            ),
            GoRoute(
              path: '/config/session',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ConfigWorkspace(section: ConfigSection.session),
              ),
            ),
            GoRoute(
              path: '/config/ssh-profiles',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ConfigWorkspace(section: ConfigSection.sshProfiles),
              ),
            ),
            GoRoute(
              path: '/config/pairing',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ConfigWorkspace(section: ConfigSection.pairing),
              ),
            ),
            GoRoute(
              path: '/config/github',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ConfigWorkspace(section: ConfigSection.github),
              ),
            ),
            GoRoute(
              path: '/config/shortcuts',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ConfigWorkspace(section: ConfigSection.shortcuts),
              ),
            ),
            GoRoute(
              path: '/config/about',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ConfigWorkspace(section: ConfigSection.about),
              ),
            ),
            GoRoute(
              path: '/config/logs',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ConfigWorkspace(section: ConfigSection.logs),
              ),
            ),
            GoRoute(
              path: '/ssh-profiles',
              redirect: (context, state) => '/config/ssh-profiles',
            ),
          ],
        ),
      ],
    ),
  ],
);

Widget _settingsChromeShell(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  if (Platform.isAndroid) {
    final path = state.uri.path;
    final detail = AndroidShellChrome.isHubDetailPath(path);
    return Scaffold(
      appBar: AppBar(
        title: Text(AndroidShellChrome.title(context, path)),
        leading: detail
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () => AndroidShellChrome.pop(context, path),
              )
            : null,
        actions: const [AndroidSshProfileSelector()],
      ),
      body: child,
    );
  }

  return Scaffold(
    body: DesktopWindowChrome(child: SafeArea(top: false, child: child)),
  );
}

