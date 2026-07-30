import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'copy'**
  String get copy;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage FlashskyAI team and model settings.'**
  String get settingsPageSubtitle;

  /// No description provided for @layout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layout;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @layoutPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Structure controls are global and apply across teams.'**
  String get layoutPageSubtitle;

  /// No description provided for @right.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get right;

  /// No description provided for @bottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get bottom;

  /// No description provided for @rightTools.
  ///
  /// In en, this message translates to:
  /// **'Right Tools'**
  String get rightTools;

  /// No description provided for @rightToolsPanelVisible.
  ///
  /// In en, this message translates to:
  /// **'Show tools panel'**
  String get rightToolsPanelVisible;

  /// No description provided for @rightToolsPanelHidden.
  ///
  /// In en, this message translates to:
  /// **'Hide tools panel'**
  String get rightToolsPanelHidden;

  /// No description provided for @sidebarPanelVisible.
  ///
  /// In en, this message translates to:
  /// **'Show sidebar'**
  String get sidebarPanelVisible;

  /// No description provided for @sidebarPanelHidden.
  ///
  /// In en, this message translates to:
  /// **'Hide sidebar'**
  String get sidebarPanelHidden;

  /// No description provided for @stacked.
  ///
  /// In en, this message translates to:
  /// **'Stacked'**
  String get stacked;

  /// No description provided for @tabs.
  ///
  /// In en, this message translates to:
  /// **'Tabs'**
  String get tabs;

  /// No description provided for @regionVisibility.
  ///
  /// In en, this message translates to:
  /// **'Region Visibility'**
  String get regionVisibility;

  /// No description provided for @visibilityMembersHint.
  ///
  /// In en, this message translates to:
  /// **'Show the member list next to tools or terminals.'**
  String get visibilityMembersHint;

  /// No description provided for @visibilityFileTreeHint.
  ///
  /// In en, this message translates to:
  /// **'Show the workspace file tree for quick navigation.'**
  String get visibilityFileTreeHint;

  /// No description provided for @visibilityGitHint.
  ///
  /// In en, this message translates to:
  /// **'Show the source control panel for the current repository.'**
  String get visibilityGitHint;

  /// No description provided for @extensionsSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get extensionsSettingsTitle;

  /// No description provided for @extensionsSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Install and enable external tools that augment your agents.'**
  String get extensionsSettingsDescription;

  /// No description provided for @extensionsNavInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get extensionsNavInstalled;

  /// No description provided for @extensionsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No extensions available'**
  String get extensionsEmptyTitle;

  /// No description provided for @extensionsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Extensions will appear here once the catalog loads.'**
  String get extensionsEmptyHint;

  /// No description provided for @extensionInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get extensionInstall;

  /// No description provided for @extensionUninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get extensionUninstall;

  /// No description provided for @extensionStatusNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get extensionStatusNotInstalled;

  /// No description provided for @extensionStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get extensionStatusReady;

  /// No description provided for @extensionStatusReadyVersion.
  ///
  /// In en, this message translates to:
  /// **'Ready ({version})'**
  String extensionStatusReadyVersion(String version);

  /// No description provided for @extensionStatusDependencyMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing dependency'**
  String get extensionStatusDependencyMissing;

  /// No description provided for @extensionStatusDependencyMissingNamed.
  ///
  /// In en, this message translates to:
  /// **'Missing: {deps}'**
  String extensionStatusDependencyMissingNamed(String deps);

  /// No description provided for @extensionDependencyMissingHint.
  ///
  /// In en, this message translates to:
  /// **'Needs {deps} on your PATH. Install it, then re-check.'**
  String extensionDependencyMissingHint(String deps);

  /// No description provided for @extensionCopyCommand.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get extensionCopyCommand;

  /// No description provided for @extensionCommandCopied.
  ///
  /// In en, this message translates to:
  /// **'Command copied to clipboard'**
  String get extensionCommandCopied;

  /// No description provided for @extensionRecheck.
  ///
  /// In en, this message translates to:
  /// **'Re-check'**
  String get extensionRecheck;

  /// No description provided for @extensionStatusVersionTooOld.
  ///
  /// In en, this message translates to:
  /// **'Installed version is too old'**
  String get extensionStatusVersionTooOld;

  /// No description provided for @themeModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get themeModeTitle;

  /// No description provided for @themeModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Light, dark, or match the operating system appearance.'**
  String get themeModeDescription;

  /// No description provided for @themeColorPresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme colors'**
  String get themeColorPresetTitle;

  /// No description provided for @themeColorPresetDescription.
  ///
  /// In en, this message translates to:
  /// **'Primary and accent colors for buttons, toggles, and highlights.'**
  String get themeColorPresetDescription;

  /// No description provided for @typographyScaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get typographyScaleTitle;

  /// No description provided for @typographyScaleDescription.
  ///
  /// In en, this message translates to:
  /// **'Size of UI text. Standard follows your system; does not change icons or spacing.'**
  String get typographyScaleDescription;

  /// No description provided for @typographyScaleCompact.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get typographyScaleCompact;

  /// No description provided for @typographyScaleStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get typographyScaleStandard;

  /// No description provided for @typographyScaleComfortable.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get typographyScaleComfortable;

  /// No description provided for @typographyScaleCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get typographyScaleCustom;

  /// No description provided for @typographyScaleCustomHint.
  ///
  /// In en, this message translates to:
  /// **'50–200'**
  String get typographyScaleCustomHint;

  /// No description provided for @fontUiTitle.
  ///
  /// In en, this message translates to:
  /// **'Interface font'**
  String get fontUiTitle;

  /// No description provided for @fontUiDescription.
  ///
  /// In en, this message translates to:
  /// **'UI text. System follows the OS default. Takes effect after restart.'**
  String get fontUiDescription;

  /// No description provided for @fontMonoTitle.
  ///
  /// In en, this message translates to:
  /// **'Monospace font'**
  String get fontMonoTitle;

  /// No description provided for @fontMonoDescription.
  ///
  /// In en, this message translates to:
  /// **'Terminal, editor, and diffs. Takes effect after restart.'**
  String get fontMonoDescription;

  /// No description provided for @fontChangeAppliesOnRestart.
  ///
  /// In en, this message translates to:
  /// **'Font saved. Restart TeamPilot to apply.'**
  String get fontChangeAppliesOnRestart;

  /// No description provided for @fontOptionSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get fontOptionSystem;

  /// No description provided for @fontOptionNotoSansSc.
  ///
  /// In en, this message translates to:
  /// **'Noto Sans SC'**
  String get fontOptionNotoSansSc;

  /// No description provided for @fontOptionJetbrainsMono.
  ///
  /// In en, this message translates to:
  /// **'JetBrains Mono'**
  String get fontOptionJetbrainsMono;

  /// No description provided for @fontOptionUbuntuSansMono.
  ///
  /// In en, this message translates to:
  /// **'Ubuntu Sans Mono'**
  String get fontOptionUbuntuSansMono;

  /// No description provided for @fontSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search fonts'**
  String get fontSearchHint;

  /// No description provided for @uiZoomTitle.
  ///
  /// In en, this message translates to:
  /// **'Interface zoom'**
  String get uiZoomTitle;

  /// No description provided for @uiZoomDescription.
  ///
  /// In en, this message translates to:
  /// **'Zoom the whole UI together — text, icons, and spacing. Standard follows your display scaling.'**
  String get uiZoomDescription;

  /// No description provided for @markdownOpenModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Markdown as'**
  String get markdownOpenModeTitle;

  /// No description provided for @markdownOpenModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Default view when opening .md files in the editor. Remember lasts for this app session only.'**
  String get markdownOpenModeDescription;

  /// No description provided for @markdownOpenModePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get markdownOpenModePreview;

  /// No description provided for @markdownOpenModeSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get markdownOpenModeSource;

  /// No description provided for @markdownOpenModeRemember.
  ///
  /// In en, this message translates to:
  /// **'Remember last'**
  String get markdownOpenModeRemember;

  /// No description provided for @thinkingProcessSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Thinking process'**
  String get thinkingProcessSectionTitle;

  /// No description provided for @cotExpandReasoningOnOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Expand reasoning when opening'**
  String get cotExpandReasoningOnOpenTitle;

  /// No description provided for @cotExpandReasoningOnOpenDescription.
  ///
  /// In en, this message translates to:
  /// **'When you open a thinking-process block, expand nested reasoning steps automatically.'**
  String get cotExpandReasoningOnOpenDescription;

  /// No description provided for @cotExpandToolsOnOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Expand tools when opening'**
  String get cotExpandToolsOnOpenTitle;

  /// No description provided for @cotExpandToolsOnOpenDescription.
  ///
  /// In en, this message translates to:
  /// **'When you open a thinking-process block, expand nested tool call details automatically.'**
  String get cotExpandToolsOnOpenDescription;

  /// No description provided for @markdownViewToggleSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get markdownViewToggleSource;

  /// No description provided for @markdownViewTogglePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get markdownViewTogglePreview;

  /// No description provided for @themePresetGraphite.
  ///
  /// In en, this message translates to:
  /// **'Graphite'**
  String get themePresetGraphite;

  /// No description provided for @themePresetOcean.
  ///
  /// In en, this message translates to:
  /// **'Ocean'**
  String get themePresetOcean;

  /// No description provided for @themePresetViolet.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get themePresetViolet;

  /// No description provided for @themePresetAmber.
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get themePresetAmber;

  /// No description provided for @themePresetForest.
  ///
  /// In en, this message translates to:
  /// **'Forest'**
  String get themePresetForest;

  /// Colour preset that derives the whole UI scheme from the active terminal theme.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get themePresetTerminal;

  /// No description provided for @languageDescription.
  ///
  /// In en, this message translates to:
  /// **'Language used for menus, buttons, and labels.'**
  String get languageDescription;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @workspaceEntryModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Startup view'**
  String get workspaceEntryModeTitle;

  /// No description provided for @workspaceEntryModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Where the app opens after launch.'**
  String get workspaceEntryModeDescription;

  /// No description provided for @workspaceEntryModeHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get workspaceEntryModeHome;

  /// No description provided for @workspaceEntryModeLastWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Last workspace'**
  String get workspaceEntryModeLastWorkspace;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get languageChinese;

  /// No description provided for @fileTree.
  ///
  /// In en, this message translates to:
  /// **'File Tree'**
  String get fileTree;

  /// No description provided for @sourceControl.
  ///
  /// In en, this message translates to:
  /// **'Source Control'**
  String get sourceControl;

  /// No description provided for @gitStagedChanges.
  ///
  /// In en, this message translates to:
  /// **'Staged Changes'**
  String get gitStagedChanges;

  /// No description provided for @gitChanges.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get gitChanges;

  /// No description provided for @gitNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get gitNoChanges;

  /// No description provided for @gitNotARepository.
  ///
  /// In en, this message translates to:
  /// **'This folder is not a Git repository'**
  String get gitNotARepository;

  /// No description provided for @gitNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Git was not found. Install Git to use source control.'**
  String get gitNotInstalled;

  /// No description provided for @gitCommit.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get gitCommit;

  /// No description provided for @gitCommitMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Message (commit to \"{branch}\")'**
  String gitCommitMessageHint(String branch);

  /// No description provided for @gitStage.
  ///
  /// In en, this message translates to:
  /// **'Stage changes'**
  String get gitStage;

  /// No description provided for @gitUnstage.
  ///
  /// In en, this message translates to:
  /// **'Unstage changes'**
  String get gitUnstage;

  /// No description provided for @gitStageAll.
  ///
  /// In en, this message translates to:
  /// **'Stage all changes'**
  String get gitStageAll;

  /// No description provided for @gitUnstageAll.
  ///
  /// In en, this message translates to:
  /// **'Unstage all changes'**
  String get gitUnstageAll;

  /// No description provided for @gitStageFolder.
  ///
  /// In en, this message translates to:
  /// **'Stage changes in folder'**
  String get gitStageFolder;

  /// No description provided for @gitUnstageFolder.
  ///
  /// In en, this message translates to:
  /// **'Unstage changes in folder'**
  String get gitUnstageFolder;

  /// No description provided for @treeExpandAllFolders.
  ///
  /// In en, this message translates to:
  /// **'Expand all folders'**
  String get treeExpandAllFolders;

  /// No description provided for @treeCollapseAllFolders.
  ///
  /// In en, this message translates to:
  /// **'Collapse all folders'**
  String get treeCollapseAllFolders;

  /// No description provided for @gitDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get gitDiscard;

  /// No description provided for @gitDiscardConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get gitDiscardConfirmTitle;

  /// No description provided for @gitDiscardConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Discard all changes in {path}? This cannot be undone.'**
  String gitDiscardConfirmBody(String path);

  /// No description provided for @gitPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get gitPush;

  /// No description provided for @gitPull.
  ///
  /// In en, this message translates to:
  /// **'Pull'**
  String get gitPull;

  /// No description provided for @gitRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get gitRefresh;

  /// No description provided for @gitSwitchBranch.
  ///
  /// In en, this message translates to:
  /// **'Switch branch'**
  String get gitSwitchBranch;

  /// No description provided for @gitCreateBranch.
  ///
  /// In en, this message translates to:
  /// **'Create branch'**
  String get gitCreateBranch;

  /// No description provided for @gitNewBranchHint.
  ///
  /// In en, this message translates to:
  /// **'New branch name'**
  String get gitNewBranchHint;

  /// No description provided for @gitError.
  ///
  /// In en, this message translates to:
  /// **'Git: {message}'**
  String gitError(String message);

  /// No description provided for @gitAheadBehind.
  ///
  /// In en, this message translates to:
  /// **'↑{ahead} ↓{behind}'**
  String gitAheadBehind(int ahead, int behind);

  /// No description provided for @filterFiles.
  ///
  /// In en, this message translates to:
  /// **'Filter files'**
  String get filterFiles;

  /// No description provided for @workspaces.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get workspaces;

  /// No description provided for @newWorkspace.
  ///
  /// In en, this message translates to:
  /// **'New Workspace'**
  String get newWorkspace;

  /// No description provided for @homeWorkspaceMainWindow.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get homeWorkspaceMainWindow;

  /// No description provided for @windowControlMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get windowControlMinimize;

  /// No description provided for @windowControlMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get windowControlMaximize;

  /// No description provided for @windowControlRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get windowControlRestore;

  /// No description provided for @windowControlClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get windowControlClose;

  /// No description provided for @windowControlAlwaysOnTop.
  ///
  /// In en, this message translates to:
  /// **'Always on top'**
  String get windowControlAlwaysOnTop;

  /// No description provided for @homeWorkspaceMyFavorites.
  ///
  /// In en, this message translates to:
  /// **'My favorites'**
  String get homeWorkspaceMyFavorites;

  /// No description provided for @homeWorkspaceRecentVisits.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get homeWorkspaceRecentVisits;

  /// No description provided for @homeWorkspaceAllWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'All workspaces'**
  String get homeWorkspaceAllWorkspaces;

  /// No description provided for @homeWorkspaceNoData.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get homeWorkspaceNoData;

  /// No description provided for @homeWorkspaceRecentlyClosed.
  ///
  /// In en, this message translates to:
  /// **'Recently closed'**
  String get homeWorkspaceRecentlyClosed;

  /// No description provided for @homeWorkspaceRecentlyClosedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recently closed workspaces'**
  String get homeWorkspaceRecentlyClosedEmpty;

  /// No description provided for @homeWorkspaceSessionsLabel.
  ///
  /// In en, this message translates to:
  /// **'sessions'**
  String get homeWorkspaceSessionsLabel;

  /// No description provided for @homeWorkspaceEmptyWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'No workspaces in this team yet'**
  String get homeWorkspaceEmptyWorkspaces;

  /// No description provided for @homeWorkspaceEmptyWorkspacesHint.
  ///
  /// In en, this message translates to:
  /// **'Create or import a workspace to get started'**
  String get homeWorkspaceEmptyWorkspacesHint;

  /// No description provided for @homeWorkspaceWorkspaceSort.
  ///
  /// In en, this message translates to:
  /// **'Sort workspaces'**
  String get homeWorkspaceWorkspaceSort;

  /// No description provided for @homeWorkspaceWorkspaceSortRecentlyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Recently updated'**
  String get homeWorkspaceWorkspaceSortRecentlyUpdated;

  /// No description provided for @homeWorkspaceWorkspaceSortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'Name (A–Z)'**
  String get homeWorkspaceWorkspaceSortNameAsc;

  /// No description provided for @homeWorkspaceWorkspaceSortNameDesc.
  ///
  /// In en, this message translates to:
  /// **'Name (Z–A)'**
  String get homeWorkspaceWorkspaceSortNameDesc;

  /// No description provided for @homeWorkspaceWorkspaceSortCreatedDesc.
  ///
  /// In en, this message translates to:
  /// **'Date created'**
  String get homeWorkspaceWorkspaceSortCreatedDesc;

  /// No description provided for @homeWorkspaceWorkspaceSortSessionCountDesc.
  ///
  /// In en, this message translates to:
  /// **'Session count'**
  String get homeWorkspaceWorkspaceSortSessionCountDesc;

  /// No description provided for @homeWorkspaceNewWorkspaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a working directory and name your workspace.'**
  String get homeWorkspaceNewWorkspaceSubtitle;

  /// No description provided for @homeWorkspaceNewWorkspaceDirectoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Workspace directory'**
  String get homeWorkspaceNewWorkspaceDirectoryLabel;

  /// No description provided for @homeWorkspaceNewWorkspaceChooseDirectory.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get homeWorkspaceNewWorkspaceChooseDirectory;

  /// No description provided for @homeWorkspaceNewWorkspaceDirectoryHint.
  ///
  /// In en, this message translates to:
  /// **'No directory selected yet'**
  String get homeWorkspaceNewWorkspaceDirectoryHint;

  /// No description provided for @homeWorkspaceNewWorkspaceNameHint.
  ///
  /// In en, this message translates to:
  /// **'Defaults to the folder name'**
  String get homeWorkspaceNewWorkspaceNameHint;

  /// No description provided for @homeWorkspaceCreateWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Create workspace'**
  String get homeWorkspaceCreateWorkspace;

  /// No description provided for @homeWorkspaceCloseWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Close workspace?'**
  String get homeWorkspaceCloseWorkspaceTitle;

  /// No description provided for @homeWorkspaceCloseWorkspaceMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Closing this tab will end 1 running session in this workspace.} other{Closing this tab will end {count} running sessions in this workspace.}}'**
  String homeWorkspaceCloseWorkspaceMessage(int count);

  /// No description provided for @homeWorkspaceCloseWorkspaceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Close & end sessions'**
  String get homeWorkspaceCloseWorkspaceConfirm;

  /// No description provided for @homeWorkspaceWorkspaceManagement.
  ///
  /// In en, this message translates to:
  /// **'Workspace management'**
  String get homeWorkspaceWorkspaceManagement;

  /// No description provided for @homeWorkspaceConversationsSection.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get homeWorkspaceConversationsSection;

  /// No description provided for @workspaceRunningSessionsSection.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get workspaceRunningSessionsSection;

  /// No description provided for @workspaceCliConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get workspaceCliConfigured;

  /// No description provided for @workspaceCliNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get workspaceCliNotConfigured;

  /// No description provided for @homeWorkspaceWorkspaceExtensions.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get homeWorkspaceWorkspaceExtensions;

  /// No description provided for @workspaceExtensionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Extensions for this workspace'**
  String get workspaceExtensionsTitle;

  /// No description provided for @workspaceExtensionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Override which extensions run for this workspace. Default follows the global setting.'**
  String get workspaceExtensionsSubtitle;

  /// No description provided for @workspaceExtensionEffectiveOn.
  ///
  /// In en, this message translates to:
  /// **'Enabled for this workspace'**
  String get workspaceExtensionEffectiveOn;

  /// No description provided for @workspaceExtensionEffectiveOff.
  ///
  /// In en, this message translates to:
  /// **'Disabled for this workspace'**
  String get workspaceExtensionEffectiveOff;

  /// No description provided for @homeWorkspaceWorkspaceSettings.
  ///
  /// In en, this message translates to:
  /// **'Workspace settings'**
  String get homeWorkspaceWorkspaceSettings;

  /// No description provided for @homeWorkspaceWorkspaceSettingsBasicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic information'**
  String get homeWorkspaceWorkspaceSettingsBasicInfo;

  /// No description provided for @homeWorkspaceWorkspaceId.
  ///
  /// In en, this message translates to:
  /// **'Workspace ID'**
  String get homeWorkspaceWorkspaceId;

  /// No description provided for @deleteWorkspaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Deletes this workspace and all conversations in it. This cannot be undone.'**
  String get deleteWorkspaceSubtitle;

  /// No description provided for @homeWorkspaceNewConversation.
  ///
  /// In en, this message translates to:
  /// **'New Conversation'**
  String get homeWorkspaceNewConversation;

  /// No description provided for @workbenchStripNewMenuTooltip.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get workbenchStripNewMenuTooltip;

  /// No description provided for @homeWorkspaceNoConversations.
  ///
  /// In en, this message translates to:
  /// **'No conversations in this workspace yet'**
  String get homeWorkspaceNoConversations;

  /// No description provided for @workspaceSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get workspaceSearchTitle;

  /// No description provided for @workspaceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search sessions and files'**
  String get workspaceSearchHint;

  /// No description provided for @workspaceSearchFilesSection.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get workspaceSearchFilesSection;

  /// No description provided for @workspaceSearchSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching files…'**
  String get workspaceSearchSearching;

  /// No description provided for @workspaceSearchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get workspaceSearchNoResults;

  /// No description provided for @workspaceSearchFilesTruncated.
  ///
  /// In en, this message translates to:
  /// **'More files match — refine your search'**
  String get workspaceSearchFilesTruncated;

  /// No description provided for @homeWorkspaceOpenWorkspaceInNewTab.
  ///
  /// In en, this message translates to:
  /// **'Open in new tab'**
  String get homeWorkspaceOpenWorkspaceInNewTab;

  /// No description provided for @homeWorkspaceFavoriteWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Favorite workspace'**
  String get homeWorkspaceFavoriteWorkspace;

  /// No description provided for @homeWorkspaceUnfavoriteWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get homeWorkspaceUnfavoriteWorkspace;

  /// No description provided for @homeWorkspaceRenameWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Rename workspace'**
  String get homeWorkspaceRenameWorkspace;

  /// No description provided for @homeWorkspaceCloneWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Clone workspace'**
  String get homeWorkspaceCloneWorkspace;

  /// No description provided for @homeWorkspaceCloneWorkspaceDisplayName.
  ///
  /// In en, this message translates to:
  /// **'{name} (copy)'**
  String homeWorkspaceCloneWorkspaceDisplayName(Object name);

  /// No description provided for @homeWorkspaceCloneWorkspaceSuccess.
  ///
  /// In en, this message translates to:
  /// **'Cloned \"{name}\".'**
  String homeWorkspaceCloneWorkspaceSuccess(Object name);

  /// No description provided for @homeWorkspaceCloneWorkspaceFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not clone workspace'**
  String get homeWorkspaceCloneWorkspaceFailed;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @workspacePrimaryPathRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a primary directory first.'**
  String get workspacePrimaryPathRequired;

  /// No description provided for @workspacePrimaryPathNotSelected.
  ///
  /// In en, this message translates to:
  /// **'No primary directory selected'**
  String get workspacePrimaryPathNotSelected;

  /// No description provided for @defaultNewChatSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get defaultNewChatSessionTitle;

  /// No description provided for @sessionIdleNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent ready'**
  String get sessionIdleNotificationTitle;

  /// No description provided for @sessionIdleNotificationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ready for your next message'**
  String get sessionIdleNotificationSubtitle;

  /// No description provided for @sessionStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting session…'**
  String get sessionStarting;

  /// No description provided for @agentPermissionAttentionBanner.
  ///
  /// In en, this message translates to:
  /// **'This agent needs confirmation in the Terminal.'**
  String get agentPermissionAttentionBanner;

  /// No description provided for @agentPermissionOpenTerminal.
  ///
  /// In en, this message translates to:
  /// **'Open Terminal'**
  String get agentPermissionOpenTerminal;

  /// No description provided for @sessionWorkbenchShowChat.
  ///
  /// In en, this message translates to:
  /// **'Show Chat'**
  String get sessionWorkbenchShowChat;

  /// No description provided for @sessionWorkbenchShowTerminal.
  ///
  /// In en, this message translates to:
  /// **'Show Terminal'**
  String get sessionWorkbenchShowTerminal;

  /// No description provided for @workspaceChatLandingInputHint.
  ///
  /// In en, this message translates to:
  /// **'What can I help you with today? @ reference files, / invoke skills'**
  String get workspaceChatLandingInputHint;

  /// No description provided for @workspaceChatLandingBackToStart.
  ///
  /// In en, this message translates to:
  /// **'Back to start'**
  String get workspaceChatLandingBackToStart;

  /// No description provided for @workspaceChatLandingSelectProject.
  ///
  /// In en, this message translates to:
  /// **'Select project >'**
  String get workspaceChatLandingSelectProject;

  /// No description provided for @workspaceChatLandingSelectWorktree.
  ///
  /// In en, this message translates to:
  /// **'Select worktree >'**
  String get workspaceChatLandingSelectWorktree;

  /// No description provided for @workspaceChatLandingFullAccessPermissions.
  ///
  /// In en, this message translates to:
  /// **'Full access permissions'**
  String get workspaceChatLandingFullAccessPermissions;

  /// No description provided for @workspaceChatLandingDefaultPermissions.
  ///
  /// In en, this message translates to:
  /// **'Default permissions'**
  String get workspaceChatLandingDefaultPermissions;

  /// No description provided for @workspaceChatLandingAttach.
  ///
  /// In en, this message translates to:
  /// **'Attach files'**
  String get workspaceChatLandingAttach;

  /// No description provided for @workspaceChatLandingVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice input'**
  String get workspaceChatLandingVoice;

  /// No description provided for @workspaceChatLandingVoiceCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel recording'**
  String get workspaceChatLandingVoiceCancel;

  /// No description provided for @workspaceChatLandingVoiceStop.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get workspaceChatLandingVoiceStop;

  /// No description provided for @workspaceChatLandingVoiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Voice input is not available on this device'**
  String get workspaceChatLandingVoiceUnavailable;

  /// No description provided for @workspaceChatLandingVoicePermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission denied'**
  String get workspaceChatLandingVoicePermissionDenied;

  /// No description provided for @sessionRetryButton.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get sessionRetryButton;

  /// No description provided for @copyFolderPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Folder Path'**
  String get copyFolderPath;

  /// No description provided for @pathCopied.
  ///
  /// In en, this message translates to:
  /// **'Path copied: {path}'**
  String pathCopied(String path);

  /// No description provided for @workspaceDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspace Details'**
  String get workspaceDetailsTitle;

  /// No description provided for @addWorkspaceDirectory.
  ///
  /// In en, this message translates to:
  /// **'Add directory'**
  String get addWorkspaceDirectory;

  /// No description provided for @workspaceDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get workspaceDisplayName;

  /// No description provided for @workspaceIcon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get workspaceIcon;

  /// No description provided for @workspaceIconPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose workspace icon'**
  String get workspaceIconPickerTitle;

  /// No description provided for @workspaceIconUseDefault.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get workspaceIconUseDefault;

  /// No description provided for @workspaceIconUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload icon'**
  String get workspaceIconUpload;

  /// No description provided for @workspaceSessionCount.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get workspaceSessionCount;

  /// No description provided for @workspaceCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get workspaceCreatedAt;

  /// No description provided for @workspaceUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get workspaceUpdatedAt;

  /// No description provided for @workspaceDirectoryAlreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'This directory is already in the workspace.'**
  String get workspaceDirectoryAlreadyAdded;

  /// No description provided for @remoteDirectoryBrowserTitle.
  ///
  /// In en, this message translates to:
  /// **'Browse remote directory'**
  String get remoteDirectoryBrowserTitle;

  /// No description provided for @remoteDirectoryBrowserUpOneLevel.
  ///
  /// In en, this message translates to:
  /// **'Up one level'**
  String get remoteDirectoryBrowserUpOneLevel;

  /// No description provided for @remoteDirectoryBrowserUseThisDirectory.
  ///
  /// In en, this message translates to:
  /// **'Use this directory'**
  String get remoteDirectoryBrowserUseThisDirectory;

  /// No description provided for @remoteDirectoryBrowserTypePathLabel.
  ///
  /// In en, this message translates to:
  /// **'Or type a path'**
  String get remoteDirectoryBrowserTypePathLabel;

  /// No description provided for @remoteDirectoryBrowserTypePathHint.
  ///
  /// In en, this message translates to:
  /// **'~/work/workspace'**
  String get remoteDirectoryBrowserTypePathHint;

  /// No description provided for @remoteDirectoryBrowserUseTypedPath.
  ///
  /// In en, this message translates to:
  /// **'Use path'**
  String get remoteDirectoryBrowserUseTypedPath;

  /// No description provided for @remoteDirectoryBrowserError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the remote directory. You can still type a path below.'**
  String get remoteDirectoryBrowserError;

  /// No description provided for @remoteDirectoryBrowserEmpty.
  ///
  /// In en, this message translates to:
  /// **'No subdirectories here'**
  String get remoteDirectoryBrowserEmpty;

  /// No description provided for @deleteWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Delete Workspace'**
  String get deleteWorkspace;

  /// No description provided for @deleteWorkspaceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete workspace \"{name}\" and all its sessions? This cannot be undone.'**
  String deleteWorkspaceConfirm(String name);

  /// No description provided for @renameConversation.
  ///
  /// In en, this message translates to:
  /// **'Rename conversation'**
  String get renameConversation;

  /// No description provided for @deleteConversation.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation'**
  String get deleteConversation;

  /// No description provided for @pinConversation.
  ///
  /// In en, this message translates to:
  /// **'Pin conversation'**
  String get pinConversation;

  /// No description provided for @unpinConversation.
  ///
  /// In en, this message translates to:
  /// **'Unpin conversation'**
  String get unpinConversation;

  /// No description provided for @sessionSortRecentlyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Recently updated'**
  String get sessionSortRecentlyUpdated;

  /// No description provided for @sessionSortCreatedDesc.
  ///
  /// In en, this message translates to:
  /// **'Date created'**
  String get sessionSortCreatedDesc;

  /// No description provided for @sessionSortTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort conversations'**
  String get sessionSortTooltip;

  /// No description provided for @renameConversationTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename Conversation'**
  String get renameConversationTitle;

  /// No description provided for @conversationName.
  ///
  /// In en, this message translates to:
  /// **'Conversation name'**
  String get conversationName;

  /// No description provided for @closeTab.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeTab;

  /// No description provided for @closeOtherTabs.
  ///
  /// In en, this message translates to:
  /// **'Close Others'**
  String get closeOtherTabs;

  /// No description provided for @closeRightTabs.
  ///
  /// In en, this message translates to:
  /// **'Close to the Right'**
  String get closeRightTabs;

  /// No description provided for @session.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get session;

  /// No description provided for @sessionPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure shell session launch, terminal behavior, and storage backend.'**
  String get sessionPageSubtitle;

  /// No description provided for @sshProfilesSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'SSH servers'**
  String get sshProfilesSettingsTitle;

  /// No description provided for @sshProfilesPageTitle.
  ///
  /// In en, this message translates to:
  /// **'SSH remote hosts'**
  String get sshProfilesPageTitle;

  /// No description provided for @sshProfilesPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to existing machines over SSH for files, terminals, Git, and workspaces.'**
  String get sshProfilesPageSubtitle;

  /// No description provided for @sshProfilesTargetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Targets'**
  String get sshProfilesTargetsTitle;

  /// No description provided for @sshProfilesTargetsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add a remote host to connect from TeamPilot.'**
  String get sshProfilesTargetsSubtitle;

  /// No description provided for @sshProfilesImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get sshProfilesImport;

  /// No description provided for @sshProfilesImportUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Import from ~/.ssh/config is not available yet.'**
  String get sshProfilesImportUnavailable;

  /// No description provided for @sshProfilesAddTarget.
  ///
  /// In en, this message translates to:
  /// **'Add target'**
  String get sshProfilesAddTarget;

  /// No description provided for @sshProfilesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No SSH targets configured.'**
  String get sshProfilesEmpty;

  /// No description provided for @sshProfileStatusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get sshProfileStatusDisconnected;

  /// No description provided for @sshProfileStatusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get sshProfileStatusConnecting;

  /// No description provided for @sshProfileStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get sshProfileStatusConnected;

  /// No description provided for @sshProfileStatusError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get sshProfileStatusError;

  /// No description provided for @sshProfileStatusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get sshProfileStatusReconnecting;

  /// No description provided for @sshProfileStatusAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed'**
  String get sshProfileStatusAuthFailed;

  /// No description provided for @sshHostsPillCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 host} other{{count} hosts}}'**
  String sshHostsPillCount(int count);

  /// No description provided for @sshHostsPillConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get sshHostsPillConnecting;

  /// No description provided for @sshHostsPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote Hosts'**
  String get sshHostsPanelTitle;

  /// No description provided for @sshHostsRowKind.
  ///
  /// In en, this message translates to:
  /// **'SSH Host'**
  String get sshHostsRowKind;

  /// No description provided for @sshHostsManage.
  ///
  /// In en, this message translates to:
  /// **'Manage Remote Hosts…'**
  String get sshHostsManage;

  /// No description provided for @sshProfileTest.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get sshProfileTest;

  /// No description provided for @sshProfileConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get sshProfileConnect;

  /// No description provided for @sshProfileDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get sshProfileDisconnect;

  /// No description provided for @sshProfileEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get sshProfileEdit;

  /// No description provided for @sshProfileDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get sshProfileDelete;

  /// No description provided for @sshProfileRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get sshProfileRefresh;

  /// No description provided for @sshProfileTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connection successful'**
  String get sshProfileTestSuccess;

  /// No description provided for @sshProfileTestFailedHostKey.
  ///
  /// In en, this message translates to:
  /// **'Host key was not trusted'**
  String get sshProfileTestFailedHostKey;

  /// No description provided for @sshProfileTestFailedAuth.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed'**
  String get sshProfileTestFailedAuth;

  /// No description provided for @sshProfileTestFailedAborted.
  ///
  /// In en, this message translates to:
  /// **'Connection closed before login: {detail}'**
  String sshProfileTestFailedAborted(String detail);

  /// No description provided for @sshProfileTestFailedDetail.
  ///
  /// In en, this message translates to:
  /// **'Connection test failed: {detail}'**
  String sshProfileTestFailedDetail(String detail);

  /// No description provided for @sshProfileConnectSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connected to {host}'**
  String sshProfileConnectSuccess(String host);

  /// No description provided for @sshHostKeyUnknownTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify SSH host key'**
  String get sshHostKeyUnknownTitle;

  /// No description provided for @sshHostKeyUnknownBody.
  ///
  /// In en, this message translates to:
  /// **'TeamPilot has not seen {host} before. Confirm the fingerprint matches this machine before trusting it.'**
  String sshHostKeyUnknownBody(String host);

  /// No description provided for @sshHostKeyMismatchTitle.
  ///
  /// In en, this message translates to:
  /// **'SSH host key changed'**
  String get sshHostKeyMismatchTitle;

  /// No description provided for @sshHostKeyMismatchBody.
  ///
  /// In en, this message translates to:
  /// **'The host key for {host} does not match the one TeamPilot saved earlier. This can happen after a reinstall — or if someone is intercepting the connection.'**
  String sshHostKeyMismatchBody(String host);

  /// No description provided for @sshHostKeyFingerprintLabel.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint'**
  String get sshHostKeyFingerprintLabel;

  /// No description provided for @sshHostKeyPreviousFingerprintLabel.
  ///
  /// In en, this message translates to:
  /// **'Previously trusted'**
  String get sshHostKeyPreviousFingerprintLabel;

  /// No description provided for @sshHostKeyKeyTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Key type: {keyType}'**
  String sshHostKeyKeyTypeLabel(String keyType);

  /// No description provided for @sshHostKeyTrust.
  ///
  /// In en, this message translates to:
  /// **'Trust and continue'**
  String get sshHostKeyTrust;

  /// No description provided for @sshHostKeyReplaceTrust.
  ///
  /// In en, this message translates to:
  /// **'Replace and trust'**
  String get sshHostKeyReplaceTrust;

  /// No description provided for @sshProfileFormTitleNew.
  ///
  /// In en, this message translates to:
  /// **'New SSH target'**
  String get sshProfileFormTitleNew;

  /// No description provided for @sshProfileFormTitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit SSH target'**
  String get sshProfileFormTitleEdit;

  /// No description provided for @sshProfileFormLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get sshProfileFormLabel;

  /// No description provided for @sshProfileFormLabelHint.
  ///
  /// In en, this message translates to:
  /// **'My server'**
  String get sshProfileFormLabelHint;

  /// No description provided for @sshProfileFormHost.
  ///
  /// In en, this message translates to:
  /// **'Host or alias'**
  String get sshProfileFormHost;

  /// No description provided for @sshProfileFormHostHint.
  ///
  /// In en, this message translates to:
  /// **'server, deploy@server:2222'**
  String get sshProfileFormHostHint;

  /// No description provided for @sshProfileFormUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get sshProfileFormUsername;

  /// No description provided for @sshProfileFormUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'deploy'**
  String get sshProfileFormUsernameHint;

  /// No description provided for @sshProfileFormPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get sshProfileFormPort;

  /// No description provided for @sshProfileFormPortInvalid.
  ///
  /// In en, this message translates to:
  /// **'Port must be between 1 and 65535'**
  String get sshProfileFormPortInvalid;

  /// No description provided for @sshProfileFormIdentityFile.
  ///
  /// In en, this message translates to:
  /// **'Identity file'**
  String get sshProfileFormIdentityFile;

  /// No description provided for @sshProfileFormIdentityFileHint.
  ///
  /// In en, this message translates to:
  /// **'~/.ssh/id_ed25519'**
  String get sshProfileFormIdentityFileHint;

  /// No description provided for @sshProfileFormIdentityFileHelper.
  ///
  /// In en, this message translates to:
  /// **'Optional. Reads the private key from disk when set.'**
  String get sshProfileFormIdentityFileHelper;

  /// No description provided for @sshProfileFormIdentityFileBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse…'**
  String get sshProfileFormIdentityFileBrowse;

  /// No description provided for @sshProfileFormIdentityFileMissing.
  ///
  /// In en, this message translates to:
  /// **'Identity file not found'**
  String get sshProfileFormIdentityFileMissing;

  /// No description provided for @sshProfileFormPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Key passphrase'**
  String get sshProfileFormPassphrase;

  /// No description provided for @sshProfileFormPassphraseHint.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get sshProfileFormPassphraseHint;

  /// No description provided for @sshProfileFormPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get sshProfileFormPassword;

  /// No description provided for @sshProfileFormPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Use when no identity file is set'**
  String get sshProfileFormPasswordHint;

  /// No description provided for @sshProfileFormPasswordHintEdit.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep saved password'**
  String get sshProfileFormPasswordHintEdit;

  /// No description provided for @sshProfileFormPasswordHelper.
  ///
  /// In en, this message translates to:
  /// **'Optional if an identity file is provided.'**
  String get sshProfileFormPasswordHelper;

  /// No description provided for @sshProfileFormCredentialRequired.
  ///
  /// In en, this message translates to:
  /// **'Provide an identity file or password.'**
  String get sshProfileFormCredentialRequired;

  /// No description provided for @sshProfileFormFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get sshProfileFormFieldRequired;

  /// No description provided for @sshProfileSelectorManage.
  ///
  /// In en, this message translates to:
  /// **'Manage SSH servers…'**
  String get sshProfileSelectorManage;

  /// No description provided for @sshDefaultWorkingDirectoryTitle.
  ///
  /// In en, this message translates to:
  /// **'SSH default working directory'**
  String get sshDefaultWorkingDirectoryTitle;

  /// No description provided for @sshDefaultWorkingDirectorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remote working directory used when the SSH launch has no workspace path; leave empty to skip changing directory.'**
  String get sshDefaultWorkingDirectorySubtitle;

  /// No description provided for @cliExecutablePathBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse…'**
  String get cliExecutablePathBrowse;

  /// No description provided for @cliExecutablePathReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get cliExecutablePathReset;

  /// No description provided for @cliExecutablePathUsing.
  ///
  /// In en, this message translates to:
  /// **'Using: '**
  String get cliExecutablePathUsing;

  /// No description provided for @cliInstallButton.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get cliInstallButton;

  /// No description provided for @cliInstallInstalling.
  ///
  /// In en, this message translates to:
  /// **'Installing…'**
  String get cliInstallInstalling;

  /// No description provided for @cliInstallProgressCheckingNpm.
  ///
  /// In en, this message translates to:
  /// **'Checking for npm…'**
  String get cliInstallProgressCheckingNpm;

  /// No description provided for @cliInstallProgressInstallingCli.
  ///
  /// In en, this message translates to:
  /// **'Installing CLI…'**
  String get cliInstallProgressInstallingCli;

  /// No description provided for @cliInstallProgressLocatingExecutable.
  ///
  /// In en, this message translates to:
  /// **'Locating CLI executable…'**
  String get cliInstallProgressLocatingExecutable;

  /// No description provided for @terminalFind.
  ///
  /// In en, this message translates to:
  /// **'Find in terminal'**
  String get terminalFind;

  /// No description provided for @terminalFindNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get terminalFindNoResults;

  /// Shown when a dragged file lives on a different machine than the terminal it was dropped on.
  ///
  /// In en, this message translates to:
  /// **'Can\'t drop a local file onto a remote terminal'**
  String get terminalDropCrossMachineRejected;

  /// No description provided for @editorSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get editorSave;

  /// No description provided for @editorCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get editorCut;

  /// No description provided for @editorCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get editorCopy;

  /// No description provided for @editorCopyAsAiContext.
  ///
  /// In en, this message translates to:
  /// **'Copy as AI context'**
  String get editorCopyAsAiContext;

  /// No description provided for @selectionAskAi.
  ///
  /// In en, this message translates to:
  /// **'Ask AI…'**
  String get selectionAskAi;

  /// No description provided for @editorPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get editorPaste;

  /// No description provided for @editorSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get editorSelectAll;

  /// No description provided for @editorUndoEdit.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get editorUndoEdit;

  /// No description provided for @editorRedoEdit.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get editorRedoEdit;

  /// No description provided for @editorRevertChanges.
  ///
  /// In en, this message translates to:
  /// **'Revert changes'**
  String get editorRevertChanges;

  /// No description provided for @editorUnsavedChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get editorUnsavedChangesTitle;

  /// No description provided for @editorUnsavedChangesDiscardMultiple.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes in {count} file(s)?'**
  String editorUnsavedChangesDiscardMultiple(int count);

  /// No description provided for @editorDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get editorDiscard;

  /// No description provided for @editorNotReady.
  ///
  /// In en, this message translates to:
  /// **'Editor not ready'**
  String get editorNotReady;

  /// No description provided for @editorBinaryFileHint.
  ///
  /// In en, this message translates to:
  /// **'Binary files open with the system default app.'**
  String get editorBinaryFileHint;

  /// No description provided for @editorFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found'**
  String get editorFileNotFound;

  /// No description provided for @editorFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'File is too large to edit in TeamPilot (max 2 MB).'**
  String get editorFileTooLarge;

  /// No description provided for @editorImageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Image is too large to preview in TeamPilot (max 25 MB).'**
  String get editorImageTooLarge;

  /// No description provided for @editorImageDecodeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not decode this image.'**
  String get editorImageDecodeFailed;

  /// No description provided for @editorCouldNotReadFile.
  ///
  /// In en, this message translates to:
  /// **'Could not read file'**
  String get editorCouldNotReadFile;

  /// No description provided for @editorFileReadOnly.
  ///
  /// In en, this message translates to:
  /// **'File is read-only'**
  String get editorFileReadOnly;

  /// No description provided for @editorSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String editorSaveFailed(String error);

  /// No description provided for @fileTreeRevealActiveFile.
  ///
  /// In en, this message translates to:
  /// **'Reveal active file'**
  String get fileTreeRevealActiveFile;

  /// No description provided for @fileTreeRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get fileTreeRefresh;

  /// No description provided for @fileTreeShowFilter.
  ///
  /// In en, this message translates to:
  /// **'Show file filter'**
  String get fileTreeShowFilter;

  /// No description provided for @fileTreeHideFilter.
  ///
  /// In en, this message translates to:
  /// **'Hide file filter'**
  String get fileTreeHideFilter;

  /// No description provided for @fileTreeRevealFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot reveal this file in the file tree'**
  String get fileTreeRevealFailed;

  /// No description provided for @fileTreeOpenWithSystemApp.
  ///
  /// In en, this message translates to:
  /// **'Open with system app'**
  String get fileTreeOpenWithSystemApp;

  /// No description provided for @fileTreeCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get fileTreeCopyPath;

  /// No description provided for @fileTreeDeleteItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get fileTreeDeleteItemTitle;

  /// No description provided for @fileTreeDeleteItemConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String fileTreeDeleteItemConfirm(String name);

  /// No description provided for @fileTreeNewFile.
  ///
  /// In en, this message translates to:
  /// **'New File'**
  String get fileTreeNewFile;

  /// No description provided for @fileTreeNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get fileTreeNewFolder;

  /// No description provided for @fileTreeCreateNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fileTreeCreateNameHint;

  /// No description provided for @fileTreeCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get fileTreeCut;

  /// No description provided for @fileTreeCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get fileTreeCopy;

  /// No description provided for @fileTreePaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get fileTreePaste;

  /// No description provided for @fileTreeRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get fileTreeRename;

  /// No description provided for @fileTreeRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get fileTreeRenameTitle;

  /// No description provided for @fileTreeOpenInFileManager.
  ///
  /// In en, this message translates to:
  /// **'Reveal in File Manager'**
  String get fileTreeOpenInFileManager;

  /// No description provided for @fileTreeOpenInTerminal.
  ///
  /// In en, this message translates to:
  /// **'Open in Terminal'**
  String get fileTreeOpenInTerminal;

  /// No description provided for @fileTreePasteDone.
  ///
  /// In en, this message translates to:
  /// **'Pasted'**
  String get fileTreePasteDone;

  /// No description provided for @fileTreeFileCreated.
  ///
  /// In en, this message translates to:
  /// **'File created'**
  String get fileTreeFileCreated;

  /// No description provided for @fileTreeFolderCreated.
  ///
  /// In en, this message translates to:
  /// **'Folder created'**
  String get fileTreeFolderCreated;

  /// No description provided for @fileTreeRenameDone.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get fileTreeRenameDone;

  /// No description provided for @fileTreeDeleteDone.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get fileTreeDeleteDone;

  /// No description provided for @fileTreeInvalidName.
  ///
  /// In en, this message translates to:
  /// **'Invalid name'**
  String get fileTreeInvalidName;

  /// No description provided for @fileTreeItemExists.
  ///
  /// In en, this message translates to:
  /// **'An item with that name already exists'**
  String get fileTreeItemExists;

  /// No description provided for @fileTreeSourceMissing.
  ///
  /// In en, this message translates to:
  /// **'The copied item no longer exists'**
  String get fileTreeSourceMissing;

  /// No description provided for @fileTreeInvalidPasteTarget.
  ///
  /// In en, this message translates to:
  /// **'Cannot paste here'**
  String get fileTreeInvalidPasteTarget;

  /// No description provided for @fileTreeOpenInTerminalFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open a terminal'**
  String get fileTreeOpenInTerminalFailed;

  /// No description provided for @terminalOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get terminalOpenLink;

  /// No description provided for @terminalExportScrollback.
  ///
  /// In en, this message translates to:
  /// **'Export scrollback…'**
  String get terminalExportScrollback;

  /// No description provided for @terminalCopySelectHint.
  ///
  /// In en, this message translates to:
  /// **'Shift+drag to copy'**
  String get terminalCopySelectHint;

  /// No description provided for @workspaceTerminalNoWorkingDirectory.
  ///
  /// In en, this message translates to:
  /// **'Connect a session to open the shell terminal'**
  String get workspaceTerminalNoWorkingDirectory;

  /// No description provided for @workspaceTerminalNewSession.
  ///
  /// In en, this message translates to:
  /// **'New terminal'**
  String get workspaceTerminalNewSession;

  /// No description provided for @workspaceTerminalNewSshSession.
  ///
  /// In en, this message translates to:
  /// **'New SSH Session…'**
  String get workspaceTerminalNewSshSession;

  /// No description provided for @workspaceTerminalSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get workspaceTerminalSettings;

  /// No description provided for @workspaceTerminalThemeAdaptive.
  ///
  /// In en, this message translates to:
  /// **'Match app theme'**
  String get workspaceTerminalThemeAdaptive;

  /// No description provided for @workspaceTerminalThemeClassicDark.
  ///
  /// In en, this message translates to:
  /// **'Classic dark'**
  String get workspaceTerminalThemeClassicDark;

  /// No description provided for @workspaceTerminalThemeHighContrast.
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get workspaceTerminalThemeHighContrast;

  /// No description provided for @workspaceTerminalSshConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'SSH profile not found or connection failed'**
  String get workspaceTerminalSshConnectFailed;

  /// No description provided for @workspaceToolsResolveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open workspace tools'**
  String get workspaceToolsResolveFailed;

  /// No description provided for @workspaceToolsResolveFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Check that remote machines are reachable, then try again.'**
  String get workspaceToolsResolveFailedHint;

  /// No description provided for @workspaceTerminalSplitRight.
  ///
  /// In en, this message translates to:
  /// **'Split right'**
  String get workspaceTerminalSplitRight;

  /// No description provided for @workspaceTerminalSplitDown.
  ///
  /// In en, this message translates to:
  /// **'Split down'**
  String get workspaceTerminalSplitDown;

  /// No description provided for @workspaceTerminalLayout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get workspaceTerminalLayout;

  /// No description provided for @workspaceTerminalLayoutSingle.
  ///
  /// In en, this message translates to:
  /// **'Single pane'**
  String get workspaceTerminalLayoutSingle;

  /// No description provided for @workspaceTerminalLayoutColumns2.
  ///
  /// In en, this message translates to:
  /// **'2 columns'**
  String get workspaceTerminalLayoutColumns2;

  /// No description provided for @workspaceTerminalLayoutColumns3.
  ///
  /// In en, this message translates to:
  /// **'3 columns'**
  String get workspaceTerminalLayoutColumns3;

  /// No description provided for @workspaceTerminalLayoutGrid.
  ///
  /// In en, this message translates to:
  /// **'2×2 grid'**
  String get workspaceTerminalLayoutGrid;

  /// No description provided for @workspaceTerminalLayoutMainStack.
  ///
  /// In en, this message translates to:
  /// **'Main + stack'**
  String get workspaceTerminalLayoutMainStack;

  /// No description provided for @workspaceTerminalEqualize.
  ///
  /// In en, this message translates to:
  /// **'Equalize panes'**
  String get workspaceTerminalEqualize;

  /// No description provided for @workspaceTerminalZoomPane.
  ///
  /// In en, this message translates to:
  /// **'Zoom pane'**
  String get workspaceTerminalZoomPane;

  /// No description provided for @workspaceTerminalUnzoomPane.
  ///
  /// In en, this message translates to:
  /// **'Unzoom pane'**
  String get workspaceTerminalUnzoomPane;

  /// No description provided for @workspaceTerminalClosePane.
  ///
  /// In en, this message translates to:
  /// **'Close pane'**
  String get workspaceTerminalClosePane;

  /// No description provided for @workspaceTerminalCommandLog.
  ///
  /// In en, this message translates to:
  /// **'Command log'**
  String get workspaceTerminalCommandLog;

  /// No description provided for @commandLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Command log'**
  String get commandLogTitle;

  /// No description provided for @commandLogRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commandLogRefresh;

  /// No description provided for @commandLogOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open log folder'**
  String get commandLogOpenFolder;

  /// No description provided for @commandLogClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commandLogClose;

  /// No description provided for @commandLogAllWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'All workspaces'**
  String get commandLogAllWorkspaces;

  /// No description provided for @commandLogAllSurfaces.
  ///
  /// In en, this message translates to:
  /// **'All tabs'**
  String get commandLogAllSurfaces;

  /// No description provided for @commandLogAllPanes.
  ///
  /// In en, this message translates to:
  /// **'All panes'**
  String get commandLogAllPanes;

  /// No description provided for @commandLogSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search command or directory'**
  String get commandLogSearchHint;

  /// No description provided for @commandLogClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get commandLogClearFilters;

  /// No description provided for @commandLogColumnTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get commandLogColumnTime;

  /// No description provided for @commandLogColumnWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get commandLogColumnWorkspace;

  /// No description provided for @commandLogColumnSurface.
  ///
  /// In en, this message translates to:
  /// **'Tab'**
  String get commandLogColumnSurface;

  /// No description provided for @commandLogColumnPane.
  ///
  /// In en, this message translates to:
  /// **'Pane'**
  String get commandLogColumnPane;

  /// No description provided for @commandLogColumnCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get commandLogColumnCommand;

  /// No description provided for @commandLogColumnDirectory.
  ///
  /// In en, this message translates to:
  /// **'Directory'**
  String get commandLogColumnDirectory;

  /// No description provided for @commandLogColumnExitCode.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get commandLogColumnExitCode;

  /// No description provided for @commandLogColumnDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get commandLogColumnDuration;

  /// No description provided for @commandLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No commands recorded yet. Commands are logged once the shell reports prompt markers (OSC 133).'**
  String get commandLogEmpty;

  /// No description provided for @commandLogNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No commands match the current filters'**
  String get commandLogNoMatches;

  /// No description provided for @commandLogEntryCount.
  ///
  /// In en, this message translates to:
  /// **'{count} entries'**
  String commandLogEntryCount(int count);

  /// No description provided for @commandLogSkippedLines.
  ///
  /// In en, this message translates to:
  /// **'{count} unreadable lines skipped'**
  String commandLogSkippedLines(int count);

  /// No description provided for @commandLogCopyCommand.
  ///
  /// In en, this message translates to:
  /// **'Copy command'**
  String get commandLogCopyCommand;

  /// No description provided for @commandLogCopied.
  ///
  /// In en, this message translates to:
  /// **'Command copied'**
  String get commandLogCopied;

  /// No description provided for @commandLogInsertIntoPane.
  ///
  /// In en, this message translates to:
  /// **'Insert into pane'**
  String get commandLogInsertIntoPane;

  /// No description provided for @commandLogRunInPane.
  ///
  /// In en, this message translates to:
  /// **'Run in pane'**
  String get commandLogRunInPane;

  /// No description provided for @commandHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Command history'**
  String get commandHistoryTitle;

  /// No description provided for @commandHistoryPaneTitle.
  ///
  /// In en, this message translates to:
  /// **'Command history · Pane {pane}'**
  String commandHistoryPaneTitle(String pane);

  /// No description provided for @commandHistorySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search commands'**
  String get commandHistorySearchHint;

  /// No description provided for @commandHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'Enter = run, Shift+Enter = insert'**
  String get commandHistoryHint;

  /// No description provided for @commandHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No command history found yet for this pane.'**
  String get commandHistoryEmpty;

  /// No description provided for @commandHistoryNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No commands match your search'**
  String get commandHistoryNoMatches;

  /// No description provided for @commandHistoryCount.
  ///
  /// In en, this message translates to:
  /// **'{count} commands'**
  String commandHistoryCount(int count);

  /// No description provided for @commandHistoryCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commandHistoryCopy;

  /// No description provided for @commandHistoryCopied.
  ///
  /// In en, this message translates to:
  /// **'Command copied'**
  String get commandHistoryCopied;

  /// No description provided for @commandHistoryInsert.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get commandHistoryInsert;

  /// No description provided for @commandHistoryRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get commandHistoryRun;

  /// No description provided for @commandHistoryClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commandHistoryClose;

  /// No description provided for @terminalScrollbackLinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Terminal scrollback lines'**
  String get terminalScrollbackLinesTitle;

  /// No description provided for @terminalScrollbackLinesDescription.
  ///
  /// In en, this message translates to:
  /// **'Maximum lines kept in each session terminal buffer'**
  String get terminalScrollbackLinesDescription;

  /// No description provided for @terminalLinkClickOpensInAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Open terminal links in app'**
  String get terminalLinkClickOpensInAppTitle;

  /// No description provided for @terminalLinkClickOpensInAppDescription.
  ///
  /// In en, this message translates to:
  /// **'Left-click links and file paths to open them in TeamPilot instead of the running program. Ctrl/Cmd-click always opens in app.'**
  String get terminalLinkClickOpensInAppDescription;

  /// No description provided for @terminalParkedSendPending.
  ///
  /// In en, this message translates to:
  /// **'Sent, awaiting receipt: {content}'**
  String terminalParkedSendPending(String content);

  /// No description provided for @terminalParkedSendDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get terminalParkedSendDismiss;

  /// No description provided for @mailbox.
  ///
  /// In en, this message translates to:
  /// **'Mailbox'**
  String get mailbox;

  /// No description provided for @board.
  ///
  /// In en, this message translates to:
  /// **'Board'**
  String get board;

  /// No description provided for @visibilityBoardHint.
  ///
  /// In en, this message translates to:
  /// **'Show the task board for mixed-mode teams.'**
  String get visibilityBoardHint;

  /// No description provided for @autoLaunchAllMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Start all members on connect'**
  String get autoLaunchAllMembersTitle;

  /// No description provided for @autoLaunchAllMembersDescription.
  ///
  /// In en, this message translates to:
  /// **'When enabled, Connect and Restart launch every valid member shell; otherwise only the selected member starts.'**
  String get autoLaunchAllMembersDescription;

  /// No description provided for @openExistingSessionStartsTerminalTitle.
  ///
  /// In en, this message translates to:
  /// **'Open existing sessions in terminal'**
  String get openExistingSessionStartsTerminalTitle;

  /// No description provided for @openExistingSessionStartsTerminalDescription.
  ///
  /// In en, this message translates to:
  /// **'When enabled, opening a conversation from the sidebar connects the terminal immediately. When off (default), open the Chat view first; send from Chat to start the terminal.'**
  String get openExistingSessionStartsTerminalDescription;

  /// No description provided for @chatSubmitSwitchesToTerminalTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to Terminal after Chat send'**
  String get chatSubmitSwitchesToTerminalTitle;

  /// No description provided for @chatSubmitSwitchesToTerminalDescription.
  ///
  /// In en, this message translates to:
  /// **'When off (default), sending from Chat (new conversation or continue) stays on the Chat view while the terminal runs in the background. When on, switch to the Terminal after send.'**
  String get chatSubmitSwitchesToTerminalDescription;

  /// No description provided for @simpleModeDefaultFullAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Simple mode default: full access'**
  String get simpleModeDefaultFullAccessTitle;

  /// No description provided for @simpleModeDefaultFullAccessDescription.
  ///
  /// In en, this message translates to:
  /// **'When enabled (default), new Simple-mode compose landing starts with full access permissions. Workspace chip choices still override and persist per workspace.'**
  String get simpleModeDefaultFullAccessDescription;

  /// No description provided for @notifyOnSessionIdleTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent idle system notification'**
  String get notifyOnSessionIdleTitle;

  /// No description provided for @notifyOnSessionIdleDescription.
  ///
  /// In en, this message translates to:
  /// **'When a session finishes a turn and becomes idle, show an OS notification in addition to the in-app notification center.'**
  String get notifyOnSessionIdleDescription;

  /// No description provided for @credentialPushOptInTitle.
  ///
  /// In en, this message translates to:
  /// **'Push credentials to this machine'**
  String get credentialPushOptInTitle;

  /// No description provided for @credentialPushOptInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Provider keys for remote member authentication.'**
  String get credentialPushOptInSubtitle;

  /// No description provided for @credentialPushConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Push credentials to remote host?'**
  String get credentialPushConfirmTitle;

  /// No description provided for @credentialPushConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Provider keys will be written to the remote host {host}. Only enable this for machines you trust. Rotating a key requires re-pushing to every opted-in machine.'**
  String credentialPushConfirmBody(Object host);

  /// No description provided for @credentialPushConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Push credentials'**
  String get credentialPushConfirmAction;

  /// No description provided for @rootSandboxEnvOptInTitle.
  ///
  /// In en, this message translates to:
  /// **'Inject IS_SANDBOX for root'**
  String get rootSandboxEnvOptInTitle;

  /// No description provided for @rootSandboxEnvOptInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep skip-permissions when Claude runs as root.'**
  String get rootSandboxEnvOptInSubtitle;

  /// No description provided for @rootSandboxEnvConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable root sandbox env?'**
  String get rootSandboxEnvConfirmTitle;

  /// No description provided for @rootSandboxEnvConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'TeamPilot will set IS_SANDBOX=1 when launching Claude as root on {host}, keeping --dangerously-skip-permissions. Only enable on machines you trust.'**
  String rootSandboxEnvConfirmBody(Object host);

  /// No description provided for @rootSandboxEnvConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get rootSandboxEnvConfirmAction;

  /// No description provided for @workspaceFoldersSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Directories & machines'**
  String get workspaceFoldersSectionTitle;

  /// No description provided for @workspaceFoldersEditorHint.
  ///
  /// In en, this message translates to:
  /// **'Set machine and path per directory. All local = local workspace; all one remote = project-remote; cross-machine = mixed (member-remote).'**
  String get workspaceFoldersEditorHint;

  /// No description provided for @workspaceFoldersMixedTargetsLockedHint.
  ///
  /// In en, this message translates to:
  /// **'Mixed workspace: folder machines are fixed. Add paths on existing machines above; use Assign to change member machine assignment.'**
  String get workspaceFoldersMixedTargetsLockedHint;

  /// No description provided for @workspaceFoldersPersonalTargetsLockedHint.
  ///
  /// In en, this message translates to:
  /// **'Personal identity cannot change folder machines. Switch to a team identity to configure machines and directories.'**
  String get workspaceFoldersPersonalTargetsLockedHint;

  /// No description provided for @workspaceTopologyLocal.
  ///
  /// In en, this message translates to:
  /// **'Local workspace'**
  String get workspaceTopologyLocal;

  /// No description provided for @workspaceTopologyRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote workspace'**
  String get workspaceTopologyRemote;

  /// No description provided for @workspaceTopologyMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed workspace'**
  String get workspaceTopologyMixed;

  /// No description provided for @workspaceTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get workspaceTypeLabel;

  /// No description provided for @mixedWorkspaceCreateSessionBlocked.
  ///
  /// In en, this message translates to:
  /// **'Confirm machine assignment in Team Settings before starting a conversation in this mixed workspace.'**
  String get mixedWorkspaceCreateSessionBlocked;

  /// No description provided for @mixedWorkspaceSessionLaunchBlocked.
  ///
  /// In en, this message translates to:
  /// **'Machine assignment for this conversation is no longer valid. Confirm assignment in Team Settings and start a new conversation.'**
  String get mixedWorkspaceSessionLaunchBlocked;

  /// No description provided for @sessionLaunchMissingWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace not found for this session.'**
  String get sessionLaunchMissingWorkspace;

  /// No description provided for @sessionLaunchMissingTeamMember.
  ///
  /// In en, this message translates to:
  /// **'Team member is not available. Select a team and try again.'**
  String get sessionLaunchMissingTeamMember;

  /// No description provided for @workspaceFolderTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Machine'**
  String get workspaceFolderTargetLabel;

  /// No description provided for @workspaceFoldersPickTarget.
  ///
  /// In en, this message translates to:
  /// **'Choose machine'**
  String get workspaceFoldersPickTarget;

  /// No description provided for @workspaceDeadTargetBadge.
  ///
  /// In en, this message translates to:
  /// **'Missing machine'**
  String get workspaceDeadTargetBadge;

  /// No description provided for @workspaceDeadTargetRemap.
  ///
  /// In en, this message translates to:
  /// **'Remap…'**
  String get workspaceDeadTargetRemap;

  /// No description provided for @workspaceDeadTargetRemapTitle.
  ///
  /// In en, this message translates to:
  /// **'Remap machine'**
  String get workspaceDeadTargetRemapTitle;

  /// No description provided for @workspaceDeadTargetRemapBody.
  ///
  /// In en, this message translates to:
  /// **'Replace {from} with another machine. Directory paths are not changed — they must already exist on the destination.'**
  String workspaceDeadTargetRemapBody(String from);

  /// No description provided for @workspaceDeadTargetRemapPickFrom.
  ///
  /// In en, this message translates to:
  /// **'Dead machine'**
  String get workspaceDeadTargetRemapPickFrom;

  /// No description provided for @workspaceDeadTargetRemapPickTo.
  ///
  /// In en, this message translates to:
  /// **'Replacement machine'**
  String get workspaceDeadTargetRemapPickTo;

  /// No description provided for @workspaceDeadTargetRemapConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remap'**
  String get workspaceDeadTargetRemapConfirm;

  /// No description provided for @workspaceDeadTargetRemapNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to remap.'**
  String get workspaceDeadTargetRemapNothing;

  /// No description provided for @workspaceDeadTargetRemapFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remap machine.'**
  String get workspaceDeadTargetRemapFailed;

  /// No description provided for @workspaceDeadTargetRemapFromLaunch.
  ///
  /// In en, this message translates to:
  /// **'Remap machine…'**
  String get workspaceDeadTargetRemapFromLaunch;

  /// No description provided for @homeTargetTitle.
  ///
  /// In en, this message translates to:
  /// **'Home device'**
  String get homeTargetTitle;

  /// No description provided for @homeTargetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Where TeamPilot stores teams, workspaces, and config (the control plane). Switching uses a separate data tree; nothing is migrated automatically.'**
  String get homeTargetSubtitle;

  /// No description provided for @bootstrapStartupFailed.
  ///
  /// In en, this message translates to:
  /// **'Startup failed: {error}'**
  String bootstrapStartupFailed(String error);

  /// No description provided for @bootstrapUseNativeStorageInstead.
  ///
  /// In en, this message translates to:
  /// **'Use Windows local storage instead'**
  String get bootstrapUseNativeStorageInstead;

  /// No description provided for @providers.
  ///
  /// In en, this message translates to:
  /// **'PROVIDERS'**
  String get providers;

  /// No description provided for @providerListModelCount.
  ///
  /// In en, this message translates to:
  /// **'{count} models'**
  String providerListModelCount(int count);

  /// No description provided for @proxyOnShort.
  ///
  /// In en, this message translates to:
  /// **'Proxy on'**
  String get proxyOnShort;

  /// No description provided for @proxyOffShort.
  ///
  /// In en, this message translates to:
  /// **'Proxy off'**
  String get proxyOffShort;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @proxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get proxy;

  /// No description provided for @reveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get reveal;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @claudeLaunchCredentialsMissingWarning.
  ///
  /// In en, this message translates to:
  /// **'Claude Official credentials are missing for this team provider. Sign in from Providers settings.'**
  String get claudeLaunchCredentialsMissingWarning;

  /// No description provided for @api.
  ///
  /// In en, this message translates to:
  /// **'api'**
  String get api;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'account'**
  String get account;

  /// No description provided for @models.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get models;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @summary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// No description provided for @validation.
  ///
  /// In en, this message translates to:
  /// **'Validation'**
  String get validation;

  /// No description provided for @validate.
  ///
  /// In en, this message translates to:
  /// **'Validate'**
  String get validate;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @configure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get configure;

  /// No description provided for @teamConfig.
  ///
  /// In en, this message translates to:
  /// **'Team Config'**
  String get teamConfig;

  /// No description provided for @teamSettings.
  ///
  /// In en, this message translates to:
  /// **'Team Settings'**
  String get teamSettings;

  /// No description provided for @teamSkillsNav.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get teamSkillsNav;

  /// No description provided for @teamPluginsNav.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get teamPluginsNav;

  /// No description provided for @teamExtensionsNav.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get teamExtensionsNav;

  /// No description provided for @teamExtensionFollowGlobal.
  ///
  /// In en, this message translates to:
  /// **'Follow global'**
  String get teamExtensionFollowGlobal;

  /// No description provided for @teamExtensionForceOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get teamExtensionForceOn;

  /// No description provided for @teamExtensionForceOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get teamExtensionForceOff;

  /// No description provided for @teamExtensionEffectiveOn.
  ///
  /// In en, this message translates to:
  /// **'Active for this team'**
  String get teamExtensionEffectiveOn;

  /// No description provided for @teamExtensionEffectiveOff.
  ///
  /// In en, this message translates to:
  /// **'Inactive for this team'**
  String get teamExtensionEffectiveOff;

  /// No description provided for @teamMcpNav.
  ///
  /// In en, this message translates to:
  /// **'MCP'**
  String get teamMcpNav;

  /// No description provided for @githubSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get githubSettingsTitle;

  /// No description provided for @githubSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect GitHub to publish experts and teams to Hub'**
  String get githubSettingsSubtitle;

  /// No description provided for @githubSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in with GitHub'**
  String get githubSignIn;

  /// No description provided for @githubConnectedAs.
  ///
  /// In en, this message translates to:
  /// **'Connected as @{login}'**
  String githubConnectedAs(Object login);

  /// No description provided for @githubConnectedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Connected to GitHub'**
  String get githubConnectedGeneric;

  /// No description provided for @githubDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get githubDisconnect;

  /// No description provided for @githubWaitingCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter this code on GitHub if prompted'**
  String get githubWaitingCodeHint;

  /// No description provided for @githubBrowserOpened.
  ///
  /// In en, this message translates to:
  /// **'Browser opened for authorization'**
  String get githubBrowserOpened;

  /// No description provided for @githubReopenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Reopen browser'**
  String get githubReopenBrowser;

  /// No description provided for @githubDeviceFlowUnavailable.
  ///
  /// In en, this message translates to:
  /// **'GitHub sign-in is unavailable in this build. Use a personal access token.'**
  String get githubDeviceFlowUnavailable;

  /// No description provided for @githubAdvancedPat.
  ///
  /// In en, this message translates to:
  /// **'Use a personal access token'**
  String get githubAdvancedPat;

  /// No description provided for @githubAdvancedPatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When GitHub sign-in is unavailable, or you prefer a token with repo scope.'**
  String get githubAdvancedPatSubtitle;

  /// No description provided for @hubPublishTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'GitHub token'**
  String get hubPublishTokenLabel;

  /// No description provided for @hubPublishTokenHint.
  ///
  /// In en, this message translates to:
  /// **'ghp_…'**
  String get hubPublishTokenHint;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @dangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get dangerZone;

  /// No description provided for @memberName.
  ///
  /// In en, this message translates to:
  /// **'Member name'**
  String get memberName;

  /// No description provided for @provider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get provider;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @agent.
  ///
  /// In en, this message translates to:
  /// **'Agent preset'**
  String get agent;

  /// No description provided for @prompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get prompt;

  /// No description provided for @appProviderClaudeAuthTokenDefault.
  ///
  /// In en, this message translates to:
  /// **'ANTHROPIC_AUTH_TOKEN (default)'**
  String get appProviderClaudeAuthTokenDefault;

  /// No description provided for @appProviderClaudeAuthApiKey.
  ///
  /// In en, this message translates to:
  /// **'ANTHROPIC_API_KEY'**
  String get appProviderClaudeAuthApiKey;

  /// No description provided for @appProviderToolFlashskyai.
  ///
  /// In en, this message translates to:
  /// **'FlashskyAI'**
  String get appProviderToolFlashskyai;

  /// No description provided for @appProviderToolCodex.
  ///
  /// In en, this message translates to:
  /// **'Codex'**
  String get appProviderToolCodex;

  /// No description provided for @appProviderToolClaude.
  ///
  /// In en, this message translates to:
  /// **'Claude Code'**
  String get appProviderToolClaude;

  /// No description provided for @appProviderToolOpencode.
  ///
  /// In en, this message translates to:
  /// **'OpenCode'**
  String get appProviderToolOpencode;

  /// No description provided for @appProviderToolCursor.
  ///
  /// In en, this message translates to:
  /// **'Cursor'**
  String get appProviderToolCursor;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @aboutPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'TeamPilot version and application updates.'**
  String get aboutPageSubtitle;

  /// No description provided for @aboutGitHub.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get aboutGitHub;

  /// No description provided for @aboutCurrentVersion.
  ///
  /// In en, this message translates to:
  /// **'Current version'**
  String get aboutCurrentVersion;

  /// No description provided for @aboutVersionLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get aboutVersionLoading;

  /// No description provided for @appUpdateCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get appUpdateCheck;

  /// No description provided for @appUpdateAutoCheck.
  ///
  /// In en, this message translates to:
  /// **'Auto-check for updates'**
  String get appUpdateAutoCheck;

  /// No description provided for @appUpdateAutoCheckHint.
  ///
  /// In en, this message translates to:
  /// **'Check GitHub for a newer version each time the app starts.'**
  String get appUpdateAutoCheckHint;

  /// No description provided for @appUpdateSkipVersion.
  ///
  /// In en, this message translates to:
  /// **'Skip this version'**
  String get appUpdateSkipVersion;

  /// No description provided for @appUpdateDownloadInstall.
  ///
  /// In en, this message translates to:
  /// **'Download and install'**
  String get appUpdateDownloadInstall;

  /// No description provided for @appUpdateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You are on the latest version.'**
  String get appUpdateUpToDate;

  /// No description provided for @appUpdateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading update…'**
  String get appUpdateDownloading;

  /// No description provided for @appUpdateInstalling.
  ///
  /// In en, this message translates to:
  /// **'Installing update…'**
  String get appUpdateInstalling;

  /// No description provided for @appUpdateViewRelease.
  ///
  /// In en, this message translates to:
  /// **'View release on GitHub'**
  String get appUpdateViewRelease;

  /// No description provided for @appUpdateViewReleases.
  ///
  /// In en, this message translates to:
  /// **'Releases'**
  String get appUpdateViewReleases;

  /// No description provided for @appUpdateNewVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} available'**
  String appUpdateNewVersion(String version);

  /// No description provided for @appUpdateDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'New version available'**
  String get appUpdateDialogTitle;

  /// No description provided for @appUpdateLatestVersion.
  ///
  /// In en, this message translates to:
  /// **'Latest version'**
  String get appUpdateLatestVersion;

  /// No description provided for @appUpdateUnknownVersion.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get appUpdateUnknownVersion;

  /// No description provided for @appUpdateChangelogTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get appUpdateChangelogTitle;

  /// No description provided for @appUpdateChangelogDefaultSection.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get appUpdateChangelogDefaultSection;

  /// No description provided for @appUpdateReadyToDownload.
  ///
  /// In en, this message translates to:
  /// **'Ready to download'**
  String get appUpdateReadyToDownload;

  /// No description provided for @appUpdateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get appUpdateLater;

  /// No description provided for @appUpdateDownloadNow.
  ///
  /// In en, this message translates to:
  /// **'Download now'**
  String get appUpdateDownloadNow;

  /// No description provided for @appUpdateDownloadInBackground.
  ///
  /// In en, this message translates to:
  /// **'Download in background'**
  String get appUpdateDownloadInBackground;

  /// No description provided for @appUpdateInstallNow.
  ///
  /// In en, this message translates to:
  /// **'Install now'**
  String get appUpdateInstallNow;

  /// No description provided for @appUpdateBrowserDownload.
  ///
  /// In en, this message translates to:
  /// **'Download in browser'**
  String get appUpdateBrowserDownload;

  /// No description provided for @appUpdateInvalidPackagePath.
  ///
  /// In en, this message translates to:
  /// **'Invalid package path'**
  String get appUpdateInvalidPackagePath;

  /// No description provided for @appUpdateReleaseBuildRequired.
  ///
  /// In en, this message translates to:
  /// **'Use a release build for in-app installation'**
  String get appUpdateReleaseBuildRequired;

  /// No description provided for @appUpdatePackagePlatformMismatch.
  ///
  /// In en, this message translates to:
  /// **'Package type does not match this system'**
  String get appUpdatePackagePlatformMismatch;

  /// No description provided for @appUpdateInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Install failed: {message}'**
  String appUpdateInstallFailed(String message);

  /// No description provided for @appUpdateInstallNoResult.
  ///
  /// In en, this message translates to:
  /// **'Install returned no result'**
  String get appUpdateInstallNoResult;

  /// No description provided for @appUpdateInstallComplete.
  ///
  /// In en, this message translates to:
  /// **'Installation complete'**
  String get appUpdateInstallComplete;

  /// No description provided for @appUpdateRedirectBrowserOnly.
  ///
  /// In en, this message translates to:
  /// **'This link must be downloaded in the browser'**
  String get appUpdateRedirectBrowserOnly;

  /// No description provided for @appUpdateDownloadStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting download…'**
  String get appUpdateDownloadStarting;

  /// No description provided for @appUpdateDownloadComplete.
  ///
  /// In en, this message translates to:
  /// **'Download complete'**
  String get appUpdateDownloadComplete;

  /// No description provided for @appUpdateDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get appUpdateDownloadFailed;

  /// No description provided for @appUpdateDownloadError.
  ///
  /// In en, this message translates to:
  /// **'Error while downloading: {error}'**
  String appUpdateDownloadError(String error);

  /// No description provided for @appUpdateResolvingDownloadUrl.
  ///
  /// In en, this message translates to:
  /// **'Resolving download link…'**
  String get appUpdateResolvingDownloadUrl;

  /// No description provided for @appUpdateBrowserOpened.
  ///
  /// In en, this message translates to:
  /// **'Opened download link in the browser'**
  String get appUpdateBrowserOpened;

  /// No description provided for @appUpdateCannotOpenDownloadLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open download link'**
  String get appUpdateCannotOpenDownloadLink;

  /// No description provided for @appUpdateBrowserOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open browser: {error}'**
  String appUpdateBrowserOpenFailed(String error);

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get onboardingPrevious;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingAppearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose language and appearance'**
  String get onboardingAppearanceTitle;

  /// No description provided for @onboardingAppearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You can change these later in Settings → Layout.'**
  String get onboardingAppearanceSubtitle;

  /// No description provided for @onboardingSshTitle.
  ///
  /// In en, this message translates to:
  /// **'Configure SSH connection'**
  String get onboardingSshTitle;

  /// No description provided for @onboardingSshSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Android runs AI CLIs on a remote host over SSH.'**
  String get onboardingSshSubtitle;

  /// No description provided for @onboardingRerunSetup.
  ///
  /// In en, this message translates to:
  /// **'Run setup wizard again'**
  String get onboardingRerunSetup;

  /// No description provided for @logViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logViewerTitle;

  /// No description provided for @logViewerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Application and error logs under your TeamPilot app data folder.'**
  String get logViewerSubtitle;

  /// No description provided for @logViewerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search logs…'**
  String get logViewerSearchHint;

  /// No description provided for @logViewerWrapLines.
  ///
  /// In en, this message translates to:
  /// **'Wrap lines'**
  String get logViewerWrapLines;

  /// No description provided for @logViewerReverseOrder.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get logViewerReverseOrder;

  /// No description provided for @logViewerCompactView.
  ///
  /// In en, this message translates to:
  /// **'Compact view'**
  String get logViewerCompactView;

  /// No description provided for @logViewerLineCount.
  ///
  /// In en, this message translates to:
  /// **'{count} lines'**
  String logViewerLineCount(int count);

  /// No description provided for @logViewerActionsMenu.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get logViewerActionsMenu;

  /// No description provided for @logViewerRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get logViewerRefresh;

  /// No description provided for @logViewerCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy log path'**
  String get logViewerCopyPath;

  /// No description provided for @logViewerClearOld.
  ///
  /// In en, this message translates to:
  /// **'Remove old logs'**
  String get logViewerClearOld;

  /// No description provided for @logViewerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No log files yet'**
  String get logViewerEmpty;

  /// No description provided for @logViewerEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Logs are created while the app runs.'**
  String get logViewerEmptyHint;

  /// No description provided for @logViewerPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Logs not on disk yet'**
  String get logViewerPendingTitle;

  /// No description provided for @logViewerPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Buffered entries waiting for file logging:'**
  String get logViewerPendingBody;

  /// No description provided for @logViewerLoadFilesFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to list logs: {error}'**
  String logViewerLoadFilesFailed(String error);

  /// No description provided for @logViewerReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to read log: {error}'**
  String logViewerReadFailed(String error);

  /// No description provided for @logViewerClearDone.
  ///
  /// In en, this message translates to:
  /// **'Old log files removed'**
  String get logViewerClearDone;

  /// No description provided for @logViewerClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Cleanup failed: {error}'**
  String logViewerClearFailed(String error);

  /// No description provided for @logViewerPathCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied path: {name}'**
  String logViewerPathCopied(String name);

  /// No description provided for @initErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Startup failed'**
  String get initErrorTitle;

  /// No description provided for @initErrorDetails.
  ///
  /// In en, this message translates to:
  /// **'Error details'**
  String get initErrorDetails;

  /// No description provided for @initErrorStackTrace.
  ///
  /// In en, this message translates to:
  /// **'Stack trace'**
  String get initErrorStackTrace;

  /// No description provided for @initErrorPendingLogs.
  ///
  /// In en, this message translates to:
  /// **'Pending logs'**
  String get initErrorPendingLogs;

  /// No description provided for @initErrorViewLogs.
  ///
  /// In en, this message translates to:
  /// **'View logs'**
  String get initErrorViewLogs;

  /// No description provided for @initErrorCopyReport.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get initErrorCopyReport;

  /// No description provided for @initErrorCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get initErrorCopy;

  /// No description provided for @initErrorCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get initErrorCopied;

  /// No description provided for @initErrorStackEmpty.
  ///
  /// In en, this message translates to:
  /// **'Stack trace is empty.'**
  String get initErrorStackEmpty;

  /// No description provided for @initErrorVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({build})'**
  String initErrorVersion(String version, String build);

  /// No description provided for @diffIgnoreWhitespace.
  ///
  /// In en, this message translates to:
  /// **'Ignore whitespace'**
  String get diffIgnoreWhitespace;

  /// No description provided for @diffPreviousChange.
  ///
  /// In en, this message translates to:
  /// **'Previous change'**
  String get diffPreviousChange;

  /// No description provided for @diffNextChange.
  ///
  /// In en, this message translates to:
  /// **'Next change'**
  String get diffNextChange;

  /// No description provided for @diffViewSideBySide.
  ///
  /// In en, this message translates to:
  /// **'Side by side'**
  String get diffViewSideBySide;

  /// No description provided for @diffViewUnified.
  ///
  /// In en, this message translates to:
  /// **'Unified'**
  String get diffViewUnified;

  /// No description provided for @diffOpenSourceFile.
  ///
  /// In en, this message translates to:
  /// **'Open source file'**
  String get diffOpenSourceFile;

  /// No description provided for @diffShowAllLines.
  ///
  /// In en, this message translates to:
  /// **'Show all lines'**
  String get diffShowAllLines;

  /// No description provided for @diffNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get diffNoChanges;

  /// No description provided for @fileDiffToggleFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get fileDiffToggleFile;

  /// No description provided for @fileDiffToggleDiff.
  ///
  /// In en, this message translates to:
  /// **'Diff'**
  String get fileDiffToggleDiff;

  /// No description provided for @diffChangeCounter.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String diffChangeCounter(int current, int total);

  /// No description provided for @notificationCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationCenterTitle;

  /// No description provided for @notificationEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get notificationEmpty;

  /// No description provided for @notificationMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get notificationMarkAllRead;

  /// No description provided for @notificationClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get notificationClearAll;

  /// No description provided for @notificationMarkRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get notificationMarkRead;

  /// No description provided for @notificationDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get notificationDelete;

  /// No description provided for @notificationSourceTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal OSC {code}'**
  String notificationSourceTerminal(String code);

  /// No description provided for @notificationSourceAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get notificationSourceAgent;

  /// No description provided for @notificationTimeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get notificationTimeJustNow;

  /// No description provided for @notificationTimeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min ago'**
  String notificationTimeMinutesAgo(int minutes);

  /// No description provided for @notificationTimeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours} h ago'**
  String notificationTimeHoursAgo(int hours);

  /// No description provided for @notificationTimeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days} d ago'**
  String notificationTimeDaysAgo(int days);

  /// No description provided for @toolchainGit.
  ///
  /// In en, this message translates to:
  /// **'Git'**
  String get toolchainGit;

  /// No description provided for @toolchainNode.
  ///
  /// In en, this message translates to:
  /// **'Node.js'**
  String get toolchainNode;

  /// No description provided for @worktreeCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New worktree'**
  String get worktreeCreateTitle;

  /// No description provided for @worktreeBranchLabel.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get worktreeBranchLabel;

  /// No description provided for @worktreeModeNewBranch.
  ///
  /// In en, this message translates to:
  /// **'New branch'**
  String get worktreeModeNewBranch;

  /// No description provided for @worktreeModeExistingBranch.
  ///
  /// In en, this message translates to:
  /// **'Existing branch'**
  String get worktreeModeExistingBranch;

  /// No description provided for @worktreeBaseRefLabel.
  ///
  /// In en, this message translates to:
  /// **'Base (optional)'**
  String get worktreeBaseRefLabel;

  /// No description provided for @worktreeBaseRefHint.
  ///
  /// In en, this message translates to:
  /// **'Defaults to current HEAD'**
  String get worktreeBaseRefHint;

  /// No description provided for @worktreePathLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get worktreePathLabel;

  /// No description provided for @worktreeStartConversation.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation here after creating'**
  String get worktreeStartConversation;

  /// No description provided for @worktreeCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get worktreeCreateAction;

  /// No description provided for @worktreeCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create worktree: {error}'**
  String worktreeCreateFailed(Object error);

  /// No description provided for @worktreeDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove worktree'**
  String get worktreeDeleteTitle;

  /// No description provided for @worktreeDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Remove the worktree for {branch}?'**
  String worktreeDeleteBody(Object branch);

  /// No description provided for @worktreeDeleteForce.
  ///
  /// In en, this message translates to:
  /// **'Force-remove even if it has uncommitted changes'**
  String get worktreeDeleteForce;

  /// No description provided for @worktreeDeleteBranchToo.
  ///
  /// In en, this message translates to:
  /// **'Also delete the branch'**
  String get worktreeDeleteBranchToo;

  /// No description provided for @worktreeDeleteSessionsToo.
  ///
  /// In en, this message translates to:
  /// **'Also delete the {count} conversations in this worktree'**
  String worktreeDeleteSessionsToo(Object count);

  /// No description provided for @worktreeDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get worktreeDeleteAction;

  /// No description provided for @worktreeDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove worktree: {error}'**
  String worktreeDeleteFailed(Object error);

  /// No description provided for @worktreeOrphanGroup.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get worktreeOrphanGroup;

  /// No description provided for @worktreeNewWorktreeTooltip.
  ///
  /// In en, this message translates to:
  /// **'New worktree'**
  String get worktreeNewWorktreeTooltip;

  /// No description provided for @worktreeRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh worktrees'**
  String get worktreeRefreshTooltip;

  /// No description provided for @worktreeNewConversationHere.
  ///
  /// In en, this message translates to:
  /// **'New conversation here'**
  String get worktreeNewConversationHere;

  /// No description provided for @worktreeMenuCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get worktreeMenuCopyPath;

  /// No description provided for @worktreeMenuRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove worktree'**
  String get worktreeMenuRemove;

  /// No description provided for @worktreeMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get worktreeMore;

  /// No description provided for @worktreeShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get worktreeShowLess;

  /// No description provided for @worktreeDeleteBusyWarning.
  ///
  /// In en, this message translates to:
  /// **'Stop the running conversations in this worktree before removing it.'**
  String get worktreeDeleteBusyWarning;

  /// Workspace project folder for launch-prompt automations
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get automationsLaunchProject;

  /// Git worktree cwd for launch-prompt automations
  ///
  /// In en, this message translates to:
  /// **'Worktree'**
  String get automationsLaunchWorktree;

  /// No description provided for @shortcutsWorkspaceNextTab.
  ///
  /// In en, this message translates to:
  /// **'Next Workspace Tab'**
  String get shortcutsWorkspaceNextTab;

  /// No description provided for @shortcutsWorkspacePrevTab.
  ///
  /// In en, this message translates to:
  /// **'Previous Workspace Tab'**
  String get shortcutsWorkspacePrevTab;

  /// No description provided for @shortcutsWorkspaceCloseTab.
  ///
  /// In en, this message translates to:
  /// **'Close Workspace Tab'**
  String get shortcutsWorkspaceCloseTab;

  /// No description provided for @shortcutsWorkspaceReopenClosed.
  ///
  /// In en, this message translates to:
  /// **'Reopen Closed Workspace Tab'**
  String get shortcutsWorkspaceReopenClosed;

  /// No description provided for @shortcutsWorkspaceSearch.
  ///
  /// In en, this message translates to:
  /// **'Search Workspace'**
  String get shortcutsWorkspaceSearch;

  /// No description provided for @shortcutsStripNextTab.
  ///
  /// In en, this message translates to:
  /// **'Next Tab'**
  String get shortcutsStripNextTab;

  /// No description provided for @shortcutsStripPrevTab.
  ///
  /// In en, this message translates to:
  /// **'Previous Tab'**
  String get shortcutsStripPrevTab;

  /// No description provided for @shortcutsSessionNewTab.
  ///
  /// In en, this message translates to:
  /// **'New Session Tab'**
  String get shortcutsSessionNewTab;

  /// No description provided for @shortcutsSessionCloseTab.
  ///
  /// In en, this message translates to:
  /// **'Close Session Tab'**
  String get shortcutsSessionCloseTab;

  /// No description provided for @shortcutsStripFocusTab.
  ///
  /// In en, this message translates to:
  /// **'Go to Tab {n}'**
  String shortcutsStripFocusTab(int n);

  /// No description provided for @shortcutsToggleSidebar.
  ///
  /// In en, this message translates to:
  /// **'Toggle Sidebar'**
  String get shortcutsToggleSidebar;

  /// No description provided for @shortcutsTogglePanel.
  ///
  /// In en, this message translates to:
  /// **'Toggle Terminal Panel'**
  String get shortcutsTogglePanel;

  /// No description provided for @shortcutsToggleSecondarySidebar.
  ///
  /// In en, this message translates to:
  /// **'Toggle Secondary Sidebar'**
  String get shortcutsToggleSecondarySidebar;

  /// No description provided for @shortcutsZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom In'**
  String get shortcutsZoomIn;

  /// No description provided for @shortcutsZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom Out'**
  String get shortcutsZoomOut;

  /// No description provided for @shortcutsZoomReset.
  ///
  /// In en, this message translates to:
  /// **'Reset Zoom'**
  String get shortcutsZoomReset;

  /// No description provided for @shortcutsComposeSubmit.
  ///
  /// In en, this message translates to:
  /// **'Send Message'**
  String get shortcutsComposeSubmit;

  /// No description provided for @shortcutsComposeNewline.
  ///
  /// In en, this message translates to:
  /// **'Insert Newline'**
  String get shortcutsComposeNewline;

  /// No description provided for @shortcutsShowCheatsheet.
  ///
  /// In en, this message translates to:
  /// **'Show Keyboard Shortcuts'**
  String get shortcutsShowCheatsheet;

  /// No description provided for @shortcutsCategoryNavigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get shortcutsCategoryNavigation;

  /// No description provided for @shortcutsCategoryTabs.
  ///
  /// In en, this message translates to:
  /// **'Tabs'**
  String get shortcutsCategoryTabs;

  /// No description provided for @shortcutsCategoryView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get shortcutsCategoryView;

  /// No description provided for @shortcutsCategoryZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get shortcutsCategoryZoom;

  /// No description provided for @shortcutsCategoryCompose.
  ///
  /// In en, this message translates to:
  /// **'Compose'**
  String get shortcutsCategoryCompose;

  /// No description provided for @shortcutsCategoryMeta.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get shortcutsCategoryMeta;

  /// No description provided for @shortcutsCategoryTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get shortcutsCategoryTerminal;

  /// No description provided for @shortcutsSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get shortcutsSettingsTitle;

  /// No description provided for @shortcutsPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View and customize keyboard shortcuts for navigation, tabs, zoom, and compose.'**
  String get shortcutsPageSubtitle;

  /// No description provided for @shortcutsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search shortcuts'**
  String get shortcutsSearchHint;

  /// No description provided for @shortcutsChangeAction.
  ///
  /// In en, this message translates to:
  /// **'Change…'**
  String get shortcutsChangeAction;

  /// No description provided for @shortcutsResetAction.
  ///
  /// In en, this message translates to:
  /// **'Reset to Default'**
  String get shortcutsResetAction;

  /// No description provided for @shortcutsUnbindAction.
  ///
  /// In en, this message translates to:
  /// **'Unbind'**
  String get shortcutsUnbindAction;

  /// No description provided for @shortcutsNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get shortcutsNotSet;

  /// No description provided for @shortcutsResetAll.
  ///
  /// In en, this message translates to:
  /// **'Reset All'**
  String get shortcutsResetAll;

  /// No description provided for @shortcutsResetAllConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset All Shortcuts?'**
  String get shortcutsResetAllConfirmTitle;

  /// No description provided for @shortcutsResetAllConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This restores every keyboard shortcut to its default binding.'**
  String get shortcutsResetAllConfirmMessage;

  /// No description provided for @shortcutsExport.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get shortcutsExport;

  /// No description provided for @shortcutsImport.
  ///
  /// In en, this message translates to:
  /// **'Import…'**
  String get shortcutsImport;

  /// No description provided for @shortcutsExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts exported.'**
  String get shortcutsExportSuccess;

  /// No description provided for @shortcutsExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export shortcuts.'**
  String get shortcutsExportFailed;

  /// No description provided for @shortcutsImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts imported.'**
  String get shortcutsImportSuccess;

  /// No description provided for @shortcutsImportInvalidFile.
  ///
  /// In en, this message translates to:
  /// **'That file isn\'t a valid shortcuts export.'**
  String get shortcutsImportInvalidFile;

  /// No description provided for @shortcutsImportConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace Conflicting Shortcuts?'**
  String get shortcutsImportConflictTitle;

  /// No description provided for @shortcutsImportConflictMessage.
  ///
  /// In en, this message translates to:
  /// **'The imported shortcuts conflict with {count} existing binding(s). Replace them?'**
  String shortcutsImportConflictMessage(int count);

  /// No description provided for @shortcutsCheatsheetButton.
  ///
  /// In en, this message translates to:
  /// **'View Cheatsheet'**
  String get shortcutsCheatsheetButton;

  /// No description provided for @shortcutsCheatsheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get shortcutsCheatsheetTitle;

  /// No description provided for @shortcutsCheatsheetEmpty.
  ///
  /// In en, this message translates to:
  /// **'No shortcuts match your search.'**
  String get shortcutsCheatsheetEmpty;

  /// No description provided for @shortcutsPressShortcutTitle.
  ///
  /// In en, this message translates to:
  /// **'Press a Shortcut'**
  String get shortcutsPressShortcutTitle;

  /// No description provided for @shortcutsPressShortcutHint.
  ///
  /// In en, this message translates to:
  /// **'Press a key combination to bind it. Press Escape to cancel, Backspace to unbind.'**
  String get shortcutsPressShortcutHint;

  /// No description provided for @shortcutsPressShortcutUnsupportedKey.
  ///
  /// In en, this message translates to:
  /// **'That key can\'t be bound.'**
  String get shortcutsPressShortcutUnsupportedKey;

  /// No description provided for @shortcutsConflictMessage.
  ///
  /// In en, this message translates to:
  /// **'Already used by \"{title}\".'**
  String shortcutsConflictMessage(String title);

  /// No description provided for @shortcutsReplaceAction.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get shortcutsReplaceAction;

  /// No description provided for @shortcutsConflictBadgeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Conflicts with another shortcut'**
  String get shortcutsConflictBadgeTooltip;

  /// No description provided for @runAction.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get runAction;

  /// No description provided for @runStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get runStop;

  /// No description provided for @runRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get runRestart;

  /// No description provided for @runNewInstance.
  ///
  /// In en, this message translates to:
  /// **'New instance'**
  String get runNewInstance;

  /// No description provided for @runDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get runDebug;

  /// No description provided for @runBuild.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get runBuild;

  /// No description provided for @runSelectConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Select configuration'**
  String get runSelectConfiguration;

  /// No description provided for @runCompoundConfiguration.
  ///
  /// In en, this message translates to:
  /// **'{name} (compound)'**
  String runCompoundConfiguration(String name);

  /// No description provided for @runSuggestedConfiguration.
  ///
  /// In en, this message translates to:
  /// **'{name} (Suggested)'**
  String runSuggestedConfiguration(String name);

  /// No description provided for @runConfigurationTooltip.
  ///
  /// In en, this message translates to:
  /// **'Run configuration'**
  String get runConfigurationTooltip;

  /// No description provided for @runAlreadyRunningTitle.
  ///
  /// In en, this message translates to:
  /// **'Configuration already running'**
  String get runAlreadyRunningTitle;

  /// No description provided for @runAlreadyRunningMessage.
  ///
  /// In en, this message translates to:
  /// **'Restart the running session, or start a new instance?'**
  String get runAlreadyRunningMessage;

  /// No description provided for @runStopSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop running session?'**
  String get runStopSessionTitle;

  /// No description provided for @runStopSessionMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is still running. Stop it and close this tab?'**
  String runStopSessionMessage(String name);

  /// No description provided for @runStopAndClose.
  ///
  /// In en, this message translates to:
  /// **'Stop and close'**
  String get runStopAndClose;

  /// No description provided for @runNoSessions.
  ///
  /// In en, this message translates to:
  /// **'No run sessions'**
  String get runNoSessions;

  /// No description provided for @runClearExited.
  ///
  /// In en, this message translates to:
  /// **'Clear exited sessions'**
  String get runClearExited;

  /// No description provided for @runLoadingOutput.
  ///
  /// In en, this message translates to:
  /// **'Loading run output…'**
  String get runLoadingOutput;

  /// No description provided for @runEmptyOutputHint.
  ///
  /// In en, this message translates to:
  /// **'Run a configuration to see output here'**
  String get runEmptyOutputHint;

  /// No description provided for @runTypeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown launch type: {type}'**
  String runTypeUnknown(String type);

  /// No description provided for @runTypeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Launch type \"{type}\" is not available on this target'**
  String runTypeUnavailable(String type);

  /// No description provided for @runTypeUnavailableRemote.
  ///
  /// In en, this message translates to:
  /// **'Launch type \"{type}\" is not available on remote targets'**
  String runTypeUnavailableRemote(String type);

  /// No description provided for @runConfigureLaunchItems.
  ///
  /// In en, this message translates to:
  /// **'Configure launch configurations'**
  String get runConfigureLaunchItems;

  /// No description provided for @runConfigurationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No launch configurations yet'**
  String get runConfigurationsEmpty;

  /// No description provided for @runEditConfigurations.
  ///
  /// In en, this message translates to:
  /// **'Edit configuration'**
  String get runEditConfigurations;

  /// No description provided for @runAddConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Add configuration'**
  String get runAddConfiguration;

  /// No description provided for @runDeleteConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get runDeleteConfiguration;

  /// No description provided for @runDeleteConfigurationConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete configuration \"{name}\"?'**
  String runDeleteConfigurationConfirm(String name);

  /// No description provided for @runStopAndDelete.
  ///
  /// In en, this message translates to:
  /// **'Stop and delete'**
  String get runStopAndDelete;

  /// No description provided for @runApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get runApply;

  /// No description provided for @runDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get runDiscard;

  /// No description provided for @runDiscardChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get runDiscardChangesTitle;

  /// No description provided for @runDiscardChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes to this configuration. Apply them, discard them, or cancel?'**
  String get runDiscardChangesMessage;

  /// No description provided for @runSelectFolder.
  ///
  /// In en, this message translates to:
  /// **'Select folder'**
  String get runSelectFolder;

  /// No description provided for @runConfigurationName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get runConfigurationName;

  /// No description provided for @runConfigurationType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get runConfigurationType;

  /// No description provided for @runTypeShellScript.
  ///
  /// In en, this message translates to:
  /// **'Shell Script'**
  String get runTypeShellScript;

  /// No description provided for @runFieldCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get runFieldCommand;

  /// No description provided for @runFieldArgs.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get runFieldArgs;

  /// No description provided for @runFieldEnv.
  ///
  /// In en, this message translates to:
  /// **'Environment variables'**
  String get runFieldEnv;

  /// No description provided for @runFieldCwd.
  ///
  /// In en, this message translates to:
  /// **'Working directory'**
  String get runFieldCwd;

  /// No description provided for @runFieldShell.
  ///
  /// In en, this message translates to:
  /// **'Run in shell'**
  String get runFieldShell;

  /// No description provided for @runFieldScriptPath.
  ///
  /// In en, this message translates to:
  /// **'Script path'**
  String get runFieldScriptPath;

  /// No description provided for @runFieldScriptText.
  ///
  /// In en, this message translates to:
  /// **'Script text'**
  String get runFieldScriptText;

  /// No description provided for @runFieldExecute.
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get runFieldExecute;

  /// No description provided for @runFieldScriptOptions.
  ///
  /// In en, this message translates to:
  /// **'Script options'**
  String get runFieldScriptOptions;

  /// No description provided for @runFieldInterpreterPath.
  ///
  /// In en, this message translates to:
  /// **'Interpreter path'**
  String get runFieldInterpreterPath;

  /// No description provided for @runFieldInterpreterOptions.
  ///
  /// In en, this message translates to:
  /// **'Interpreter options'**
  String get runFieldInterpreterOptions;

  /// No description provided for @runFieldExecuteInTerminal.
  ///
  /// In en, this message translates to:
  /// **'Execute in the terminal'**
  String get runFieldExecuteInTerminal;

  /// No description provided for @runFieldAllowMultipleInstances.
  ///
  /// In en, this message translates to:
  /// **'Allow multiple instances'**
  String get runFieldAllowMultipleInstances;

  /// No description provided for @runFieldActivateToolWindow.
  ///
  /// In en, this message translates to:
  /// **'Activate tool window'**
  String get runFieldActivateToolWindow;

  /// No description provided for @runFieldFocusToolWindow.
  ///
  /// In en, this message translates to:
  /// **'Focus tool window'**
  String get runFieldFocusToolWindow;

  /// No description provided for @runExecuteScriptFile.
  ///
  /// In en, this message translates to:
  /// **'Script file'**
  String get runExecuteScriptFile;

  /// No description provided for @runExecuteScriptText.
  ///
  /// In en, this message translates to:
  /// **'Script text'**
  String get runExecuteScriptText;

  /// No description provided for @runValidationEnvMustBeStringMap.
  ///
  /// In en, this message translates to:
  /// **'Environment must be a map of strings'**
  String get runValidationEnvMustBeStringMap;

  /// No description provided for @runValidationCwdMustBeString.
  ///
  /// In en, this message translates to:
  /// **'Working directory must be a string'**
  String get runValidationCwdMustBeString;

  /// No description provided for @runValidationConfigurationMustBeMap.
  ///
  /// In en, this message translates to:
  /// **'Configuration must be a map'**
  String get runValidationConfigurationMustBeMap;

  /// No description provided for @runValidationExecuteRequired.
  ///
  /// In en, this message translates to:
  /// **'Execute mode is required'**
  String get runValidationExecuteRequired;

  /// No description provided for @runValidationExecuteInvalid.
  ///
  /// In en, this message translates to:
  /// **'Execute must be Script file or Script text'**
  String get runValidationExecuteInvalid;

  /// No description provided for @runValidationScriptPathRequired.
  ///
  /// In en, this message translates to:
  /// **'Script path is required'**
  String get runValidationScriptPathRequired;

  /// No description provided for @runValidationScriptTextRequired.
  ///
  /// In en, this message translates to:
  /// **'Script text is required'**
  String get runValidationScriptTextRequired;

  /// No description provided for @runValidationInterpreterPathMustBeString.
  ///
  /// In en, this message translates to:
  /// **'Interpreter path must be a string'**
  String get runValidationInterpreterPathMustBeString;

  /// No description provided for @runValidationExecuteInTerminalMustBeBoolean.
  ///
  /// In en, this message translates to:
  /// **'Execute in the terminal must be a boolean'**
  String get runValidationExecuteInTerminalMustBeBoolean;

  /// No description provided for @runValidationAllowMultipleInstancesMustBeBoolean.
  ///
  /// In en, this message translates to:
  /// **'Allow multiple instances must be a boolean'**
  String get runValidationAllowMultipleInstancesMustBeBoolean;

  /// No description provided for @runValidationActivateToolWindowMustBeBoolean.
  ///
  /// In en, this message translates to:
  /// **'Activate tool window must be a boolean'**
  String get runValidationActivateToolWindowMustBeBoolean;

  /// No description provided for @runValidationFocusToolWindowMustBeBoolean.
  ///
  /// In en, this message translates to:
  /// **'Focus tool window must be a boolean'**
  String get runValidationFocusToolWindowMustBeBoolean;

  /// No description provided for @shortcutsRunSelected.
  ///
  /// In en, this message translates to:
  /// **'Run Selected Configuration'**
  String get shortcutsRunSelected;

  /// No description provided for @shortcutsRunStop.
  ///
  /// In en, this message translates to:
  /// **'Stop Run'**
  String get shortcutsRunStop;

  /// No description provided for @shortcutsRunRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart Run'**
  String get shortcutsRunRestart;

  /// No description provided for @shortcutsCategoryRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get shortcutsCategoryRun;

  /// No description provided for @shortcutsCommandPalette.
  ///
  /// In en, this message translates to:
  /// **'Command Palette'**
  String get shortcutsCommandPalette;

  /// No description provided for @commandPaletteSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Type a command…'**
  String get commandPaletteSearchHint;

  /// No description provided for @commandPaletteEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matching commands'**
  String get commandPaletteEmpty;

  /// No description provided for @shortcutsTerminalSplitRight.
  ///
  /// In en, this message translates to:
  /// **'Split Terminal Right'**
  String get shortcutsTerminalSplitRight;

  /// No description provided for @shortcutsTerminalSplitDown.
  ///
  /// In en, this message translates to:
  /// **'Split Terminal Down'**
  String get shortcutsTerminalSplitDown;

  /// No description provided for @shortcutsTerminalFocusNextPane.
  ///
  /// In en, this message translates to:
  /// **'Focus Next Pane'**
  String get shortcutsTerminalFocusNextPane;

  /// No description provided for @shortcutsTerminalFocusPrevPane.
  ///
  /// In en, this message translates to:
  /// **'Focus Previous Pane'**
  String get shortcutsTerminalFocusPrevPane;

  /// No description provided for @shortcutsTerminalFocusPaneLeft.
  ///
  /// In en, this message translates to:
  /// **'Focus Pane Left'**
  String get shortcutsTerminalFocusPaneLeft;

  /// No description provided for @shortcutsTerminalFocusPaneRight.
  ///
  /// In en, this message translates to:
  /// **'Focus Pane Right'**
  String get shortcutsTerminalFocusPaneRight;

  /// No description provided for @shortcutsTerminalFocusPaneUp.
  ///
  /// In en, this message translates to:
  /// **'Focus Pane Up'**
  String get shortcutsTerminalFocusPaneUp;

  /// No description provided for @shortcutsTerminalFocusPaneDown.
  ///
  /// In en, this message translates to:
  /// **'Focus Pane Down'**
  String get shortcutsTerminalFocusPaneDown;

  /// No description provided for @shortcutsTerminalZoomPane.
  ///
  /// In en, this message translates to:
  /// **'Toggle Pane Zoom'**
  String get shortcutsTerminalZoomPane;

  /// No description provided for @shortcutsTerminalEqualizePanes.
  ///
  /// In en, this message translates to:
  /// **'Equalize Panes'**
  String get shortcutsTerminalEqualizePanes;

  /// No description provided for @shortcutsTerminalClosePane.
  ///
  /// In en, this message translates to:
  /// **'Close Pane'**
  String get shortcutsTerminalClosePane;

  /// No description provided for @shortcutsTerminalLayoutSingle.
  ///
  /// In en, this message translates to:
  /// **'Layout: Single'**
  String get shortcutsTerminalLayoutSingle;

  /// No description provided for @shortcutsTerminalLayoutColumns2.
  ///
  /// In en, this message translates to:
  /// **'Layout: Two Columns'**
  String get shortcutsTerminalLayoutColumns2;

  /// No description provided for @shortcutsTerminalLayoutColumns3.
  ///
  /// In en, this message translates to:
  /// **'Layout: Three Columns'**
  String get shortcutsTerminalLayoutColumns3;

  /// No description provided for @shortcutsTerminalLayoutGrid.
  ///
  /// In en, this message translates to:
  /// **'Layout: Grid'**
  String get shortcutsTerminalLayoutGrid;

  /// No description provided for @shortcutsTerminalLayoutMainStack.
  ///
  /// In en, this message translates to:
  /// **'Layout: Main + Stack'**
  String get shortcutsTerminalLayoutMainStack;

  /// No description provided for @shortcutsTerminalCommandLog.
  ///
  /// In en, this message translates to:
  /// **'Show command log'**
  String get shortcutsTerminalCommandLog;

  /// No description provided for @shortcutsTerminalCommandHistory.
  ///
  /// In en, this message translates to:
  /// **'Show command history'**
  String get shortcutsTerminalCommandHistory;

  /// No description provided for @terminalColorSchemeTitle.
  ///
  /// In en, this message translates to:
  /// **'Terminal color scheme'**
  String get terminalColorSchemeTitle;

  /// No description provided for @terminalColorSchemeDescription.
  ///
  /// In en, this message translates to:
  /// **'Pick a built-in palette for embedded terminals, or tweak individual colors.'**
  String get terminalColorSchemeDescription;

  /// No description provided for @terminalColorSchemeGroupDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get terminalColorSchemeGroupDark;

  /// No description provided for @terminalColorSchemeGroupLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get terminalColorSchemeGroupLight;

  /// No description provided for @terminalColorSchemeGroupLegacy.
  ///
  /// In en, this message translates to:
  /// **'Adaptive & legacy'**
  String get terminalColorSchemeGroupLegacy;

  /// No description provided for @terminalColorSchemeByAuthor.
  ///
  /// In en, this message translates to:
  /// **'by {author}'**
  String terminalColorSchemeByAuthor(String author);

  /// No description provided for @terminalColorPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get terminalColorPreviewTitle;

  /// No description provided for @terminalUseCustomColorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Use custom colors'**
  String get terminalUseCustomColorsTitle;

  /// No description provided for @terminalUseCustomColorsDescription.
  ///
  /// In en, this message translates to:
  /// **'Override individual palette slots on top of the selected scheme.'**
  String get terminalUseCustomColorsDescription;

  /// No description provided for @terminalCustomColorsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom colors'**
  String get terminalCustomColorsSectionTitle;

  /// No description provided for @terminalColorResetAll.
  ///
  /// In en, this message translates to:
  /// **'Reset all'**
  String get terminalColorResetAll;

  /// No description provided for @terminalColorResetSlot.
  ///
  /// In en, this message translates to:
  /// **'Reset to scheme color'**
  String get terminalColorResetSlot;

  /// No description provided for @terminalColorInvalidHex.
  ///
  /// In en, this message translates to:
  /// **'Enter #RRGGBB or #AARRGGBB'**
  String get terminalColorInvalidHex;

  /// No description provided for @terminalSlotBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get terminalSlotBackground;

  /// No description provided for @terminalSlotForeground.
  ///
  /// In en, this message translates to:
  /// **'Foreground'**
  String get terminalSlotForeground;

  /// No description provided for @terminalSlotCursor.
  ///
  /// In en, this message translates to:
  /// **'Cursor'**
  String get terminalSlotCursor;

  /// No description provided for @terminalSlotSelection.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get terminalSlotSelection;

  /// No description provided for @terminalSlotSearchHit.
  ///
  /// In en, this message translates to:
  /// **'Search match'**
  String get terminalSlotSearchHit;

  /// No description provided for @terminalSlotSearchHitCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current match'**
  String get terminalSlotSearchHitCurrent;

  /// No description provided for @terminalSlotSearchHitFg.
  ///
  /// In en, this message translates to:
  /// **'Match text'**
  String get terminalSlotSearchHitFg;

  /// No description provided for @terminalSlotAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get terminalSlotAccent;

  /// No description provided for @terminalSlotAnsiLabel.
  ///
  /// In en, this message translates to:
  /// **'ANSI {index}'**
  String terminalSlotAnsiLabel(String index);

  /// No description provided for @terminalThemeImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import theme…'**
  String get terminalThemeImportAction;

  /// No description provided for @terminalThemeImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import terminal theme'**
  String get terminalThemeImportTitle;

  /// No description provided for @terminalThemeImportDescription.
  ///
  /// In en, this message translates to:
  /// **'Paste an Alacritty TOML or Ghostty config below, or choose a file.'**
  String get terminalThemeImportDescription;

  /// No description provided for @terminalThemeImportNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme name'**
  String get terminalThemeImportNameLabel;

  /// No description provided for @terminalThemeImportSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme file contents'**
  String get terminalThemeImportSourceLabel;

  /// No description provided for @terminalThemeImportChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file…'**
  String get terminalThemeImportChooseFile;

  /// No description provided for @terminalThemeImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get terminalThemeImportConfirm;

  /// No description provided for @terminalThemeImportFileReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read that file.'**
  String get terminalThemeImportFileReadFailed;

  /// No description provided for @terminalThemeImportEmptySource.
  ///
  /// In en, this message translates to:
  /// **'Paste the theme contents first.'**
  String get terminalThemeImportEmptySource;

  /// No description provided for @terminalThemeImportErrorFormat.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized format — expected Alacritty TOML ([colors.primary]) or Ghostty key = value lines.'**
  String get terminalThemeImportErrorFormat;

  /// No description provided for @terminalThemeImportErrorBackground.
  ///
  /// In en, this message translates to:
  /// **'No usable background color in that file.'**
  String get terminalThemeImportErrorBackground;

  /// No description provided for @terminalThemeImportErrorForeground.
  ///
  /// In en, this message translates to:
  /// **'No usable foreground color in that file.'**
  String get terminalThemeImportErrorForeground;

  /// No description provided for @terminalThemeImportErrorAnsi.
  ///
  /// In en, this message translates to:
  /// **'Missing the normal ANSI colors (0-7).'**
  String get terminalThemeImportErrorAnsi;

  /// No description provided for @terminalThemeImportSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the imported theme.'**
  String get terminalThemeImportSaveFailed;

  /// No description provided for @terminalThemeImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Imported “{name}”.'**
  String terminalThemeImportSuccess(String name);

  /// No description provided for @terminalThemeImportDerived.
  ///
  /// In en, this message translates to:
  /// **'Derived from the palette: {slots}'**
  String terminalThemeImportDerived(String slots);

  /// No description provided for @terminalColorSchemeGroupImported.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get terminalColorSchemeGroupImported;

  /// No description provided for @terminalThemeDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete imported theme'**
  String get terminalThemeDeleteTooltip;

  /// No description provided for @terminalThemeDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete imported theme?'**
  String get terminalThemeDeleteConfirmTitle;

  /// No description provided for @terminalThemeDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'“{name}” will be removed. Terminals using it fall back to the adaptive scheme.'**
  String terminalThemeDeleteConfirmMessage(String name);

  /// No description provided for @terminalThemeDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete that theme.'**
  String get terminalThemeDeleteFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
