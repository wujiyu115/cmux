import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/l10n_extensions.dart';

/// Resolves Android [Scaffold] title, back affordance, and drawer visibility
/// for hub-style workspace routes (settings, team config).
class AndroidShellChrome {
  const AndroidShellChrome._();

  static bool isHubDetailPath(String path) {
    if (_isConfigDetail(path)) return true;
    if (_isTeamConfigDetail(path)) return true;
    return false;
  }

  static bool shouldHideDrawer(String path) => isHubDetailPath(path);

  static String title(BuildContext context, String path) {
    final l10n = context.l10n;
    if (path == '/config') return l10n.settings;
    if (path == '/config/layout') return l10n.layout;
    if (path == '/config/session') return l10n.session;
    if (path == '/config/ssh-profiles') return l10n.sshProfilesSettingsTitle;
    if (path == '/config/github') return l10n.githubSettingsTitle;
    if (path == '/config/shortcuts') return l10n.shortcutsSettingsTitle;
    if (path == '/config/about') return l10n.aboutTitle;
    if (path == '/config/logs') return l10n.logViewerTitle;

    if (path == '/team-config') return l10n.teamConfig;
    if (path == '/team-config/team') return l10n.teamSettings;
    if (path.startsWith('/team-config/members/')) {
      return _memberTitle(context, path) ?? l10n.members;
    }


    return 'FlashSkyAI';
  }

  static void pop(BuildContext context, String path) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    if (_isConfigDetail(path) || path == '/config') {
      context.go('/config');
      return;
    }
    if (_isTeamConfigDetail(path) || path == '/team-config') {
      context.go('/team-config');
      return;
    }
  }

  static bool _isConfigDetail(String path) =>
      path.startsWith('/config/') && path.length > '/config/'.length;

  static bool _isTeamConfigDetail(String path) =>
      path.startsWith('/team-config/') && path.length > '/team-config/'.length;

  static String? _memberTitle(BuildContext context, String path) => null;
}
