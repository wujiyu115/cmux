// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get copy => 'copy';

  @override
  String get settings => 'Settings';

  @override
  String get settingsPageSubtitle =>
      'Manage FlashskyAI team and model settings.';

  @override
  String get layout => 'Layout';

  @override
  String get save => 'Save';

  @override
  String get ok => 'OK';

  @override
  String get layoutPageSubtitle =>
      'Structure controls are global and apply across teams.';

  @override
  String get right => 'Right';

  @override
  String get bottom => 'Bottom';

  @override
  String get rightTools => 'Right Tools';

  @override
  String get rightToolsPanelVisible => 'Show tools panel';

  @override
  String get rightToolsPanelHidden => 'Hide tools panel';

  @override
  String get sidebarPanelVisible => 'Show sidebar';

  @override
  String get sidebarPanelHidden => 'Hide sidebar';

  @override
  String get stacked => 'Stacked';

  @override
  String get tabs => 'Tabs';

  @override
  String get regionVisibility => 'Region Visibility';

  @override
  String get visibilityMembersHint =>
      'Show the member list next to tools or terminals.';

  @override
  String get visibilityFileTreeHint =>
      'Show the workspace file tree for quick navigation.';

  @override
  String get visibilityGitHint =>
      'Show the source control panel for the current repository.';

  @override
  String get themeModeTitle => 'Theme mode';

  @override
  String get themeModeDescription =>
      'Light, dark, or match the operating system appearance.';

  @override
  String get themeColorPresetTitle => 'Theme colors';

  @override
  String get themeColorPresetDescription =>
      'Primary and accent colors for buttons, toggles, and highlights.';

  @override
  String get typographyScaleTitle => 'Text size';

  @override
  String get typographyScaleDescription =>
      'Size of UI text. Standard follows your system; does not change icons or spacing.';

  @override
  String get typographyScaleCompact => 'Small';

  @override
  String get typographyScaleStandard => 'Standard';

  @override
  String get typographyScaleComfortable => 'Large';

  @override
  String get typographyScaleCustom => 'Custom';

  @override
  String get typographyScaleCustomHint => '50–200';

  @override
  String get fontUiTitle => 'Interface font';

  @override
  String get fontUiDescription =>
      'UI text. System follows the OS default. Takes effect after restart.';

  @override
  String get fontMonoTitle => 'Monospace font';

  @override
  String get fontMonoDescription =>
      'Terminal, editor, and diffs. Takes effect after restart.';

  @override
  String get fontChangeAppliesOnRestart =>
      'Font saved. Restart TeamPilot to apply.';

  @override
  String get fontOptionSystem => 'System';

  @override
  String get fontOptionNotoSansSc => 'Noto Sans SC';

  @override
  String get fontOptionJetbrainsMono => 'JetBrains Mono';

  @override
  String get fontOptionUbuntuSansMono => 'Ubuntu Sans Mono';

  @override
  String get fontSearchHint => 'Search fonts';

  @override
  String get uiZoomTitle => 'Interface zoom';

  @override
  String get uiZoomDescription =>
      'Zoom the whole UI together — text, icons, and spacing. Standard follows your display scaling.';

  @override
  String get markdownOpenModeTitle => 'Open Markdown as';

  @override
  String get markdownOpenModeDescription =>
      'Default view when opening .md files in the editor. Remember lasts for this app session only.';

  @override
  String get markdownOpenModePreview => 'Preview';

  @override
  String get markdownOpenModeSource => 'Source';

  @override
  String get markdownOpenModeRemember => 'Remember last';

  @override
  String get markdownViewToggleSource => 'Source';

  @override
  String get markdownViewTogglePreview => 'Preview';

  @override
  String get themePresetGraphite => 'Graphite';

  @override
  String get themePresetOcean => 'Ocean';

  @override
  String get themePresetViolet => 'Violet';

  @override
  String get themePresetAmber => 'Amber';

  @override
  String get themePresetForest => 'Forest';

  @override
  String get themePresetTerminal => 'Terminal';

  @override
  String get languageDescription =>
      'Language used for menus, buttons, and labels.';

  @override
  String get cancel => 'Cancel';

  @override
  String get add => 'Add';

  @override
  String get delete => 'Delete';

  @override
  String get appearance => 'Appearance';

  @override
  String get workspaceEntryModeTitle => 'Startup view';

  @override
  String get workspaceEntryModeDescription =>
      'Where the app opens after launch.';

  @override
  String get workspaceEntryModeHome => 'Home';

  @override
  String get workspaceEntryModeLastWorkspace => 'Last workspace';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get fileTree => 'File Tree';

  @override
  String get sourceControl => 'Source Control';

  @override
  String get gitStagedChanges => 'Staged Changes';

  @override
  String get gitChanges => 'Changes';

  @override
  String get gitNoChanges => 'No changes';

  @override
  String get gitNotARepository => 'This folder is not a Git repository';

  @override
  String get gitNotInstalled =>
      'Git was not found. Install Git to use source control.';

  @override
  String get gitCommit => 'Commit';

  @override
  String gitCommitMessageHint(String branch) {
    return 'Message (commit to \"$branch\")';
  }

  @override
  String get gitStage => 'Stage changes';

  @override
  String get gitUnstage => 'Unstage changes';

  @override
  String get gitStageAll => 'Stage all changes';

  @override
  String get gitUnstageAll => 'Unstage all changes';

  @override
  String get gitStageFolder => 'Stage changes in folder';

  @override
  String get gitUnstageFolder => 'Unstage changes in folder';

  @override
  String get treeExpandAllFolders => 'Expand all folders';

  @override
  String get treeCollapseAllFolders => 'Collapse all folders';

  @override
  String get gitDiscard => 'Discard changes';

  @override
  String get gitDiscardConfirmTitle => 'Discard changes?';

  @override
  String gitDiscardConfirmBody(String path) {
    return 'Discard all changes in $path? This cannot be undone.';
  }

  @override
  String get gitPush => 'Push';

  @override
  String get gitPull => 'Pull';

  @override
  String get gitRefresh => 'Refresh';

  @override
  String get gitSwitchBranch => 'Switch branch';

  @override
  String get gitCreateBranch => 'Create branch';

  @override
  String get gitNewBranchHint => 'New branch name';

  @override
  String gitError(String message) {
    return 'Git: $message';
  }

  @override
  String gitAheadBehind(int ahead, int behind) {
    return '↑$ahead ↓$behind';
  }

  @override
  String get filterFiles => 'Filter files';

  @override
  String get workspaces => 'Workspaces';

  @override
  String get newWorkspace => 'New Workspace';

  @override
  String get homeWorkspaceMainWindow => 'Workspace';

  @override
  String get windowControlMinimize => 'Minimize';

  @override
  String get windowControlMaximize => 'Maximize';

  @override
  String get windowControlRestore => 'Restore';

  @override
  String get windowControlClose => 'Close';

  @override
  String get windowControlAlwaysOnTop => 'Always on top';

  @override
  String get homeWorkspaceMyFavorites => 'My favorites';

  @override
  String get homeWorkspaceRecentVisits => 'Recent';

  @override
  String get homeWorkspaceAllWorkspaces => 'All workspaces';

  @override
  String get homeWorkspaceNoData => 'No data yet';

  @override
  String get homeWorkspaceRecentlyClosed => 'Recently closed';

  @override
  String get homeWorkspaceRecentlyClosedEmpty =>
      'No recently closed workspaces';

  @override
  String get homeWorkspaceSessionsLabel => 'sessions';

  @override
  String get homeWorkspaceEmptyWorkspaces => 'No workspaces in this team yet';

  @override
  String get homeWorkspaceEmptyWorkspacesHint =>
      'Create or import a workspace to get started';

  @override
  String get homeWorkspaceWorkspaceSort => 'Sort workspaces';

  @override
  String get homeWorkspaceWorkspaceSortRecentlyUpdated => 'Recently updated';

  @override
  String get homeWorkspaceWorkspaceSortNameAsc => 'Name (A–Z)';

  @override
  String get homeWorkspaceWorkspaceSortNameDesc => 'Name (Z–A)';

  @override
  String get homeWorkspaceWorkspaceSortCreatedDesc => 'Date created';

  @override
  String get homeWorkspaceWorkspaceSortSessionCountDesc => 'Session count';

  @override
  String get homeWorkspaceNewWorkspaceSubtitle =>
      'Choose a working directory and name your workspace.';

  @override
  String get homeWorkspaceNewWorkspaceDirectoryLabel => 'Workspace directory';

  @override
  String get homeWorkspaceNewWorkspaceChooseDirectory => 'Choose folder';

  @override
  String get homeWorkspaceNewWorkspaceDirectoryHint =>
      'No directory selected yet';

  @override
  String get homeWorkspaceNewWorkspaceNameHint => 'Defaults to the folder name';

  @override
  String get homeWorkspaceCreateWorkspace => 'Create workspace';

  @override
  String get homeWorkspaceCloseWorkspaceTitle => 'Close workspace?';

  @override
  String homeWorkspaceCloseWorkspaceMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Closing this tab will end $count running sessions in this workspace.',
      one: 'Closing this tab will end 1 running session in this workspace.',
    );
    return '$_temp0';
  }

  @override
  String get homeWorkspaceCloseWorkspaceConfirm => 'Close & end sessions';

  @override
  String get homeWorkspaceWorkspaceManagement => 'Workspace management';

  @override
  String get homeWorkspaceConversationsSection => 'Conversations';

  @override
  String get workspaceRunningSessionsSection => 'Running';

  @override
  String get workspaceCliConfigured => 'Configured';

  @override
  String get workspaceCliNotConfigured => 'Not configured';

  @override
  String get homeWorkspaceWorkspaceSettings => 'Workspace settings';

  @override
  String get homeWorkspaceWorkspaceSettingsBasicInfo => 'Basic information';

  @override
  String get homeWorkspaceWorkspaceId => 'Workspace ID';

  @override
  String get deleteWorkspaceSubtitle =>
      'Deletes this workspace and all conversations in it. This cannot be undone.';

  @override
  String get homeWorkspaceNewConversation => 'New Conversation';

  @override
  String get workbenchStripNewMenuTooltip => 'New';

  @override
  String get homeWorkspaceNoConversations =>
      'No conversations in this workspace yet';

  @override
  String get workspaceSearchTitle => 'Search';

  @override
  String get workspaceSearchHint => 'Search sessions and files';

  @override
  String get workspaceSearchFilesSection => 'Files';

  @override
  String get workspaceSearchSearching => 'Searching files…';

  @override
  String get workspaceSearchNoResults => 'No matches';

  @override
  String get workspaceSearchFilesTruncated =>
      'More files match — refine your search';

  @override
  String get homeWorkspaceOpenWorkspaceInNewTab => 'Open in new tab';

  @override
  String get homeWorkspaceFavoriteWorkspace => 'Favorite workspace';

  @override
  String get homeWorkspaceUnfavoriteWorkspace => 'Remove from favorites';

  @override
  String get homeWorkspaceRenameWorkspace => 'Rename workspace';

  @override
  String get homeWorkspaceCloneWorkspace => 'Clone workspace';

  @override
  String homeWorkspaceCloneWorkspaceDisplayName(Object name) {
    return '$name (copy)';
  }

  @override
  String homeWorkspaceCloneWorkspaceSuccess(Object name) {
    return 'Cloned \"$name\".';
  }

  @override
  String get homeWorkspaceCloneWorkspaceFailed => 'Could not clone workspace';

  @override
  String get create => 'Create';

  @override
  String get workspacePrimaryPathRequired =>
      'Select a primary directory first.';

  @override
  String get workspacePrimaryPathNotSelected => 'No primary directory selected';

  @override
  String get defaultNewChatSessionTitle => 'New Chat';

  @override
  String get sessionStarting => 'Starting session…';

  @override
  String get agentPermissionAttentionBanner =>
      'This agent needs confirmation in the Terminal.';

  @override
  String get agentPermissionOpenTerminal => 'Open Terminal';

  @override
  String get sessionWorkbenchShowChat => 'Show Chat';

  @override
  String get sessionWorkbenchShowTerminal => 'Show Terminal';

  @override
  String get workspaceChatLandingInputHint =>
      'What can I help you with today? @ reference files, / invoke skills';

  @override
  String get workspaceChatLandingBackToStart => 'Back to start';

  @override
  String get workspaceChatLandingSelectProject => 'Select project >';

  @override
  String get workspaceChatLandingSelectWorktree => 'Select worktree >';

  @override
  String get workspaceChatLandingFullAccessPermissions =>
      'Full access permissions';

  @override
  String get workspaceChatLandingDefaultPermissions => 'Default permissions';

  @override
  String get workspaceChatLandingAttach => 'Attach files';

  @override
  String get workspaceChatLandingVoice => 'Voice input';

  @override
  String get workspaceChatLandingVoiceCancel => 'Cancel recording';

  @override
  String get workspaceChatLandingVoiceStop => 'Stop recording';

  @override
  String get workspaceChatLandingVoiceUnavailable =>
      'Voice input is not available on this device';

  @override
  String get workspaceChatLandingVoicePermissionDenied =>
      'Microphone permission denied';

  @override
  String get sessionRetryButton => 'Try again';

  @override
  String get copyFolderPath => 'Copy Folder Path';

  @override
  String pathCopied(String path) {
    return 'Path copied: $path';
  }

  @override
  String get workspaceDetailsTitle => 'Workspace Details';

  @override
  String get addWorkspaceDirectory => 'Add directory';

  @override
  String get workspaceDisplayName => 'Display name';

  @override
  String get workspaceIcon => 'Icon';

  @override
  String get workspaceNavUngrouped => 'Ungrouped';

  @override
  String get workspaceNavNewGroup => 'New group';

  @override
  String get workspaceNavGroupNameHint => 'Group name';

  @override
  String get workspaceGroupRename => 'Rename group';

  @override
  String get workspaceGroupDelete => 'Delete group';

  @override
  String get workspaceGroupAccentColor => 'Group color';

  @override
  String get workspaceMoveToGroup => 'Move to group';

  @override
  String get workspaceRemoveFromGroup => 'Remove from group';

  @override
  String get workspaceDefaultTerminal => 'Default terminal';

  @override
  String get workspaceDefaultTerminalGlobal => 'Global default';

  @override
  String get workspaceAccentColor => 'Accent color';

  @override
  String get workspaceAccentDefault => 'Default';

  @override
  String get workspaceMoveUp => 'Move up';

  @override
  String get workspaceMoveDown => 'Move down';

  @override
  String get workspaceIconPickerTitle => 'Choose workspace icon';

  @override
  String get workspaceIconUseDefault => 'Use default';

  @override
  String get workspaceIconUpload => 'Upload icon';

  @override
  String get workspaceSessionCount => 'Sessions';

  @override
  String get workspaceCreatedAt => 'Created';

  @override
  String get workspaceUpdatedAt => 'Updated';

  @override
  String get workspaceDirectoryAlreadyAdded =>
      'This directory is already in the workspace.';

  @override
  String get remoteDirectoryBrowserTitle => 'Browse remote directory';

  @override
  String get remoteDirectoryBrowserUpOneLevel => 'Up one level';

  @override
  String get remoteDirectoryBrowserUseThisDirectory => 'Use this directory';

  @override
  String get remoteDirectoryBrowserTypePathLabel => 'Or type a path';

  @override
  String get remoteDirectoryBrowserTypePathHint => '~/work/workspace';

  @override
  String get remoteDirectoryBrowserUseTypedPath => 'Use path';

  @override
  String get remoteDirectoryBrowserError =>
      'Couldn\'t open the remote directory. You can still type a path below.';

  @override
  String get remoteDirectoryBrowserEmpty => 'No subdirectories here';

  @override
  String get deleteWorkspace => 'Delete Workspace';

  @override
  String deleteWorkspaceConfirm(String name) {
    return 'Delete workspace \"$name\" and all its sessions? This cannot be undone.';
  }

  @override
  String get renameConversation => 'Rename conversation';

  @override
  String get deleteConversation => 'Delete conversation';

  @override
  String get pinConversation => 'Pin conversation';

  @override
  String get unpinConversation => 'Unpin conversation';

  @override
  String get sessionSortRecentlyUpdated => 'Recently updated';

  @override
  String get sessionSortCreatedDesc => 'Date created';

  @override
  String get sessionSortTooltip => 'Sort conversations';

  @override
  String get renameConversationTitle => 'Rename Conversation';

  @override
  String get conversationName => 'Conversation name';

  @override
  String get closeTab => 'Close';

  @override
  String get closeOtherTabs => 'Close Others';

  @override
  String get closeRightTabs => 'Close to the Right';

  @override
  String get session => 'Session';

  @override
  String get sessionPageSubtitle =>
      'Configure shell session launch, terminal behavior, and storage backend.';

  @override
  String get sshProfilesSettingsTitle => 'SSH servers';

  @override
  String get sshProfilesPageTitle => 'SSH remote hosts';

  @override
  String get sshProfilesPageSubtitle =>
      'Connect to existing machines over SSH for files, terminals, Git, and workspaces.';

  @override
  String get sshProfilesTargetsTitle => 'Targets';

  @override
  String get sshProfilesTargetsSubtitle =>
      'Add a remote host to connect from TeamPilot.';

  @override
  String get sshProfilesImport => 'Import';

  @override
  String get sshProfilesImportUnavailable =>
      'Import from ~/.ssh/config is not available yet.';

  @override
  String get sshProfilesAddTarget => 'Add target';

  @override
  String get sshProfilesEmpty => 'No SSH targets configured.';

  @override
  String get sshProfileStatusDisconnected => 'Disconnected';

  @override
  String get sshProfileStatusConnecting => 'Connecting…';

  @override
  String get sshProfileStatusConnected => 'Connected';

  @override
  String get sshProfileStatusError => 'Error';

  @override
  String get sshProfileStatusReconnecting => 'Reconnecting…';

  @override
  String get sshProfileStatusAuthFailed => 'Authentication failed';

  @override
  String sshHostsPillCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts',
      one: '1 host',
    );
    return '$_temp0';
  }

  @override
  String get sshHostsPillConnecting => 'Connecting…';

  @override
  String get sshHostsPanelTitle => 'Remote Hosts';

  @override
  String get sshHostsRowKind => 'SSH Host';

  @override
  String get sshHostsManage => 'Manage Remote Hosts…';

  @override
  String get sshProfileTest => 'Test';

  @override
  String get sshProfileConnect => 'Connect';

  @override
  String get sshProfileDisconnect => 'Disconnect';

  @override
  String get sshProfileEdit => 'Edit';

  @override
  String get sshProfileDelete => 'Delete';

  @override
  String get sshProfileRefresh => 'Refresh';

  @override
  String get sshProfileTestSuccess => 'Connection successful';

  @override
  String get sshProfileTestFailedHostKey => 'Host key was not trusted';

  @override
  String get sshProfileTestFailedAuth => 'Authentication failed';

  @override
  String sshProfileTestFailedAborted(String detail) {
    return 'Connection closed before login: $detail';
  }

  @override
  String sshProfileTestFailedDetail(String detail) {
    return 'Connection test failed: $detail';
  }

  @override
  String sshProfileConnectSuccess(String host) {
    return 'Connected to $host';
  }

  @override
  String get sshHostKeyUnknownTitle => 'Verify SSH host key';

  @override
  String sshHostKeyUnknownBody(String host) {
    return 'TeamPilot has not seen $host before. Confirm the fingerprint matches this machine before trusting it.';
  }

  @override
  String get sshHostKeyMismatchTitle => 'SSH host key changed';

  @override
  String sshHostKeyMismatchBody(String host) {
    return 'The host key for $host does not match the one TeamPilot saved earlier. This can happen after a reinstall — or if someone is intercepting the connection.';
  }

  @override
  String get sshHostKeyFingerprintLabel => 'Fingerprint';

  @override
  String get sshHostKeyPreviousFingerprintLabel => 'Previously trusted';

  @override
  String sshHostKeyKeyTypeLabel(String keyType) {
    return 'Key type: $keyType';
  }

  @override
  String get sshHostKeyTrust => 'Trust and continue';

  @override
  String get sshHostKeyReplaceTrust => 'Replace and trust';

  @override
  String get sshProfileFormTitleNew => 'New SSH target';

  @override
  String get sshProfileFormTitleEdit => 'Edit SSH target';

  @override
  String get sshProfileFormLabel => 'Label';

  @override
  String get sshProfileFormLabelHint => 'My server';

  @override
  String get sshProfileFormHost => 'Host or alias';

  @override
  String get sshProfileFormHostHint => 'server, deploy@server:2222';

  @override
  String get sshProfileFormUsername => 'Username';

  @override
  String get sshProfileFormUsernameHint => 'deploy';

  @override
  String get sshProfileFormPort => 'Port';

  @override
  String get sshProfileFormPortInvalid => 'Port must be between 1 and 65535';

  @override
  String get sshProfileFormIdentityFile => 'Identity file';

  @override
  String get sshProfileFormIdentityFileHint => '~/.ssh/id_ed25519';

  @override
  String get sshProfileFormIdentityFileHelper =>
      'Optional. Reads the private key from disk when set.';

  @override
  String get sshProfileFormIdentityFileBrowse => 'Browse…';

  @override
  String get sshProfileFormIdentityFileMissing => 'Identity file not found';

  @override
  String get sshProfileFormPassphrase => 'Key passphrase';

  @override
  String get sshProfileFormPassphraseHint => 'Optional';

  @override
  String get sshProfileFormPassword => 'Password';

  @override
  String get sshProfileFormPasswordHint => 'Use when no identity file is set';

  @override
  String get sshProfileFormPasswordHintEdit =>
      'Leave empty to keep saved password';

  @override
  String get sshProfileFormPasswordHelper =>
      'Optional if an identity file is provided.';

  @override
  String get sshProfileFormCredentialRequired =>
      'Provide an identity file or password.';

  @override
  String get sshProfileFormFieldRequired => 'Required';

  @override
  String get sshProfileSelectorManage => 'Manage SSH servers…';

  @override
  String get sshDefaultWorkingDirectoryTitle => 'SSH default working directory';

  @override
  String get sshDefaultWorkingDirectorySubtitle =>
      'Remote working directory used when the SSH launch has no workspace path; leave empty to skip changing directory.';

  @override
  String get cliExecutablePathBrowse => 'Browse…';

  @override
  String get cliExecutablePathReset => 'Reset';

  @override
  String get cliExecutablePathUsing => 'Using: ';

  @override
  String get cliInstallButton => 'Install';

  @override
  String get cliInstallInstalling => 'Installing…';

  @override
  String get cliInstallProgressCheckingNpm => 'Checking for npm…';

  @override
  String get cliInstallProgressInstallingCli => 'Installing CLI…';

  @override
  String get cliInstallProgressLocatingExecutable => 'Locating CLI executable…';

  @override
  String get terminalFind => 'Find in terminal';

  @override
  String get terminalFindNoResults => 'No results';

  @override
  String get terminalDropCrossMachineRejected =>
      'Can\'t drop a local file onto a remote terminal';

  @override
  String get editorSave => 'Save';

  @override
  String get editorCut => 'Cut';

  @override
  String get editorCopy => 'Copy';

  @override
  String get editorCopyAsAiContext => 'Copy as AI context';

  @override
  String get selectionAskAi => 'Ask AI…';

  @override
  String get editorPaste => 'Paste';

  @override
  String get editorSelectAll => 'Select all';

  @override
  String get editorUndoEdit => 'Undo';

  @override
  String get editorRedoEdit => 'Redo';

  @override
  String get editorRevertChanges => 'Revert changes';

  @override
  String get editorUnsavedChangesTitle => 'Unsaved changes';

  @override
  String editorUnsavedChangesDiscardMultiple(int count) {
    return 'Discard unsaved changes in $count file(s)?';
  }

  @override
  String get editorDiscard => 'Discard';

  @override
  String get editorNotReady => 'Editor not ready';

  @override
  String get editorBinaryFileHint =>
      'Binary files open with the system default app.';

  @override
  String get editorFileNotFound => 'File not found';

  @override
  String get editorFileTooLarge =>
      'File is too large to edit in TeamPilot (max 2 MB).';

  @override
  String get editorImageTooLarge =>
      'Image is too large to preview in TeamPilot (max 25 MB).';

  @override
  String get editorImageDecodeFailed => 'Could not decode this image.';

  @override
  String get editorCouldNotReadFile => 'Could not read file';

  @override
  String get editorFileReadOnly => 'File is read-only';

  @override
  String editorSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get fileTreeRevealActiveFile => 'Reveal active file';

  @override
  String get fileTreeRefresh => 'Refresh';

  @override
  String get fileTreeShowFilter => 'Show file filter';

  @override
  String get fileTreeHideFilter => 'Hide file filter';

  @override
  String get fileTreeRevealFailed => 'Cannot reveal this file in the file tree';

  @override
  String get fileTreeOpenWithSystemApp => 'Open with system app';

  @override
  String get fileTreeCopyPath => 'Copy path';

  @override
  String get fileTreeDeleteItemTitle => 'Delete';

  @override
  String fileTreeDeleteItemConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get fileTreeNewFile => 'New File';

  @override
  String get fileTreeNewFolder => 'New Folder';

  @override
  String get fileTreeCreateNameHint => 'Name';

  @override
  String get fileTreeCut => 'Cut';

  @override
  String get fileTreeCopy => 'Copy';

  @override
  String get fileTreePaste => 'Paste';

  @override
  String get fileTreeRename => 'Rename';

  @override
  String get fileTreeRenameTitle => 'Rename';

  @override
  String get fileTreeOpenInFileManager => 'Reveal in File Manager';

  @override
  String get fileTreeOpenInTerminal => 'Open in Terminal';

  @override
  String get fileTreePasteDone => 'Pasted';

  @override
  String get fileTreeFileCreated => 'File created';

  @override
  String get fileTreeFolderCreated => 'Folder created';

  @override
  String get fileTreeRenameDone => 'Renamed';

  @override
  String get fileTreeDeleteDone => 'Deleted';

  @override
  String get fileTreeInvalidName => 'Invalid name';

  @override
  String get fileTreeItemExists => 'An item with that name already exists';

  @override
  String get fileTreeSourceMissing => 'The copied item no longer exists';

  @override
  String get fileTreeInvalidPasteTarget => 'Cannot paste here';

  @override
  String get fileTreeOpenInTerminalFailed => 'Could not open a terminal';

  @override
  String get terminalOpenLink => 'Open link';

  @override
  String get terminalExportScrollback => 'Export scrollback…';

  @override
  String get terminalCopySelectHint => 'Shift+drag to copy';

  @override
  String get workspaceTerminalNoWorkingDirectory =>
      'Connect a session to open the shell terminal';

  @override
  String get workspaceTerminalNewSession => 'New terminal';

  @override
  String get workspaceTerminalNewSshSession => 'New SSH Session…';

  @override
  String get workspaceTerminalSettings => 'Settings';

  @override
  String get workspaceTerminalThemeAdaptive => 'Match app theme';

  @override
  String get workspaceTerminalThemeClassicDark => 'Classic dark';

  @override
  String get workspaceTerminalThemeHighContrast => 'High contrast';

  @override
  String get workspaceTerminalSshConnectFailed =>
      'SSH profile not found or connection failed';

  @override
  String get workspaceToolsResolveFailed => 'Could not open workspace tools';

  @override
  String get workspaceToolsResolveFailedHint =>
      'Check that remote machines are reachable, then try again.';

  @override
  String get workspaceTerminalSplitRight => 'Split right';

  @override
  String get workspaceTerminalSplitDown => 'Split down';

  @override
  String get workspaceTerminalLayout => 'Layout';

  @override
  String get workspaceTerminalLayoutSingle => 'Single pane';

  @override
  String get workspaceTerminalLayoutColumns2 => '2 columns';

  @override
  String get workspaceTerminalLayoutColumns3 => '3 columns';

  @override
  String get workspaceTerminalLayoutGrid => '2×2 grid';

  @override
  String get workspaceTerminalLayoutMainStack => 'Main + stack';

  @override
  String get workspaceTerminalEqualize => 'Equalize panes';

  @override
  String get workspaceTerminalZoomPane => 'Zoom pane';

  @override
  String get workspaceTerminalUnzoomPane => 'Unzoom pane';

  @override
  String get workspaceTerminalClosePane => 'Close pane';

  @override
  String get workspaceTerminalCommandLog => 'Command log';

  @override
  String get commandLogTitle => 'Command log';

  @override
  String get commandLogRefresh => 'Refresh';

  @override
  String get commandLogOpenFolder => 'Open log folder';

  @override
  String get commandLogClose => 'Close';

  @override
  String get commandLogAllWorkspaces => 'All workspaces';

  @override
  String get commandLogAllSurfaces => 'All tabs';

  @override
  String get commandLogAllPanes => 'All panes';

  @override
  String get commandLogSearchHint => 'Search command or directory';

  @override
  String get commandLogClearFilters => 'Clear filters';

  @override
  String get commandLogColumnTime => 'Time';

  @override
  String get commandLogColumnWorkspace => 'Workspace';

  @override
  String get commandLogColumnSurface => 'Tab';

  @override
  String get commandLogColumnPane => 'Pane';

  @override
  String get commandLogColumnCommand => 'Command';

  @override
  String get commandLogColumnDirectory => 'Directory';

  @override
  String get commandLogColumnExitCode => 'Exit';

  @override
  String get commandLogColumnDuration => 'Duration';

  @override
  String get commandLogEmpty =>
      'No commands recorded yet. Commands are logged once the shell reports prompt markers (OSC 133).';

  @override
  String get commandLogNoMatches => 'No commands match the current filters';

  @override
  String commandLogEntryCount(int count) {
    return '$count entries';
  }

  @override
  String commandLogSkippedLines(int count) {
    return '$count unreadable lines skipped';
  }

  @override
  String get commandLogCopyCommand => 'Copy command';

  @override
  String get commandLogCopied => 'Command copied';

  @override
  String get commandLogInsertIntoPane => 'Insert into pane';

  @override
  String get commandLogRunInPane => 'Run in pane';

  @override
  String get commandHistoryTitle => 'Command history';

  @override
  String commandHistoryPaneTitle(String pane) {
    return 'Command history · Pane $pane';
  }

  @override
  String get commandHistorySearchHint => 'Search commands';

  @override
  String get commandHistoryHint => 'Enter = run, Shift+Enter = insert';

  @override
  String get commandHistoryEmpty =>
      'No command history found yet for this pane.';

  @override
  String get commandHistoryNoMatches => 'No commands match your search';

  @override
  String commandHistoryCount(int count) {
    return '$count commands';
  }

  @override
  String get commandHistoryCopy => 'Copy';

  @override
  String get commandHistoryCopied => 'Command copied';

  @override
  String get commandHistoryInsert => 'Insert';

  @override
  String get commandHistoryRun => 'Run';

  @override
  String get commandHistoryClose => 'Close';

  @override
  String get terminalScrollbackLinesTitle => 'Terminal scrollback lines';

  @override
  String get terminalScrollbackLinesDescription =>
      'Maximum lines kept in each session terminal buffer';

  @override
  String get terminalLinkClickOpensInAppTitle => 'Open terminal links in app';

  @override
  String get terminalLinkClickOpensInAppDescription =>
      'Left-click links and file paths to open them in TeamPilot instead of the running program. Ctrl/Cmd-click always opens in app.';

  @override
  String terminalParkedSendPending(String content) {
    return 'Sent, awaiting receipt: $content';
  }

  @override
  String get terminalParkedSendDismiss => 'Dismiss';

  @override
  String get mailbox => 'Mailbox';

  @override
  String get board => 'Board';

  @override
  String get visibilityBoardHint => 'Show the task board for mixed-mode teams.';

  @override
  String get openExistingSessionStartsTerminalTitle =>
      'Open existing sessions in terminal';

  @override
  String get openExistingSessionStartsTerminalDescription =>
      'When enabled, opening a saved session connects the terminal immediately. When off (default), open the Chat view first; send from Chat to start the terminal.';

  @override
  String get simpleModeDefaultFullAccessTitle =>
      'Simple mode default: full access';

  @override
  String get simpleModeDefaultFullAccessDescription =>
      'When enabled (default), new Simple-mode compose landing starts with full access permissions. Workspace chip choices still override and persist per workspace.';

  @override
  String get credentialPushOptInTitle => 'Push credentials to this machine';

  @override
  String get credentialPushOptInSubtitle =>
      'Provider keys for remote member authentication.';

  @override
  String get credentialPushConfirmTitle => 'Push credentials to remote host?';

  @override
  String credentialPushConfirmBody(Object host) {
    return 'Provider keys will be written to the remote host $host. Only enable this for machines you trust. Rotating a key requires re-pushing to every opted-in machine.';
  }

  @override
  String get credentialPushConfirmAction => 'Push credentials';

  @override
  String get rootSandboxEnvOptInTitle => 'Inject IS_SANDBOX for root';

  @override
  String get rootSandboxEnvOptInSubtitle =>
      'Keep skip-permissions when Claude runs as root.';

  @override
  String get rootSandboxEnvConfirmTitle => 'Enable root sandbox env?';

  @override
  String rootSandboxEnvConfirmBody(Object host) {
    return 'TeamPilot will set IS_SANDBOX=1 when launching Claude as root on $host, keeping --dangerously-skip-permissions. Only enable on machines you trust.';
  }

  @override
  String get rootSandboxEnvConfirmAction => 'Enable';

  @override
  String get workspaceFoldersSectionTitle => 'Directories & machines';

  @override
  String get workspaceFoldersEditorHint =>
      'Set machine and path per directory. All local = local workspace; all one remote = project-remote; cross-machine = mixed (member-remote).';

  @override
  String get workspaceFoldersMixedTargetsLockedHint =>
      'Mixed workspace: folder machines are fixed. Add paths on existing machines above; use Assign to change member machine assignment.';

  @override
  String get workspaceFoldersPersonalTargetsLockedHint =>
      'Personal identity cannot change folder machines. Switch to a team identity to configure machines and directories.';

  @override
  String get workspaceTopologyLocal => 'Local workspace';

  @override
  String get workspaceTopologyRemote => 'Remote workspace';

  @override
  String get workspaceTopologyMixed => 'Mixed workspace';

  @override
  String get workspaceTypeLabel => 'Type';

  @override
  String get mixedWorkspaceCreateSessionBlocked =>
      'Confirm machine assignment in Team Settings before starting a conversation in this mixed workspace.';

  @override
  String get mixedWorkspaceSessionLaunchBlocked =>
      'Machine assignment for this conversation is no longer valid. Confirm assignment in Team Settings and start a new conversation.';

  @override
  String get sessionLaunchMissingWorkspace =>
      'Workspace not found for this session.';

  @override
  String get sessionLaunchMissingTeamMember =>
      'Team member is not available. Select a team and try again.';

  @override
  String get workspaceFolderTargetLabel => 'Machine';

  @override
  String get workspaceFoldersPickTarget => 'Choose machine';

  @override
  String get workspaceDeadTargetBadge => 'Missing machine';

  @override
  String get workspaceDeadTargetRemap => 'Remap…';

  @override
  String get workspaceDeadTargetRemapTitle => 'Remap machine';

  @override
  String workspaceDeadTargetRemapBody(String from) {
    return 'Replace $from with another machine. Directory paths are not changed — they must already exist on the destination.';
  }

  @override
  String get workspaceDeadTargetRemapPickFrom => 'Dead machine';

  @override
  String get workspaceDeadTargetRemapPickTo => 'Replacement machine';

  @override
  String get workspaceDeadTargetRemapConfirm => 'Remap';

  @override
  String get workspaceDeadTargetRemapNothing => 'Nothing to remap.';

  @override
  String get workspaceDeadTargetRemapFailed => 'Could not remap machine.';

  @override
  String get workspaceDeadTargetRemapFromLaunch => 'Remap machine…';

  @override
  String get homeTargetTitle => 'Home device';

  @override
  String get homeTargetSubtitle =>
      'Where TeamPilot stores teams, workspaces, and config (the control plane). Switching uses a separate data tree; nothing is migrated automatically.';

  @override
  String bootstrapStartupFailed(String error) {
    return 'Startup failed: $error';
  }

  @override
  String get bootstrapUseNativeStorageInstead =>
      'Use Windows local storage instead';

  @override
  String get providers => 'PROVIDERS';

  @override
  String providerListModelCount(int count) {
    return '$count models';
  }

  @override
  String get proxyOnShort => 'Proxy on';

  @override
  String get proxyOffShort => 'Proxy off';

  @override
  String get type => 'Type';

  @override
  String get proxy => 'Proxy';

  @override
  String get reveal => 'Reveal';

  @override
  String get hide => 'Hide';

  @override
  String get claudeLaunchCredentialsMissingWarning =>
      'Claude Official credentials are missing for this team provider. Sign in from Providers settings.';

  @override
  String get api => 'api';

  @override
  String get account => 'account';

  @override
  String get models => 'Models';

  @override
  String get enabled => 'Enabled';

  @override
  String get edit => 'Edit';

  @override
  String get name => 'Name';

  @override
  String get summary => 'Summary';

  @override
  String get validation => 'Validation';

  @override
  String get validate => 'Validate';

  @override
  String get back => 'Back';

  @override
  String get members => 'Members';

  @override
  String get configure => 'Configure';

  @override
  String get teamConfig => 'Team Config';

  @override
  String get teamSettings => 'Team Settings';

  @override
  String get teamSkillsNav => 'Skills';

  @override
  String get teamPluginsNav => 'Plugins';

  @override
  String get teamMcpNav => 'MCP';

  @override
  String get githubSettingsTitle => 'GitHub';

  @override
  String get githubSettingsSubtitle =>
      'Connect GitHub to publish experts and teams to Hub';

  @override
  String get githubSignIn => 'Sign in with GitHub';

  @override
  String githubConnectedAs(Object login) {
    return 'Connected as @$login';
  }

  @override
  String get githubConnectedGeneric => 'Connected to GitHub';

  @override
  String get githubDisconnect => 'Disconnect';

  @override
  String get githubWaitingCodeHint => 'Enter this code on GitHub if prompted';

  @override
  String get githubBrowserOpened => 'Browser opened for authorization';

  @override
  String get githubReopenBrowser => 'Reopen browser';

  @override
  String get githubDeviceFlowUnavailable =>
      'GitHub sign-in is unavailable in this build. Use a personal access token.';

  @override
  String get githubAdvancedPat => 'Use a personal access token';

  @override
  String get githubAdvancedPatSubtitle =>
      'When GitHub sign-in is unavailable, or you prefer a token with repo scope.';

  @override
  String get hubPublishTokenLabel => 'GitHub token';

  @override
  String get hubPublishTokenHint => 'ghp_…';

  @override
  String get confirm => 'Confirm';

  @override
  String get dangerZone => 'Danger zone';

  @override
  String get memberName => 'Member name';

  @override
  String get provider => 'Provider';

  @override
  String get model => 'Model';

  @override
  String get agent => 'Agent preset';

  @override
  String get prompt => 'Prompt';

  @override
  String get appProviderClaudeAuthTokenDefault =>
      'ANTHROPIC_AUTH_TOKEN (default)';

  @override
  String get appProviderClaudeAuthApiKey => 'ANTHROPIC_API_KEY';

  @override
  String get appProviderToolFlashskyai => 'FlashskyAI';

  @override
  String get appProviderToolCodex => 'Codex';

  @override
  String get appProviderToolClaude => 'Claude Code';

  @override
  String get appProviderToolOpencode => 'OpenCode';

  @override
  String get appProviderToolCursor => 'Cursor';

  @override
  String get notes => 'Notes';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutPageSubtitle => 'TeamPilot version and application updates.';

  @override
  String get aboutGitHub => 'GitHub';

  @override
  String get aboutCurrentVersion => 'Current version';

  @override
  String get aboutVersionLoading => 'Loading…';

  @override
  String get appUpdateCheck => 'Check for updates';

  @override
  String get appUpdateAutoCheck => 'Auto-check for updates';

  @override
  String get appUpdateAutoCheckHint =>
      'Check GitHub for a newer version each time the app starts.';

  @override
  String get appUpdateSkipVersion => 'Skip this version';

  @override
  String get appUpdateDownloadInstall => 'Download and install';

  @override
  String get appUpdateUpToDate => 'You are on the latest version.';

  @override
  String get appUpdateDownloading => 'Downloading update…';

  @override
  String get appUpdateInstalling => 'Installing update…';

  @override
  String get appUpdateViewRelease => 'View release on GitHub';

  @override
  String get appUpdateViewReleases => 'Releases';

  @override
  String appUpdateNewVersion(String version) {
    return 'Version $version available';
  }

  @override
  String get appUpdateDialogTitle => 'New version available';

  @override
  String get appUpdateLatestVersion => 'Latest version';

  @override
  String get appUpdateUnknownVersion => 'Unknown';

  @override
  String get appUpdateChangelogTitle => 'What\'s new';

  @override
  String get appUpdateChangelogDefaultSection => 'Updates';

  @override
  String get appUpdateReadyToDownload => 'Ready to download';

  @override
  String get appUpdateLater => 'Later';

  @override
  String get appUpdateDownloadNow => 'Download now';

  @override
  String get appUpdateDownloadInBackground => 'Download in background';

  @override
  String get appUpdateInstallNow => 'Install now';

  @override
  String get appUpdateBrowserDownload => 'Download in browser';

  @override
  String get appUpdateInvalidPackagePath => 'Invalid package path';

  @override
  String get appUpdateReleaseBuildRequired =>
      'Use a release build for in-app installation';

  @override
  String get appUpdatePackagePlatformMismatch =>
      'Package type does not match this system';

  @override
  String appUpdateInstallFailed(String message) {
    return 'Install failed: $message';
  }

  @override
  String get appUpdateInstallNoResult => 'Install returned no result';

  @override
  String get appUpdateInstallComplete => 'Installation complete';

  @override
  String get appUpdateRedirectBrowserOnly =>
      'This link must be downloaded in the browser';

  @override
  String get appUpdateDownloadStarting => 'Starting download…';

  @override
  String get appUpdateDownloadComplete => 'Download complete';

  @override
  String get appUpdateDownloadFailed => 'Download failed';

  @override
  String appUpdateDownloadError(String error) {
    return 'Error while downloading: $error';
  }

  @override
  String get appUpdateResolvingDownloadUrl => 'Resolving download link…';

  @override
  String get appUpdateBrowserOpened => 'Opened download link in the browser';

  @override
  String get appUpdateCannotOpenDownloadLink => 'Could not open download link';

  @override
  String appUpdateBrowserOpenFailed(String error) {
    return 'Failed to open browser: $error';
  }

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingPrevious => 'Previous';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get onboardingAppearanceTitle => 'Choose language and appearance';

  @override
  String get onboardingAppearanceSubtitle =>
      'You can change these later in Settings → Layout.';

  @override
  String get onboardingSshTitle => 'Configure SSH connection';

  @override
  String get onboardingSshSubtitle =>
      'Android runs AI CLIs on a remote host over SSH.';

  @override
  String get onboardingRerunSetup => 'Run setup wizard again';

  @override
  String get logViewerTitle => 'Logs';

  @override
  String get logViewerSubtitle =>
      'Application and error logs under your TeamPilot app data folder.';

  @override
  String get logViewerSearchHint => 'Search logs…';

  @override
  String get logViewerWrapLines => 'Wrap lines';

  @override
  String get logViewerReverseOrder => 'Newest first';

  @override
  String get logViewerCompactView => 'Compact view';

  @override
  String logViewerLineCount(int count) {
    return '$count lines';
  }

  @override
  String get logViewerActionsMenu => 'More actions';

  @override
  String get logViewerRefresh => 'Refresh';

  @override
  String get logViewerCopyPath => 'Copy log path';

  @override
  String get logViewerClearOld => 'Remove old logs';

  @override
  String get logViewerEmpty => 'No log files yet';

  @override
  String get logViewerEmptyHint => 'Logs are created while the app runs.';

  @override
  String get logViewerPendingTitle => 'Logs not on disk yet';

  @override
  String get logViewerPendingBody =>
      'Buffered entries waiting for file logging:';

  @override
  String logViewerLoadFilesFailed(String error) {
    return 'Failed to list logs: $error';
  }

  @override
  String logViewerReadFailed(String error) {
    return 'Failed to read log: $error';
  }

  @override
  String get logViewerClearDone => 'Old log files removed';

  @override
  String logViewerClearFailed(String error) {
    return 'Cleanup failed: $error';
  }

  @override
  String logViewerPathCopied(String name) {
    return 'Copied path: $name';
  }

  @override
  String get initErrorTitle => 'Startup failed';

  @override
  String get initErrorDetails => 'Error details';

  @override
  String get initErrorStackTrace => 'Stack trace';

  @override
  String get initErrorPendingLogs => 'Pending logs';

  @override
  String get initErrorViewLogs => 'View logs';

  @override
  String get initErrorCopyReport => 'Copy report';

  @override
  String get initErrorCopy => 'Copy';

  @override
  String get initErrorCopied => 'Copied';

  @override
  String get initErrorStackEmpty => 'Stack trace is empty.';

  @override
  String initErrorVersion(String version, String build) {
    return 'Version $version ($build)';
  }

  @override
  String get diffIgnoreWhitespace => 'Ignore whitespace';

  @override
  String get diffPreviousChange => 'Previous change';

  @override
  String get diffNextChange => 'Next change';

  @override
  String get diffViewSideBySide => 'Side by side';

  @override
  String get diffViewUnified => 'Unified';

  @override
  String get diffOpenSourceFile => 'Open source file';

  @override
  String get diffShowAllLines => 'Show all lines';

  @override
  String get diffNoChanges => 'No changes';

  @override
  String get fileDiffToggleFile => 'File';

  @override
  String get fileDiffToggleDiff => 'Diff';

  @override
  String diffChangeCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get notificationCenterTitle => 'Notifications';

  @override
  String get notificationEmpty => 'No notifications';

  @override
  String get notificationMarkAllRead => 'Mark all as read';

  @override
  String get notificationClearAll => 'Clear';

  @override
  String get notificationMarkRead => 'Mark as read';

  @override
  String get notificationDelete => 'Delete';

  @override
  String notificationSourceTerminal(String code) {
    return 'Terminal OSC $code';
  }

  @override
  String get notificationSourceAgent => 'Agent';

  @override
  String get notificationTimeJustNow => 'Just now';

  @override
  String notificationTimeMinutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String notificationTimeHoursAgo(int hours) {
    return '$hours h ago';
  }

  @override
  String notificationTimeDaysAgo(int days) {
    return '$days d ago';
  }

  @override
  String get toolchainGit => 'Git';

  @override
  String get toolchainNode => 'Node.js';

  @override
  String get worktreeCreateTitle => 'New worktree';

  @override
  String get worktreeBranchLabel => 'Branch name';

  @override
  String get worktreeModeNewBranch => 'New branch';

  @override
  String get worktreeModeExistingBranch => 'Existing branch';

  @override
  String get worktreeBaseRefLabel => 'Base (optional)';

  @override
  String get worktreeBaseRefHint => 'Defaults to current HEAD';

  @override
  String get worktreePathLabel => 'Location';

  @override
  String get worktreeStartConversation =>
      'Start a conversation here after creating';

  @override
  String get worktreeCreateAction => 'Create';

  @override
  String worktreeCreateFailed(Object error) {
    return 'Failed to create worktree: $error';
  }

  @override
  String get worktreeDeleteTitle => 'Remove worktree';

  @override
  String worktreeDeleteBody(Object branch) {
    return 'Remove the worktree for $branch?';
  }

  @override
  String get worktreeDeleteForce =>
      'Force-remove even if it has uncommitted changes';

  @override
  String get worktreeDeleteBranchToo => 'Also delete the branch';

  @override
  String worktreeDeleteSessionsToo(Object count) {
    return 'Also delete the $count conversations in this worktree';
  }

  @override
  String get worktreeDeleteAction => 'Remove';

  @override
  String worktreeDeleteFailed(Object error) {
    return 'Failed to remove worktree: $error';
  }

  @override
  String get worktreeOrphanGroup => 'Other';

  @override
  String get worktreeNewWorktreeTooltip => 'New worktree';

  @override
  String get worktreeRefreshTooltip => 'Refresh worktrees';

  @override
  String get worktreeNewConversationHere => 'New conversation here';

  @override
  String get worktreeMenuCopyPath => 'Copy path';

  @override
  String get worktreeMenuRemove => 'Remove worktree';

  @override
  String get worktreeMore => 'More';

  @override
  String get worktreeShowLess => 'Show less';

  @override
  String get worktreeDeleteBusyWarning =>
      'Stop the running conversations in this worktree before removing it.';

  @override
  String get automationsLaunchProject => 'Project';

  @override
  String get automationsLaunchWorktree => 'Worktree';

  @override
  String get shortcutsWorkspaceNextTab => 'Next Workspace Tab';

  @override
  String get shortcutsWorkspacePrevTab => 'Previous Workspace Tab';

  @override
  String get shortcutsWorkspaceCloseTab => 'Close Workspace Tab';

  @override
  String get shortcutsWorkspaceReopenClosed => 'Reopen Closed Workspace Tab';

  @override
  String get shortcutsWorkspaceSearch => 'Search Workspace';

  @override
  String get shortcutsStripNextTab => 'Next Tab';

  @override
  String get shortcutsStripPrevTab => 'Previous Tab';

  @override
  String get shortcutsSessionNewTab => 'New Session Tab';

  @override
  String get shortcutsSessionCloseTab => 'Close Session Tab';

  @override
  String shortcutsStripFocusTab(int n) {
    return 'Go to Tab $n';
  }

  @override
  String get shortcutsToggleSidebar => 'Toggle Sidebar';

  @override
  String get shortcutsTogglePanel => 'Toggle Terminal Panel';

  @override
  String get shortcutsToggleSecondarySidebar => 'Toggle Secondary Sidebar';

  @override
  String get shortcutsZoomIn => 'Zoom In';

  @override
  String get shortcutsZoomOut => 'Zoom Out';

  @override
  String get shortcutsZoomReset => 'Reset Zoom';

  @override
  String get shortcutsComposeSubmit => 'Send Message';

  @override
  String get shortcutsComposeNewline => 'Insert Newline';

  @override
  String get shortcutsShowCheatsheet => 'Show Keyboard Shortcuts';

  @override
  String get shortcutsCategoryNavigation => 'Navigation';

  @override
  String get shortcutsCategoryTabs => 'Tabs';

  @override
  String get shortcutsCategoryView => 'View';

  @override
  String get shortcutsCategoryZoom => 'Zoom';

  @override
  String get shortcutsCategoryCompose => 'Compose';

  @override
  String get shortcutsCategoryMeta => 'General';

  @override
  String get shortcutsCategoryTerminal => 'Terminal';

  @override
  String get shortcutsSettingsTitle => 'Keyboard Shortcuts';

  @override
  String get shortcutsPageSubtitle =>
      'View and customize keyboard shortcuts for navigation, tabs, zoom, and compose.';

  @override
  String get shortcutsSearchHint => 'Search shortcuts';

  @override
  String get shortcutsChangeAction => 'Change…';

  @override
  String get shortcutsResetAction => 'Reset to Default';

  @override
  String get shortcutsUnbindAction => 'Unbind';

  @override
  String get shortcutsNotSet => 'Not set';

  @override
  String get shortcutsResetAll => 'Reset All';

  @override
  String get shortcutsResetAllConfirmTitle => 'Reset All Shortcuts?';

  @override
  String get shortcutsResetAllConfirmMessage =>
      'This restores every keyboard shortcut to its default binding.';

  @override
  String get shortcutsExport => 'Export…';

  @override
  String get shortcutsImport => 'Import…';

  @override
  String get shortcutsExportSuccess => 'Shortcuts exported.';

  @override
  String get shortcutsExportFailed => 'Couldn\'t export shortcuts.';

  @override
  String get shortcutsImportSuccess => 'Shortcuts imported.';

  @override
  String get shortcutsImportInvalidFile =>
      'That file isn\'t a valid shortcuts export.';

  @override
  String get shortcutsImportConflictTitle => 'Replace Conflicting Shortcuts?';

  @override
  String shortcutsImportConflictMessage(int count) {
    return 'The imported shortcuts conflict with $count existing binding(s). Replace them?';
  }

  @override
  String get shortcutsCheatsheetButton => 'View Cheatsheet';

  @override
  String get shortcutsCheatsheetTitle => 'Keyboard Shortcuts';

  @override
  String get shortcutsCheatsheetEmpty => 'No shortcuts match your search.';

  @override
  String get shortcutsPressShortcutTitle => 'Press a Shortcut';

  @override
  String get shortcutsPressShortcutHint =>
      'Press a key combination to bind it. Press Escape to cancel, Backspace to unbind.';

  @override
  String get shortcutsPressShortcutUnsupportedKey =>
      'That key can\'t be bound.';

  @override
  String shortcutsConflictMessage(String title) {
    return 'Already used by \"$title\".';
  }

  @override
  String get shortcutsReplaceAction => 'Replace';

  @override
  String get shortcutsConflictBadgeTooltip => 'Conflicts with another shortcut';

  @override
  String get runAction => 'Run';

  @override
  String get runStop => 'Stop';

  @override
  String get runRestart => 'Restart';

  @override
  String get runNewInstance => 'New instance';

  @override
  String get runDebug => 'Debug';

  @override
  String get runBuild => 'Build';

  @override
  String get runSelectConfiguration => 'Select configuration';

  @override
  String runCompoundConfiguration(String name) {
    return '$name (compound)';
  }

  @override
  String runSuggestedConfiguration(String name) {
    return '$name (Suggested)';
  }

  @override
  String get runConfigurationTooltip => 'Run configuration';

  @override
  String get runAlreadyRunningTitle => 'Configuration already running';

  @override
  String get runAlreadyRunningMessage =>
      'Restart the running session, or start a new instance?';

  @override
  String get runStopSessionTitle => 'Stop running session?';

  @override
  String runStopSessionMessage(String name) {
    return '\"$name\" is still running. Stop it and close this tab?';
  }

  @override
  String get runStopAndClose => 'Stop and close';

  @override
  String get runNoSessions => 'No run sessions';

  @override
  String get runClearExited => 'Clear exited sessions';

  @override
  String get runLoadingOutput => 'Loading run output…';

  @override
  String get runEmptyOutputHint => 'Run a configuration to see output here';

  @override
  String runTypeUnknown(String type) {
    return 'Unknown launch type: $type';
  }

  @override
  String runTypeUnavailable(String type) {
    return 'Launch type \"$type\" is not available on this target';
  }

  @override
  String runTypeUnavailableRemote(String type) {
    return 'Launch type \"$type\" is not available on remote targets';
  }

  @override
  String get runConfigureLaunchItems => 'Configure launch configurations';

  @override
  String get runConfigurationsEmpty => 'No launch configurations yet';

  @override
  String get runEditConfigurations => 'Edit configuration';

  @override
  String get runAddConfiguration => 'Add configuration';

  @override
  String get runDeleteConfiguration => 'Delete';

  @override
  String runDeleteConfigurationConfirm(String name) {
    return 'Delete configuration \"$name\"?';
  }

  @override
  String get runStopAndDelete => 'Stop and delete';

  @override
  String get runApply => 'Apply';

  @override
  String get runDiscard => 'Discard';

  @override
  String get runDiscardChangesTitle => 'Discard changes?';

  @override
  String get runDiscardChangesMessage =>
      'You have unsaved changes to this configuration. Apply them, discard them, or cancel?';

  @override
  String get runSelectFolder => 'Select folder';

  @override
  String get runConfigurationName => 'Name';

  @override
  String get runConfigurationType => 'Type';

  @override
  String get runTypeShellScript => 'Shell Script';

  @override
  String get runFieldCommand => 'Command';

  @override
  String get runFieldArgs => 'Arguments';

  @override
  String get runFieldEnv => 'Environment variables';

  @override
  String get runFieldCwd => 'Working directory';

  @override
  String get runFieldShell => 'Run in shell';

  @override
  String get runFieldScriptPath => 'Script path';

  @override
  String get runFieldScriptText => 'Script text';

  @override
  String get runFieldExecute => 'Execute';

  @override
  String get runFieldScriptOptions => 'Script options';

  @override
  String get runFieldInterpreterPath => 'Interpreter path';

  @override
  String get runFieldInterpreterOptions => 'Interpreter options';

  @override
  String get runFieldExecuteInTerminal => 'Execute in the terminal';

  @override
  String get runFieldAllowMultipleInstances => 'Allow multiple instances';

  @override
  String get runFieldActivateToolWindow => 'Activate tool window';

  @override
  String get runFieldFocusToolWindow => 'Focus tool window';

  @override
  String get runExecuteScriptFile => 'Script file';

  @override
  String get runExecuteScriptText => 'Script text';

  @override
  String get runValidationEnvMustBeStringMap =>
      'Environment must be a map of strings';

  @override
  String get runValidationCwdMustBeString =>
      'Working directory must be a string';

  @override
  String get runValidationConfigurationMustBeMap =>
      'Configuration must be a map';

  @override
  String get runValidationExecuteRequired => 'Execute mode is required';

  @override
  String get runValidationExecuteInvalid =>
      'Execute must be Script file or Script text';

  @override
  String get runValidationScriptPathRequired => 'Script path is required';

  @override
  String get runValidationScriptTextRequired => 'Script text is required';

  @override
  String get runValidationInterpreterPathMustBeString =>
      'Interpreter path must be a string';

  @override
  String get runValidationExecuteInTerminalMustBeBoolean =>
      'Execute in the terminal must be a boolean';

  @override
  String get runValidationAllowMultipleInstancesMustBeBoolean =>
      'Allow multiple instances must be a boolean';

  @override
  String get runValidationActivateToolWindowMustBeBoolean =>
      'Activate tool window must be a boolean';

  @override
  String get runValidationFocusToolWindowMustBeBoolean =>
      'Focus tool window must be a boolean';

  @override
  String get shortcutsRunSelected => 'Run Selected Configuration';

  @override
  String get shortcutsRunStop => 'Stop Run';

  @override
  String get shortcutsRunRestart => 'Restart Run';

  @override
  String get shortcutsCategoryRun => 'Run';

  @override
  String get shortcutsCommandPalette => 'Command Palette';

  @override
  String get commandPaletteSearchHint => 'Type a command…';

  @override
  String get commandPaletteEmpty => 'No matching commands';

  @override
  String get shortcutsTerminalSplitRight => 'Split Terminal Right';

  @override
  String get shortcutsTerminalSplitDown => 'Split Terminal Down';

  @override
  String get shortcutsTerminalFocusNextPane => 'Focus Next Pane';

  @override
  String get shortcutsTerminalFocusPrevPane => 'Focus Previous Pane';

  @override
  String get shortcutsTerminalFocusPaneLeft => 'Focus Pane Left';

  @override
  String get shortcutsTerminalFocusPaneRight => 'Focus Pane Right';

  @override
  String get shortcutsTerminalFocusPaneUp => 'Focus Pane Up';

  @override
  String get shortcutsTerminalFocusPaneDown => 'Focus Pane Down';

  @override
  String get shortcutsTerminalZoomPane => 'Toggle Pane Zoom';

  @override
  String get shortcutsTerminalEqualizePanes => 'Equalize Panes';

  @override
  String get shortcutsTerminalClosePane => 'Close Pane';

  @override
  String get shortcutsTerminalLayoutSingle => 'Layout: Single';

  @override
  String get shortcutsTerminalLayoutColumns2 => 'Layout: Two Columns';

  @override
  String get shortcutsTerminalLayoutColumns3 => 'Layout: Three Columns';

  @override
  String get shortcutsTerminalLayoutGrid => 'Layout: Grid';

  @override
  String get shortcutsTerminalLayoutMainStack => 'Layout: Main + Stack';

  @override
  String get shortcutsTerminalCommandLog => 'Show command log';

  @override
  String get shortcutsTerminalCommandHistory => 'Show command history';

  @override
  String get terminalColorSchemeTitle => 'Terminal color scheme';

  @override
  String get terminalColorSchemeDescription =>
      'Pick a built-in palette for embedded terminals, or tweak individual colors.';

  @override
  String get terminalColorSchemeGroupDark => 'Dark';

  @override
  String get terminalColorSchemeGroupLight => 'Light';

  @override
  String get terminalColorSchemeGroupLegacy => 'Adaptive & legacy';

  @override
  String terminalColorSchemeByAuthor(String author) {
    return 'by $author';
  }

  @override
  String get terminalColorPreviewTitle => 'Preview';

  @override
  String get terminalUseCustomColorsTitle => 'Use custom colors';

  @override
  String get terminalUseCustomColorsDescription =>
      'Override individual palette slots on top of the selected scheme.';

  @override
  String get terminalCustomColorsSectionTitle => 'Custom colors';

  @override
  String get terminalColorResetAll => 'Reset all';

  @override
  String get terminalColorResetSlot => 'Reset to scheme color';

  @override
  String get terminalColorInvalidHex => 'Enter #RRGGBB or #AARRGGBB';

  @override
  String get terminalSlotBackground => 'Background';

  @override
  String get terminalSlotForeground => 'Foreground';

  @override
  String get terminalSlotCursor => 'Cursor';

  @override
  String get terminalSlotSelection => 'Selection';

  @override
  String get terminalSlotSearchHit => 'Search match';

  @override
  String get terminalSlotSearchHitCurrent => 'Current match';

  @override
  String get terminalSlotSearchHitFg => 'Match text';

  @override
  String get terminalSlotAccent => 'Accent';

  @override
  String terminalSlotAnsiLabel(String index) {
    return 'ANSI $index';
  }

  @override
  String get terminalThemeImportAction => 'Import theme…';

  @override
  String get terminalThemeImportTitle => 'Import terminal theme';

  @override
  String get terminalThemeImportDescription =>
      'Paste an Alacritty TOML or Ghostty config below, or choose a file.';

  @override
  String get terminalThemeImportNameLabel => 'Theme name';

  @override
  String get terminalThemeImportSourceLabel => 'Theme file contents';

  @override
  String get terminalThemeImportChooseFile => 'Choose file…';

  @override
  String get terminalThemeImportConfirm => 'Import';

  @override
  String get terminalThemeImportFileReadFailed => 'Could not read that file.';

  @override
  String get terminalThemeImportEmptySource =>
      'Paste the theme contents first.';

  @override
  String get terminalThemeImportErrorFormat =>
      'Unrecognized format — expected Alacritty TOML ([colors.primary]) or Ghostty key = value lines.';

  @override
  String get terminalThemeImportErrorBackground =>
      'No usable background color in that file.';

  @override
  String get terminalThemeImportErrorForeground =>
      'No usable foreground color in that file.';

  @override
  String get terminalThemeImportErrorAnsi =>
      'Missing the normal ANSI colors (0-7).';

  @override
  String get terminalThemeImportSaveFailed =>
      'Could not save the imported theme.';

  @override
  String terminalThemeImportSuccess(String name) {
    return 'Imported “$name”.';
  }

  @override
  String terminalThemeImportDerived(String slots) {
    return 'Derived from the palette: $slots';
  }

  @override
  String get terminalColorSchemeGroupImported => 'Imported';

  @override
  String get terminalThemeDeleteTooltip => 'Delete imported theme';

  @override
  String get terminalThemeDeleteConfirmTitle => 'Delete imported theme?';

  @override
  String terminalThemeDeleteConfirmMessage(String name) {
    return '“$name” will be removed. Terminals using it fall back to the adaptive scheme.';
  }

  @override
  String get terminalThemeDeleteFailed => 'Could not delete that theme.';
}
