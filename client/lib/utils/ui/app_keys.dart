import 'package:flutter/widgets.dart';

class AppKeys {
  const AppKeys._();

  static const workspaceTopbar = Key('workspace-topbar');
  static const chatWorkspace = Key('chat-workspace');
  static const configWorkspace = Key('config-workspace');
  static const configSettingsHub = Key('config-settings-hub');
  static const rightToolsPanel = Key('right-tools-panel');
  static const membersPanel = Key('members-panel');
  static const fileTreePanel = Key('file-tree-panel');
  static const workspaceTerminalPanel = Key('workspace-terminal-panel');
  static const workbenchWelcomePage = Key('workbench-welcome-page');
  static Key workbenchWelcomeCommandRow(String commandId) =>
      Key('workbench-welcome-command-$commandId');
  static const workspaceChatLandingBackButton = Key(
    'workspace-chat-landing-back-button',
  );
  static const fileTreeVisibilitySwitch = Key('file-tree-visibility-switch');
  static const openExistingSessionStartsTerminalSwitch = Key(
    'open-existing-session-starts-terminal-switch',
  );
  static const simpleModeDefaultFullAccessSwitch = Key(
    'simple-mode-default-full-access-switch',
  );
  static const sidebarSessionWaitingMarker = Key(
    'sidebar-session-waiting-marker',
  );
  static const terminalLinkClickOpensInAppSwitch = Key(
    'terminal-link-click-opens-in-app-switch',
  );
  static const configLayoutSectionButton = Key('config-layout-section-button');
  static const configSessionSectionButton = Key(
    'config-session-section-button',
  );
  static const configSshProfilesSectionButton = Key(
    'config-ssh-profiles-section-button',
  );
  static const configGithubSectionButton = Key('config-github-section-button');
  static const configShortcutsSectionButton = Key(
    'config-shortcuts-section-button',
  );
  static const configLogsSectionButton = Key('config-logs-section-button');
  static const configAboutSectionButton = Key('config-about-section-button');
  static const aboutCheckUpdatesButton = Key('about-check-updates-button');
  static const aboutViewReleasesButton = Key('about-view-releases-button');
  static const aboutGitHubButton = Key('about-github-button');
  static const aboutDownloadInstallButton = Key(
    'about-download-install-button',
  );
  static const aboutAutoCheckUpdatesSwitch = Key(
    'about-auto-check-updates-switch',
  );
  static const workspaceTabRowNewChatButton = Key('workspace-tab-row-new-chat');
  static const workspaceConfigWorkspace = Key('workspace-config-workspace');
  static const sessionLaunchErrorBanner = Key('session-launch-error-banner');
  static const sessionLaunchErrorRetryButton = Key(
    'session-launch-error-retry-button',
  );
  static const rightToolsVisibilityButton = Key(
    'right-tools-visibility-button',
  );
  static const sidebarVisibilityButton = Key('sidebar-visibility-button');

  static const languageSystemButton = Key('language-system-button');
  static const languageEnButton = Key('language-en-button');
  static const languageZhButton = Key('language-zh-button');
}
