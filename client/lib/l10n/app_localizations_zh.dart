// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get copy => '复制';

  @override
  String get settings => '设置';

  @override
  String get settingsPageSubtitle => '管理 FlashskyAI 团队和模型设置。';

  @override
  String get layout => '通用';

  @override
  String get save => '保存';

  @override
  String get ok => '确定';

  @override
  String get layoutPageSubtitle => '结构控件为全局设置，适用于所有团队。';

  @override
  String get right => '右侧';

  @override
  String get bottom => '底部';

  @override
  String get rightTools => '右侧工具栏';

  @override
  String get rightToolsPanelVisible => '显示工具栏';

  @override
  String get rightToolsPanelHidden => '隐藏工具栏';

  @override
  String get sidebarPanelVisible => '显示侧边栏';

  @override
  String get sidebarPanelHidden => '隐藏侧边栏';

  @override
  String get stacked => '堆叠';

  @override
  String get tabs => '标签页';

  @override
  String get regionVisibility => '区域可见性';

  @override
  String get visibilityFileTreeHint => '显示工作区文件树以便快速浏览。';

  @override
  String get visibilityGitHint => '显示当前仓库的源代码管理面板。';

  @override
  String get themeModeTitle => '主题模式';

  @override
  String get themeModeDescription => '浅色、深色，或与系统外观一致。';

  @override
  String get themeColorPresetTitle => '主题色';

  @override
  String get themeColorPresetDescription => '用于按钮、开关与高亮的主色与强调色。';

  @override
  String get typographyScaleTitle => '文字大小';

  @override
  String get typographyScaleDescription => '界面文字大小。「标准」跟随系统；不改变图标与间距。';

  @override
  String get typographyScaleCompact => '紧凑';

  @override
  String get typographyScaleStandard => '标准';

  @override
  String get typographyScaleComfortable => '宽松';

  @override
  String get typographyScaleCustom => '自定义';

  @override
  String get typographyScaleCustomHint => '50–200';

  @override
  String get fontUiTitle => '界面字体';

  @override
  String get fontUiDescription => '界面文字。系统跟随操作系统默认字体。重启后生效。';

  @override
  String get fontMonoTitle => '等宽字体';

  @override
  String get fontMonoDescription => '终端、编辑器与 diff。重启后生效。';

  @override
  String get fontChangeAppliesOnRestart => '字体已保存，重启 TeamPilot 后生效。';

  @override
  String get fontOptionSystem => '系统';

  @override
  String get fontOptionNotoSansSc => 'Noto Sans SC';

  @override
  String get fontOptionJetbrainsMono => 'JetBrains Mono';

  @override
  String get fontOptionUbuntuSansMono => 'Ubuntu Sans Mono';

  @override
  String get fontSearchHint => '搜索字体';

  @override
  String get uiZoomTitle => '界面缩放';

  @override
  String get uiZoomDescription => '整体缩放界面——文字、图标与间距一起。「标准」按系统缩放自动匹配。';

  @override
  String get markdownOpenModeTitle => '打开 Markdown 为';

  @override
  String get markdownOpenModeDescription =>
      '在编辑器中打开 .md 文件时的默认视图。「记住上次」仅在本次应用会话内有效。';

  @override
  String get markdownOpenModePreview => '预览';

  @override
  String get markdownOpenModeSource => '源码';

  @override
  String get markdownOpenModeRemember => '记住上次';

  @override
  String get markdownViewToggleSource => '源码';

  @override
  String get markdownViewTogglePreview => '预览';

  @override
  String get themePresetGraphite => '石墨';

  @override
  String get themePresetOcean => '海洋';

  @override
  String get themePresetViolet => '紫罗兰';

  @override
  String get themePresetAmber => '琥珀';

  @override
  String get themePresetForest => '森林';

  @override
  String get themePresetTerminal => '跟随终端';

  @override
  String get languageDescription => '菜单、按钮与标签所使用的语言。';

  @override
  String get cancel => '取消';

  @override
  String get close => '关闭';

  @override
  String get add => '添加';

  @override
  String get delete => '删除';

  @override
  String get appearance => '外观';

  @override
  String get workspaceEntryModeTitle => '启动视图';

  @override
  String get workspaceEntryModeDescription => 'App 启动后默认打开的页面。';

  @override
  String get workspaceEntryModeHome => '主页';

  @override
  String get workspaceEntryModeLastWorkspace => '恢复上次工作区';

  @override
  String get theme => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeDark => '深色';

  @override
  String get themeLight => '浅色';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get fileTree => '文件树';

  @override
  String get sourceControl => '源代码管理';

  @override
  String get gitStagedChanges => '暂存的更改';

  @override
  String get gitChanges => '更改';

  @override
  String get gitNoChanges => '没有更改';

  @override
  String get gitNotARepository => '当前文件夹不是 Git 仓库';

  @override
  String get gitNotInstalled => '未找到 Git。安装 Git 后即可使用源代码管理。';

  @override
  String get gitCommit => '提交';

  @override
  String gitCommitMessageHint(String branch) {
    return '消息（提交到 \"$branch\"）';
  }

  @override
  String get gitStage => '暂存更改';

  @override
  String get gitUnstage => '取消暂存';

  @override
  String get gitStageAll => '暂存所有更改';

  @override
  String get gitUnstageAll => '取消暂存所有更改';

  @override
  String get gitStageFolder => '暂存此目录下的更改';

  @override
  String get gitUnstageFolder => '取消暂存此目录下的更改';

  @override
  String get treeExpandAllFolders => '展开所有目录';

  @override
  String get treeCollapseAllFolders => '折叠所有目录';

  @override
  String get gitDiscard => '放弃更改';

  @override
  String get gitDiscardConfirmTitle => '放弃更改？';

  @override
  String gitDiscardConfirmBody(String path) {
    return '放弃 $path 中的所有更改？此操作无法撤销。';
  }

  @override
  String get gitPush => '推送';

  @override
  String get gitPull => '拉取';

  @override
  String get gitRefresh => '刷新';

  @override
  String get gitSwitchBranch => '切换分支';

  @override
  String get gitCreateBranch => '新建分支';

  @override
  String get gitNewBranchHint => '新分支名称';

  @override
  String gitError(String message) {
    return 'Git：$message';
  }

  @override
  String gitAheadBehind(int ahead, int behind) {
    return '↑$ahead ↓$behind';
  }

  @override
  String get filterFiles => '筛选文件';

  @override
  String get workspaces => '工作区';

  @override
  String get newWorkspace => '新建工作区';

  @override
  String get homeWorkspaceMainWindow => '主窗口';

  @override
  String get windowControlMinimize => '最小化';

  @override
  String get windowControlMaximize => '最大化';

  @override
  String get windowControlRestore => '还原';

  @override
  String get windowControlClose => '关闭';

  @override
  String get windowControlAlwaysOnTop => '置顶';

  @override
  String get homeWorkspaceMyFavorites => '我的收藏';

  @override
  String get homeWorkspaceRecentVisits => '最近访问';

  @override
  String get homeWorkspaceAllWorkspaces => '全部工作区';

  @override
  String get homeWorkspaceNoData => '暂无数据';

  @override
  String get homeWorkspaceRecentlyClosed => '最近关闭';

  @override
  String get homeWorkspaceRecentlyClosedEmpty => '暂无最近关闭的工作区';

  @override
  String get homeWorkspaceSessionsLabel => '会话';

  @override
  String get homeWorkspaceEmptyWorkspaces => '该团队还没有工作区';

  @override
  String get homeWorkspaceEmptyWorkspacesHint => '新建或导入一个工作区开始吧';

  @override
  String get homeWorkspaceWorkspaceSort => '排序工作区';

  @override
  String get homeWorkspaceWorkspaceSortRecentlyUpdated => '最近更新';

  @override
  String get homeWorkspaceWorkspaceSortNameAsc => '名称（A–Z）';

  @override
  String get homeWorkspaceWorkspaceSortNameDesc => '名称（Z–A）';

  @override
  String get homeWorkspaceWorkspaceSortCreatedDesc => '创建时间';

  @override
  String get homeWorkspaceWorkspaceSortSessionCountDesc => '会话数量';

  @override
  String get homeWorkspaceNewWorkspaceSubtitle => '选择工作区的工作目录，并为它命名。';

  @override
  String get homeWorkspaceNewWorkspaceDirectoryLabel => '工作区目录';

  @override
  String get homeWorkspaceNewWorkspaceChooseDirectory => '选择文件夹';

  @override
  String get homeWorkspaceNewWorkspaceDirectoryHint => '尚未选择目录';

  @override
  String get homeWorkspaceNewWorkspaceNameHint => '默认使用文件夹名';

  @override
  String get homeWorkspaceCreateWorkspace => '创建工作区';

  @override
  String get homeWorkspaceCloseWorkspaceTitle => '关闭工作区？';

  @override
  String homeWorkspaceCloseWorkspaceMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '关闭该标签会终止此工作区中 $count 个运行中的会话。',
      one: '关闭该标签会终止此工作区中 1 个运行中的会话。',
    );
    return '$_temp0';
  }

  @override
  String get homeWorkspaceCloseWorkspaceConfirm => '关闭并终止会话';

  @override
  String get homeWorkspaceWorkspaceManagement => '工作区管理';

  @override
  String get homeWorkspaceConversationsSection => '对话';

  @override
  String get homeWorkspaceWorkspaceSettings => '工作区设置';

  @override
  String get homeWorkspaceWorkspaceSettingsBasicInfo => '基本信息';

  @override
  String get homeWorkspaceWorkspaceId => '工作区 ID';

  @override
  String get deleteWorkspaceSubtitle => '将删除该工作区及其下所有会话，且无法恢复。';

  @override
  String get homeWorkspaceNewConversation => '新建对话';

  @override
  String get workbenchStripNewMenuTooltip => '新建';

  @override
  String get workspaceSearchTitle => '搜索';

  @override
  String get workspaceSearchHint => '搜索会话和文件';

  @override
  String get workspaceSearchFilesSection => '文件';

  @override
  String get workspaceSearchSearching => '正在搜索文件…';

  @override
  String get workspaceSearchNoResults => '没有匹配结果';

  @override
  String get workspaceSearchFilesTruncated => '还有更多文件，请细化搜索';

  @override
  String get homeWorkspaceOpenWorkspaceInNewTab => '在新标签页中打开';

  @override
  String get homeWorkspaceFavoriteWorkspace => '收藏工作区';

  @override
  String get homeWorkspaceUnfavoriteWorkspace => '取消收藏';

  @override
  String get homeWorkspaceRenameWorkspace => '修改名称';

  @override
  String get homeWorkspaceCloneWorkspace => '克隆工作区';

  @override
  String homeWorkspaceCloneWorkspaceDisplayName(Object name) {
    return '$name（副本）';
  }

  @override
  String homeWorkspaceCloneWorkspaceSuccess(Object name) {
    return '已克隆「$name」。';
  }

  @override
  String get homeWorkspaceCloneWorkspaceFailed => '无法克隆工作区';

  @override
  String get create => '创建';

  @override
  String get workspacePrimaryPathNotSelected => '尚未选择主目录';

  @override
  String get defaultNewChatSessionTitle => '新对话';

  @override
  String get sessionStarting => '正在启动会话…';

  @override
  String get sessionRetryButton => '重试';

  @override
  String get copyFolderPath => '复制文件夹路径';

  @override
  String pathCopied(String path) {
    return '已复制路径：$path';
  }

  @override
  String get addWorkspaceDirectory => '添加目录';

  @override
  String get workspaceDisplayName => '显示名称';

  @override
  String get workspaceIcon => '图标';

  @override
  String get workspaceNavUngrouped => '未分组';

  @override
  String get workspaceNavNewGroup => '新建分组';

  @override
  String get workspaceNavGroupNameHint => '分组名称';

  @override
  String get workspaceGroupRename => '重命名分组';

  @override
  String get workspaceGroupDelete => '删除分组';

  @override
  String get workspaceGroupAccentColor => '分组颜色';

  @override
  String get workspaceMoveToGroup => '移动到分组';

  @override
  String get workspaceRemoveFromGroup => '移出分组';

  @override
  String get workspaceDefaultTerminal => '默认终端';

  @override
  String get workspaceDefaultTerminalGlobal => '全局默认';

  @override
  String get workspaceAccentColor => '主题色';

  @override
  String get workspaceMoveUp => '上移';

  @override
  String get workspaceMoveDown => '下移';

  @override
  String get workspaceIconPickerTitle => '选择工作区图标';

  @override
  String get workspaceIconUseDefault => '使用默认';

  @override
  String get workspaceIconUpload => '上传图标';

  @override
  String get workspaceSessionCount => '会话数';

  @override
  String get workspaceCreatedAt => '创建时间';

  @override
  String get workspaceUpdatedAt => '更新时间';

  @override
  String get workspaceDirectoryAlreadyAdded => '该目录已在工作区中。';

  @override
  String get remoteDirectoryBrowserTitle => '浏览远程目录';

  @override
  String get remoteDirectoryBrowserUpOneLevel => '上一级';

  @override
  String get remoteDirectoryBrowserUseThisDirectory => '使用此目录';

  @override
  String get remoteDirectoryBrowserTypePathLabel => '或手动输入路径';

  @override
  String get remoteDirectoryBrowserTypePathHint => '~/work/workspace';

  @override
  String get remoteDirectoryBrowserUseTypedPath => '使用路径';

  @override
  String get remoteDirectoryBrowserError => '无法打开远程目录。你仍可在下方手动输入路径。';

  @override
  String get remoteDirectoryBrowserEmpty => '此处没有子目录';

  @override
  String get deleteWorkspace => '删除工作区';

  @override
  String deleteWorkspaceConfirm(String name) {
    return '删除工作区 \"$name\" 及其所有会话？此操作不可撤销。';
  }

  @override
  String get renameConversation => '重命名对话';

  @override
  String get deleteConversation => '删除对话';

  @override
  String get pinConversation => '置顶对话';

  @override
  String get unpinConversation => '取消置顶';

  @override
  String get renameConversationTitle => '重命名对话';

  @override
  String get conversationName => '对话名称';

  @override
  String get closeTab => '关闭';

  @override
  String get closeOtherTabs => '关闭其他标签';

  @override
  String get closeRightTabs => '关闭右侧标签';

  @override
  String get session => '会话';

  @override
  String get sessionPageSubtitle => '配置 Shell 会话启动方式、终端行为与存储后端。';

  @override
  String get sshProfilesSettingsTitle => 'SSH 服务器';

  @override
  String get sshProfilesPageTitle => 'SSH 远程主机';

  @override
  String get sshProfilesPageSubtitle => '通过 SSH 使用已有机器处理文件、终端、Git 和工作区。';

  @override
  String get sshProfilesTargetsTitle => '目标';

  @override
  String get sshProfilesTargetsSubtitle => '添加远程主机以在 TeamPilot 中连接到它。';

  @override
  String get sshProfilesImport => '导入';

  @override
  String get sshProfilesImportUnavailable => '暂不支持从 ~/.ssh/config 导入。';

  @override
  String get sshProfilesAddTarget => '添加目标';

  @override
  String get sshProfilesEmpty => '尚未配置 SSH 目标。';

  @override
  String get sshProfileStatusDisconnected => '未连接';

  @override
  String get sshProfileStatusConnecting => '连接中…';

  @override
  String get sshProfileStatusConnected => '已连接';

  @override
  String get sshProfileStatusError => '错误';

  @override
  String get sshProfileStatusReconnecting => '重连中…';

  @override
  String get sshProfileStatusAuthFailed => '认证失败';

  @override
  String get sshProfileTest => '测试';

  @override
  String get sshProfileConnect => '连接';

  @override
  String get sshProfileDisconnect => '断开';

  @override
  String get sshProfileEdit => '编辑';

  @override
  String get sshProfileDelete => '删除';

  @override
  String get sshProfileRefresh => '刷新';

  @override
  String get sshProfileTestSuccess => '连接成功';

  @override
  String get sshProfileTestFailedHostKey => '主机密钥未获信任';

  @override
  String get sshProfileTestFailedAuth => '身份验证失败';

  @override
  String sshProfileTestFailedAborted(String detail) {
    return '登录前连接已断开：$detail';
  }

  @override
  String sshProfileTestFailedDetail(String detail) {
    return '连接测试失败：$detail';
  }

  @override
  String sshProfileConnectSuccess(String host) {
    return '已连接到 $host';
  }

  @override
  String get sshHostKeyUnknownTitle => '验证 SSH 主机密钥';

  @override
  String sshHostKeyUnknownBody(String host) {
    return 'TeamPilot 尚未见过 $host。请确认指纹与该机器一致后再信任。';
  }

  @override
  String get sshHostKeyMismatchTitle => 'SSH 主机密钥已变更';

  @override
  String sshHostKeyMismatchBody(String host) {
    return '$host 的主机密钥与 TeamPilot 先前保存的不一致。可能是系统重装，也可能是连接被劫持。';
  }

  @override
  String get sshHostKeyFingerprintLabel => '指纹';

  @override
  String get sshHostKeyPreviousFingerprintLabel => '先前信任的指纹';

  @override
  String sshHostKeyKeyTypeLabel(String keyType) {
    return '密钥类型：$keyType';
  }

  @override
  String get sshHostKeyTrust => '信任并继续';

  @override
  String get sshHostKeyReplaceTrust => '替换并信任';

  @override
  String get sshProfileFormTitleNew => '新的 SSH 目标';

  @override
  String get sshProfileFormTitleEdit => '编辑 SSH 目标';

  @override
  String get sshProfileFormLabel => '标签';

  @override
  String get sshProfileFormLabelHint => '我的服务器';

  @override
  String get sshProfileFormHost => '主机或别名';

  @override
  String get sshProfileFormHostHint => 'server、deploy@server:2222';

  @override
  String get sshProfileFormUsername => '用户名';

  @override
  String get sshProfileFormUsernameHint => 'deploy';

  @override
  String get sshProfileFormPort => '端口';

  @override
  String get sshProfileFormPortInvalid => '端口须在 1–65535 之间';

  @override
  String get sshProfileFormIdentityFile => '身份文件';

  @override
  String get sshProfileFormIdentityFileHint => '~/.ssh/id_ed25519';

  @override
  String get sshProfileFormIdentityFileHelper => '可选。填写后从磁盘读取私钥。';

  @override
  String get sshProfileFormIdentityFileBrowse => '浏览…';

  @override
  String get sshProfileFormIdentityFileMissing => '找不到身份文件';

  @override
  String get sshProfileFormPassphrase => '密钥口令';

  @override
  String get sshProfileFormPassphraseHint => '可选';

  @override
  String get sshProfileFormPassword => '密码';

  @override
  String get sshProfileFormPasswordHint => '未设置身份文件时使用';

  @override
  String get sshProfileFormPasswordHintEdit => '留空则保留已保存密码';

  @override
  String get sshProfileFormPasswordHelper => '若已提供身份文件则可不填。';

  @override
  String get sshProfileFormCredentialRequired => '请提供身份文件或密码。';

  @override
  String get sshProfileFormFieldRequired => '必填';

  @override
  String get sshProfileSelectorManage => '管理 SSH 服务器…';

  @override
  String get sshDefaultWorkingDirectoryTitle => 'SSH 默认工作目录';

  @override
  String get sshDefaultWorkingDirectorySubtitle =>
      'SSH 启动没有工作区路径时使用的远端工作目录；留空则不切换目录。';

  @override
  String get cliExecutablePathReset => '重置';

  @override
  String get terminalFind => '在终端中查找';

  @override
  String get terminalFindNoResults => '无匹配';

  @override
  String get terminalDropCrossMachineRejected => '无法将本地文件拖入远程终端';

  @override
  String get editorSave => '保存';

  @override
  String get editorCut => '剪切';

  @override
  String get editorCopy => '复制';

  @override
  String get editorCopyAsAiContext => '复制为 AI 上下文';

  @override
  String get editorPaste => '粘贴';

  @override
  String get editorSelectAll => '全选';

  @override
  String get editorUndoEdit => '撤销';

  @override
  String get editorRedoEdit => '重做';

  @override
  String get editorRevertChanges => '撤销修改';

  @override
  String get editorUnsavedChangesTitle => '未保存的更改';

  @override
  String editorUnsavedChangesDiscardMultiple(int count) {
    return '放弃 $count 个文件中的未保存修改？';
  }

  @override
  String get editorDiscard => '放弃';

  @override
  String get editorNotReady => '编辑器未就绪';

  @override
  String get editorBinaryFileHint => '二进制文件将使用系统默认应用打开。';

  @override
  String get editorFileNotFound => '找不到文件';

  @override
  String get editorFileTooLarge => '文件过大，无法在 TeamPilot 中编辑（上限 2 MB）。';

  @override
  String get editorImageTooLarge => '图片过大，无法在 TeamPilot 中预览（上限 25 MB）。';

  @override
  String get editorImageDecodeFailed => '无法解码此图片。';

  @override
  String get editorCouldNotReadFile => '无法读取文件';

  @override
  String get editorFileReadOnly => '文件为只读';

  @override
  String editorSaveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get fileTreeRevealActiveFile => '定位当前文件';

  @override
  String get fileTreeRefresh => '刷新';

  @override
  String get fileTreeShowFilter => '显示筛选';

  @override
  String get fileTreeHideFilter => '隐藏筛选';

  @override
  String get fileTreeRevealFailed => '无法在文件树中定位该文件';

  @override
  String get fileTreeOpenWithSystemApp => '用系统应用打开';

  @override
  String get fileTreeCopyPath => '复制路径';

  @override
  String get fileTreeDeleteItemTitle => '删除';

  @override
  String fileTreeDeleteItemConfirm(String name) {
    return '删除「$name」？';
  }

  @override
  String get fileTreeNewFile => '新建文件';

  @override
  String get fileTreeNewFolder => '新建文件夹';

  @override
  String get fileTreeCreateNameHint => '名称';

  @override
  String get fileTreeCut => '剪切';

  @override
  String get fileTreeCopy => '复制';

  @override
  String get fileTreePaste => '粘贴';

  @override
  String get fileTreeRename => '重命名';

  @override
  String get fileTreeRenameTitle => '重命名';

  @override
  String get fileTreeOpenInFileManager => '在文件管理器中打开';

  @override
  String get fileTreeOpenInTerminal => '在终端中打开';

  @override
  String get fileTreePasteDone => '已粘贴';

  @override
  String get fileTreeFileCreated => '已创建文件';

  @override
  String get fileTreeFolderCreated => '已创建文件夹';

  @override
  String get fileTreeRenameDone => '已重命名';

  @override
  String get fileTreeDeleteDone => '已删除';

  @override
  String get fileTreeInvalidName => '名称无效';

  @override
  String get fileTreeItemExists => '同名项目已存在';

  @override
  String get fileTreeSourceMissing => '源文件不存在';

  @override
  String get fileTreeInvalidPasteTarget => '无法粘贴到此处';

  @override
  String get fileTreeOpenInTerminalFailed => '无法打开终端';

  @override
  String get terminalOpenLink => '打开链接';

  @override
  String get terminalExportScrollback => '导出滚动缓冲…';

  @override
  String get terminalCopySelectHint => '按住 Shift 选择复制';

  @override
  String get workspaceTerminalNoWorkingDirectory => '请先连接会话以打开 Shell 终端';

  @override
  String get workspaceTerminalNewSession => '新建终端';

  @override
  String get workspaceTerminalNewSshSession => '新建 SSH 会话…';

  @override
  String get workspaceTerminalSettings => '设置';

  @override
  String get workspaceTerminalThemeAdaptive => '跟随主题';

  @override
  String get workspaceTerminalThemeClassicDark => '经典暗色';

  @override
  String get workspaceTerminalThemeHighContrast => '高对比';

  @override
  String get workspaceTerminalSshConnectFailed => 'SSH 配置未找到或连接失败';

  @override
  String get workspaceToolsResolveFailed => '无法打开工作区工具';

  @override
  String get workspaceToolsResolveFailedHint => '请确认远程机器可连通后再重试。';

  @override
  String get workspaceTerminalSplitRight => '向右拆分';

  @override
  String get workspaceTerminalSplitDown => '向下拆分';

  @override
  String get workspaceTerminalLayout => '布局';

  @override
  String get workspaceTerminalLayoutSingle => '单窗格';

  @override
  String get workspaceTerminalLayoutColumns2 => '2 列';

  @override
  String get workspaceTerminalLayoutColumns3 => '3 列';

  @override
  String get workspaceTerminalLayoutGrid => '2×2 网格';

  @override
  String get workspaceTerminalLayoutMainStack => '主窗格 + 堆叠';

  @override
  String get workspaceTerminalEqualize => '均分窗格';

  @override
  String get workspaceTerminalZoomPane => '缩放窗格';

  @override
  String get workspaceTerminalUnzoomPane => '取消缩放';

  @override
  String get workspaceTerminalClosePane => '关闭窗格';

  @override
  String get workspaceTerminalClearScreen => '清屏';

  @override
  String get workspaceTerminalSearch => '搜索';

  @override
  String get workspaceTerminalCommandLog => '命令日志';

  @override
  String get commandLogTitle => '命令日志';

  @override
  String get commandLogRefresh => '刷新';

  @override
  String get commandLogOpenFolder => '打开日志目录';

  @override
  String get commandLogClose => '关闭';

  @override
  String get commandLogAllWorkspaces => '全部工作区';

  @override
  String get commandLogAllSurfaces => '全部标签页';

  @override
  String get commandLogAllPanes => '全部窗格';

  @override
  String get commandLogSearchHint => '搜索命令或工作目录';

  @override
  String get commandLogClearFilters => '清除筛选';

  @override
  String get commandLogColumnTime => '时间';

  @override
  String get commandLogColumnWorkspace => '工作区';

  @override
  String get commandLogColumnSurface => '标签页';

  @override
  String get commandLogColumnPane => '窗格';

  @override
  String get commandLogColumnCommand => '命令';

  @override
  String get commandLogColumnDirectory => '工作目录';

  @override
  String get commandLogColumnExitCode => '退出码';

  @override
  String get commandLogColumnDuration => '时长';

  @override
  String get commandLogEmpty => '暂无命令记录。Shell 上报提示符标记（OSC 133）后会自动记录。';

  @override
  String get commandLogNoMatches => '没有命令匹配当前筛选';

  @override
  String commandLogEntryCount(int count) {
    return '$count 条';
  }

  @override
  String commandLogSkippedLines(int count) {
    return '已跳过 $count 行无法解析的记录';
  }

  @override
  String get commandLogCopyCommand => '复制命令';

  @override
  String get commandLogCopied => '命令已复制';

  @override
  String get commandLogInsertIntoPane => '插入到当前窗格';

  @override
  String get commandLogRunInPane => '在当前窗格执行';

  @override
  String get commandHistoryTitle => '命令历史';

  @override
  String commandHistoryPaneTitle(String pane) {
    return '命令历史 · 窗格 $pane';
  }

  @override
  String get commandHistorySearchHint => '搜索命令';

  @override
  String get commandHistoryHint => 'Enter = 执行，Shift+Enter = 插入';

  @override
  String get commandHistoryEmpty => '该窗格暂无命令历史。';

  @override
  String get commandHistoryNoMatches => '没有匹配的命令';

  @override
  String commandHistoryCount(int count) {
    return '$count 条命令';
  }

  @override
  String get commandHistoryCopy => '复制';

  @override
  String get commandHistoryCopied => '已复制命令';

  @override
  String get commandHistoryInsert => '插入';

  @override
  String get commandHistoryRun => '执行';

  @override
  String get commandHistoryClose => '关闭';

  @override
  String get terminalScrollbackLinesTitle => '终端滚动缓冲行数';

  @override
  String get terminalScrollbackLinesDescription => '每个会话终端保留的最大行数';

  @override
  String get terminalLinkClickOpensInAppTitle => '在应用内打开终端链接';

  @override
  String get terminalLinkClickOpensInAppDescription =>
      '左键点击链接和文件路径时在 TeamPilot 内打开，而不是交给正在运行的程序。Ctrl/Cmd+点击始终在应用内打开。';

  @override
  String terminalParkedSendPending(String content) {
    return '已发送，等待接收：$content';
  }

  @override
  String get terminalParkedSendDismiss => '关闭';

  @override
  String get terminalMirrorTakeoverTitle => '手机正在使用此终端';

  @override
  String terminalMirrorTakeoverHint(int cols, int rows) {
    return '$cols×$rows · 手机断开后本窗格自动恢复';
  }

  @override
  String get mailbox => '信箱';

  @override
  String get openExistingSessionStartsTerminalTitle => '打开已有会话时直接启动终端';

  @override
  String get openExistingSessionStartsTerminalDescription =>
      '开启后，打开已保存会话会立即连接终端。关闭（默认）时先显示聊天视图，发送消息后才启动终端。';

  @override
  String get simpleModeDefaultFullAccessTitle => '简单模式默认：完全访问';

  @override
  String get simpleModeDefaultFullAccessDescription =>
      '开启（默认）时，简单模式落地页默认使用完全访问权限。工作区里权限芯片的选择仍会覆盖并按工作区持久化。';

  @override
  String get notifyOnSessionIdleTitle => 'Agent 空闲系统通知';

  @override
  String get notifyOnSessionIdleDescription =>
      '终端输出结束一轮并进入空闲（agent 完成一轮）时，除应用内通知中心外，同时发送操作系统通知。';

  @override
  String get notifyOnPtyIdleTitle => '终端输出静默时通知';

  @override
  String get notifyOnPtyIdleDescription =>
      '默认关闭。对不上报状态的终端，用 PTY 输出转为静默来猜测一轮结束；构建、跑测试这类长命令也会触发。能通过状态钩子上报的 Agent 无需此项即可精确通知。';

  @override
  String get barkPushSectionTitle => '手机推送（Bark）';

  @override
  String get barkPushSectionSubtitle =>
      '手机未连接到本桌面时也能收到。通知里带工作区名和标签页标题，便于区分多个 Agent。';

  @override
  String get barkPushModeTitle => '推送 Agent 通知到 Bark';

  @override
  String get barkPushModeDescription => '包含完成一轮、等待授权、被打断三类。';

  @override
  String get barkPushModeOff => '关闭';

  @override
  String get barkPushModeDisconnected => '仅在无手机连接时';

  @override
  String get barkPushModeAlways => '总是推送';

  @override
  String get barkPushServerTitle => 'Bark 服务器';

  @override
  String get barkPushServerDescription => '自建服务器才需要改。只填源地址，不要带 /push 路径。';

  @override
  String get barkPushDeviceKeyTitle => '设备 Key';

  @override
  String get barkPushDeviceKeyDescription =>
      '在 Bark App 首页获取。存放在系统钥匙串，不写入偏好设置文件。';

  @override
  String get barkPushTest => '发送测试';

  @override
  String get barkPushTestOk => '测试推送已送达。';

  @override
  String get barkPushTestFailed => '测试推送失败';

  @override
  String get barkPushTestTitle => 'TeamPilot';

  @override
  String get barkPushTestBody => '推送通道正常。';

  @override
  String get notifyWhileWatchingTitle => '正在查看时也通知';

  @override
  String get notifyWhileWatchingDescription =>
      '开启（默认）时，即使应用在前台、且你正停在报告事件的那个终端上，仍然发送通知。关闭则对正在查看的终端不再打扰。';

  @override
  String get sessionIdleNotificationTitle => 'Agent 已就绪';

  @override
  String get sessionIdleNotificationSubtitle => '可以继续对话了';

  @override
  String get agentDoneNotificationTitle => 'Agent 已完成';

  @override
  String get agentDoneNotificationBody => 'Agent 完成了本轮，等待你的下一步。';

  @override
  String get agentInterruptedNotificationTitle => 'Agent 已中断';

  @override
  String get agentInterruptedNotificationBody => 'Agent 本轮被取消。';

  @override
  String get agentWaitingNotificationTitle => 'Agent 需要授权';

  @override
  String get agentWaitingNotificationBody => 'Agent 正在等待你的授权以继续。';

  @override
  String get credentialPushOptInTitle => '把凭证推送到此机器';

  @override
  String get credentialPushOptInSubtitle => '供远程成员认证使用。';

  @override
  String get credentialPushConfirmTitle => '确认把凭证推送到远程主机？';

  @override
  String credentialPushConfirmBody(Object host) {
    return 'provider 密钥将写入远程主机 $host。请仅对你信任的机器开启。轮换密钥后需重推到每台已开启的机器。';
  }

  @override
  String get credentialPushConfirmAction => '推送凭证';

  @override
  String get rootSandboxEnvOptInTitle => '为 root 注入 IS_SANDBOX';

  @override
  String get rootSandboxEnvOptInSubtitle =>
      'root 启动 Claude 时保留 skip-permissions。';

  @override
  String get rootSandboxEnvConfirmTitle => '确认为 root 启用 sandbox 环境变量？';

  @override
  String rootSandboxEnvConfirmBody(Object host) {
    return '在 $host 上以 root 启动 Claude 时，TeamPilot 将设置 IS_SANDBOX=1 并保留 --dangerously-skip-permissions。请仅对你信任的机器开启。';
  }

  @override
  String get rootSandboxEnvConfirmAction => '启用';

  @override
  String get workspaceFoldersSectionTitle => '工作区目录与机器';

  @override
  String get workspaceFoldersEditorHint =>
      '每个目录单独指定所在机器与路径。全部本地 = 本地工作区；全部同一远程 = 项目远程；跨机 = 混合工作区（成员远程）。';

  @override
  String get workspaceFoldersMixedTargetsLockedHint =>
      '混合工作区：各目录所在机器已固定。可在上方现有机器上添加路径；成员分配请使用下方「分配」按钮。';

  @override
  String get workspaceFoldersPersonalTargetsLockedHint =>
      '个人身份下无法更改目录所在机器。请切换到团队身份配置机器与目录。';

  @override
  String get workspaceTopologyLocal => '本地工作区';

  @override
  String get workspaceTopologyRemote => '远程工作区';

  @override
  String get workspaceTopologyMixed => '混合工作区';

  @override
  String get workspaceTypeLabel => '类型';

  @override
  String get mixedWorkspaceCreateSessionBlocked =>
      '请先在团队设置中确认机器分配，再在此混合工作区新建对话。';

  @override
  String get mixedWorkspaceSessionLaunchBlocked =>
      '该对话的机器分配已失效。请在团队设置中确认分配后新建对话。';

  @override
  String get sessionLaunchMissingWorkspace => '找不到该对话所属的工作区。';

  @override
  String get sessionLaunchMissingTeamMember => '团队成员不可用，请选择团队后重试。';

  @override
  String get workspaceFolderTargetLabel => '所在机器';

  @override
  String get workspaceFoldersPickTarget => '选择机器';

  @override
  String get workspaceDeadTargetBadge => '机器不可用';

  @override
  String get workspaceDeadTargetRemap => '重新映射…';

  @override
  String get workspaceDeadTargetRemapTitle => '重新映射机器';

  @override
  String workspaceDeadTargetRemapBody(String from) {
    return '将 $from 替换为另一台机器。目录路径不会改动，目标机器上必须已有相同路径。';
  }

  @override
  String get workspaceDeadTargetRemapPickFrom => '失效机器';

  @override
  String get workspaceDeadTargetRemapPickTo => '替换为';

  @override
  String get workspaceDeadTargetRemapConfirm => '重新映射';

  @override
  String get workspaceDeadTargetRemapNothing => '没有可映射的目标。';

  @override
  String get workspaceDeadTargetRemapFailed => '无法重新映射机器。';

  @override
  String get workspaceDeadTargetRemapFromLaunch => '重新映射机器…';

  @override
  String get homeTargetTitle => '主设备';

  @override
  String get homeTargetSubtitle =>
      'TeamPilot 存放团队、工作区与配置的位置（控制面）。切换会使用独立的数据目录，不会自动迁移。';

  @override
  String bootstrapStartupFailed(String error) {
    return '启动失败：$error';
  }

  @override
  String get bootstrapUseNativeStorageInstead => '改用 Windows 本地存储';

  @override
  String get providers => '提供商';

  @override
  String providerListModelCount(int count) {
    return '$count 个模型';
  }

  @override
  String get proxyOnShort => '代理开';

  @override
  String get proxyOffShort => '代理关';

  @override
  String get type => '类型';

  @override
  String get proxy => '代理';

  @override
  String get reveal => '显示';

  @override
  String get hide => '隐藏';

  @override
  String get claudeLaunchCredentialsMissingWarning =>
      '该 Team 绑定的 Claude Official Provider 缺少凭据，请在 Providers 设置中登录。';

  @override
  String get api => 'api';

  @override
  String get account => 'account';

  @override
  String get models => '模型';

  @override
  String get enabled => '启用';

  @override
  String get edit => '编辑';

  @override
  String get name => '名称';

  @override
  String get summary => '摘要';

  @override
  String get validation => '验证';

  @override
  String get validate => '校验';

  @override
  String get back => '返回';

  @override
  String get members => '成员';

  @override
  String get configure => '配置';

  @override
  String get teamConfig => '团队配置';

  @override
  String get teamSettings => '团队设置';

  @override
  String get confirm => '确认';

  @override
  String get dangerZone => '危险操作';

  @override
  String get memberName => '成员名称';

  @override
  String get provider => '提供商';

  @override
  String get model => '模型';

  @override
  String get agent => 'Agent 预设';

  @override
  String get prompt => '提示词';

  @override
  String get appProviderClaudeAuthTokenDefault => 'ANTHROPIC_AUTH_TOKEN（默认）';

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
  String get notes => '备注';

  @override
  String get aboutTitle => '关于';

  @override
  String get aboutPageSubtitle => 'TeamPilot 版本与应用更新。';

  @override
  String get aboutGitHub => 'GitHub';

  @override
  String get aboutCurrentVersion => '当前版本';

  @override
  String get aboutVersionLoading => '加载中…';

  @override
  String get appUpdateCheck => '检查更新';

  @override
  String get appUpdateAutoCheck => '自动检查更新';

  @override
  String get appUpdateAutoCheckHint => '每次启动时自动从 GitHub 检查新版本。';

  @override
  String get appUpdateSkipVersion => '跳过此版本';

  @override
  String get appUpdateDownloadInstall => '下载并安装';

  @override
  String get appUpdateUpToDate => '已是最新版本。';

  @override
  String get appUpdateDownloading => '正在下载更新…';

  @override
  String get appUpdateInstalling => '正在安装更新…';

  @override
  String get appUpdateViewRelease => '在 GitHub 查看发布';

  @override
  String get appUpdateViewReleases => '查看发布';

  @override
  String appUpdateNewVersion(String version) {
    return '新版本 $version 可用';
  }

  @override
  String get appUpdateDialogTitle => '发现新版本';

  @override
  String get appUpdateLatestVersion => '最新版本';

  @override
  String get appUpdateChangelogTitle => '更新内容';

  @override
  String get appUpdateChangelogDefaultSection => '更新';

  @override
  String get appUpdateLater => '以后更新';

  @override
  String get appUpdateDownloadInBackground => '后台下载';

  @override
  String get onboardingSkip => '跳过';

  @override
  String get onboardingPrevious => '上一步';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingGetStarted => '开始使用';

  @override
  String get onboardingAppearanceTitle => '选择语言与外观';

  @override
  String get onboardingAppearanceSubtitle => '可随时在「设置 → 布局」中修改。';

  @override
  String get onboardingSshTitle => '配置 SSH 连接';

  @override
  String get onboardingSshSubtitle => 'Android 通过 SSH 在远程主机运行 AI CLI。';

  @override
  String get onboardingRerunSetup => '重新运行设置向导';

  @override
  String get logViewerTitle => '日志';

  @override
  String get logViewerSubtitle => '应用数据目录下的运行日志与错误记录。';

  @override
  String get logViewerSearchHint => '搜索日志…';

  @override
  String get logViewerWrapLines => '自动换行';

  @override
  String get logViewerReverseOrder => '从最新内容开始';

  @override
  String get logViewerCompactView => '简洁视图';

  @override
  String logViewerLineCount(int count) {
    return '$count 行';
  }

  @override
  String get logViewerActionsMenu => '更多操作';

  @override
  String get logViewerRefresh => '刷新';

  @override
  String get logViewerCopyPath => '复制日志路径';

  @override
  String get logViewerClearOld => '清理过期日志';

  @override
  String get logViewerEmpty => '暂无日志文件';

  @override
  String get logViewerEmptyHint => '应用运行后会在此生成日志。';

  @override
  String get logViewerPendingTitle => '日志尚未写入磁盘';

  @override
  String get logViewerPendingBody => '以下为等待写入文件的缓冲条目：';

  @override
  String logViewerLoadFilesFailed(String error) {
    return '加载日志列表失败：$error';
  }

  @override
  String logViewerReadFailed(String error) {
    return '读取日志失败：$error';
  }

  @override
  String get logViewerClearDone => '已清理过期日志';

  @override
  String logViewerClearFailed(String error) {
    return '清理失败：$error';
  }

  @override
  String logViewerPathCopied(String name) {
    return '已复制路径：$name';
  }

  @override
  String get initErrorTitle => '应用启动失败';

  @override
  String get initErrorDetails => '错误信息';

  @override
  String get initErrorStackTrace => '堆栈跟踪';

  @override
  String get initErrorPendingLogs => '待写入日志';

  @override
  String get initErrorViewLogs => '查看日志';

  @override
  String get initErrorCopyReport => '复制报告';

  @override
  String get initErrorCopy => '复制';

  @override
  String get initErrorCopied => '已复制';

  @override
  String get initErrorStackEmpty => '（堆栈为空）';

  @override
  String initErrorVersion(String version, String build) {
    return '版本 $version（$build）';
  }

  @override
  String get diffIgnoreWhitespace => '忽略空白';

  @override
  String get diffPreviousChange => '上一处更改';

  @override
  String get diffNextChange => '下一处更改';

  @override
  String get diffViewSideBySide => '并排';

  @override
  String get diffViewUnified => '统一';

  @override
  String get diffOpenSourceFile => '打开源文件';

  @override
  String get diffShowAllLines => '显示全部';

  @override
  String get diffNoChanges => '没有更改';

  @override
  String get fileDiffToggleFile => '文件';

  @override
  String get fileDiffToggleDiff => 'Diff';

  @override
  String diffChangeCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get notificationCenterTitle => '通知';

  @override
  String get notificationEmpty => '暂无通知';

  @override
  String get notificationMarkAllRead => '全部标为已读';

  @override
  String get notificationClearAll => '清空';

  @override
  String get notificationMarkRead => '标为已读';

  @override
  String get notificationDelete => '删除';

  @override
  String notificationSourceTerminal(String code) {
    return '终端 OSC $code';
  }

  @override
  String get notificationSourceAgent => '智能体';

  @override
  String get notificationTimeJustNow => '刚刚';

  @override
  String notificationTimeMinutesAgo(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String notificationTimeHoursAgo(int hours) {
    return '$hours 小时';
  }

  @override
  String notificationTimeDaysAgo(int days) {
    return '$days 天';
  }

  @override
  String get toolchainGit => 'Git';

  @override
  String get toolchainNode => 'Node.js';

  @override
  String get worktreeCreateTitle => '新建 worktree';

  @override
  String get worktreeBranchLabel => '分支名';

  @override
  String get worktreeModeNewBranch => '新建分支';

  @override
  String get worktreeModeExistingBranch => '已有分支';

  @override
  String get worktreeBaseRefLabel => '基线（可选）';

  @override
  String get worktreeBaseRefHint => '默认当前 HEAD';

  @override
  String get worktreePathLabel => '位置';

  @override
  String get worktreeStartConversation => '创建后在此开始一个会话';

  @override
  String get worktreeCreateAction => '创建';

  @override
  String worktreeCreateFailed(Object error) {
    return '创建 worktree 失败：$error';
  }

  @override
  String get worktreeNewWorktreeTooltip => '新建 worktree';

  @override
  String get worktreeRefreshTooltip => '刷新 worktree 列表';

  @override
  String get shortcutsWorkspaceNextTab => '下一个工作区标签';

  @override
  String get shortcutsWorkspacePrevTab => '上一个工作区标签';

  @override
  String get shortcutsWorkspaceCloseTab => '关闭工作区标签';

  @override
  String get shortcutsWorkspaceReopenClosed => '重新打开已关闭的工作区标签';

  @override
  String get shortcutsWorkspaceSearch => '搜索工作区';

  @override
  String get shortcutsStripNextTab => '下一个标签';

  @override
  String get shortcutsStripPrevTab => '上一个标签';

  @override
  String get shortcutsSessionNewTab => '新建终端';

  @override
  String get shortcutsSessionCloseTab => '关闭会话标签';

  @override
  String shortcutsStripFocusTab(int n) {
    return '切换到第 $n 个标签';
  }

  @override
  String get shortcutsToggleSidebar => '切换侧边栏';

  @override
  String get shortcutsTogglePanel => '切换终端面板';

  @override
  String get shortcutsToggleSecondarySidebar => '切换次侧边栏';

  @override
  String get shortcutsZoomIn => '放大';

  @override
  String get shortcutsZoomOut => '缩小';

  @override
  String get shortcutsZoomReset => '重置缩放';

  @override
  String get shortcutsComposeSubmit => '发送消息';

  @override
  String get shortcutsComposeNewline => '插入换行';

  @override
  String get shortcutsShowCheatsheet => '显示键盘快捷键';

  @override
  String get shortcutsCategoryNavigation => '导航';

  @override
  String get shortcutsCategoryTabs => '标签';

  @override
  String get shortcutsCategoryView => '视图';

  @override
  String get shortcutsCategoryZoom => '缩放';

  @override
  String get shortcutsCategoryCompose => '输入框';

  @override
  String get shortcutsCategoryMeta => '通用';

  @override
  String get shortcutsCategoryTerminal => '终端';

  @override
  String get shortcutsSettingsTitle => '键盘快捷键';

  @override
  String get shortcutsPageSubtitle => '查看并自定义导航、标签、缩放和输入框的键盘快捷键。';

  @override
  String get shortcutsSearchHint => '搜索快捷键';

  @override
  String get shortcutsChangeAction => '更改…';

  @override
  String get shortcutsResetAction => '恢复默认';

  @override
  String get shortcutsUnbindAction => '取消绑定';

  @override
  String get shortcutsNotSet => '未设置';

  @override
  String get shortcutsResetAll => '全部重置';

  @override
  String get shortcutsResetAllConfirmTitle => '重置所有快捷键？';

  @override
  String get shortcutsResetAllConfirmMessage => '这会将所有键盘快捷键恢复为默认绑定。';

  @override
  String get shortcutsExport => '导出…';

  @override
  String get shortcutsImport => '导入…';

  @override
  String get shortcutsExportSuccess => '快捷键已导出。';

  @override
  String get shortcutsExportFailed => '无法导出快捷键。';

  @override
  String get shortcutsImportSuccess => '快捷键已导入。';

  @override
  String get shortcutsImportInvalidFile => '该文件不是有效的快捷键导出文件。';

  @override
  String get shortcutsImportConflictTitle => '替换冲突的快捷键？';

  @override
  String shortcutsImportConflictMessage(int count) {
    return '导入的快捷键与 $count 个现有绑定冲突。是否替换？';
  }

  @override
  String get shortcutsCheatsheetButton => '查看速查表';

  @override
  String get shortcutsCheatsheetTitle => '键盘快捷键';

  @override
  String get shortcutsCheatsheetEmpty => '没有匹配的快捷键。';

  @override
  String get shortcutsPressShortcutTitle => '按下快捷键';

  @override
  String get shortcutsPressShortcutHint =>
      '按下组合键进行绑定。按 Escape 取消，按 Backspace 取消绑定。';

  @override
  String get shortcutsPressShortcutUnsupportedKey => '该键无法绑定。';

  @override
  String shortcutsConflictMessage(String title) {
    return '已被“$title”使用。';
  }

  @override
  String get shortcutsReplaceAction => '替换';

  @override
  String get shortcutsConflictBadgeTooltip => '与另一个快捷键冲突';

  @override
  String get runAction => '运行';

  @override
  String get runStop => '停止';

  @override
  String get runRestart => '重新运行';

  @override
  String get runNewInstance => '新实例';

  @override
  String get runDebug => '调试';

  @override
  String get runBuild => '构建';

  @override
  String get runSelectConfiguration => '选择配置';

  @override
  String runCompoundConfiguration(String name) {
    return '$name（组合）';
  }

  @override
  String runSuggestedConfiguration(String name) {
    return '$name（建议）';
  }

  @override
  String get runConfigurationTooltip => '运行配置';

  @override
  String get runAlreadyRunningTitle => '配置已在运行';

  @override
  String get runAlreadyRunningMessage => '重新运行当前会话，还是再启动一个新实例？';

  @override
  String get runStopSessionTitle => '停止正在运行的会话？';

  @override
  String runStopSessionMessage(String name) {
    return '“$name”仍在运行。停止并关闭此标签页？';
  }

  @override
  String get runStopAndClose => '停止并关闭';

  @override
  String get runNoSessions => '暂无运行会话';

  @override
  String get runClearExited => '清除已退出的会话';

  @override
  String get runLoadingOutput => '正在加载运行输出…';

  @override
  String get runEmptyOutputHint => '运行配置后，输出将显示在这里';

  @override
  String runTypeUnknown(String type) {
    return '未知启动类型：$type';
  }

  @override
  String runTypeUnavailable(String type) {
    return '启动类型“$type”在此目标上不可用';
  }

  @override
  String runTypeUnavailableRemote(String type) {
    return '启动类型“$type”在远程目标上不可用';
  }

  @override
  String get runConfigureLaunchItems => '配置启动项';

  @override
  String get runConfigurationsEmpty => '暂无启动配置';

  @override
  String get runEditConfigurations => '编辑配置';

  @override
  String get runAddConfiguration => '添加配置';

  @override
  String get runDeleteConfiguration => '删除';

  @override
  String runDeleteConfigurationConfirm(String name) {
    return '删除配置“$name”？';
  }

  @override
  String get runStopAndDelete => '停止并删除';

  @override
  String get runApply => '应用';

  @override
  String get runDiscard => '放弃';

  @override
  String get runDiscardChangesTitle => '放弃更改？';

  @override
  String get runDiscardChangesMessage => '此配置有未保存的更改。应用、放弃，还是取消？';

  @override
  String get runSelectFolder => '选择文件夹';

  @override
  String get runConfigurationName => '名称';

  @override
  String get runConfigurationType => '类型';

  @override
  String get runTypeShellScript => 'Shell 脚本';

  @override
  String get runFieldCommand => '命令';

  @override
  String get runFieldArgs => '参数';

  @override
  String get runFieldEnv => '环境变量';

  @override
  String get runFieldCwd => '工作目录';

  @override
  String get runFieldShell => '在 Shell 中运行';

  @override
  String get runFieldScriptPath => '脚本路径';

  @override
  String get runFieldScriptText => '脚本内容';

  @override
  String get runFieldExecute => '执行方式';

  @override
  String get runFieldScriptOptions => '脚本选项';

  @override
  String get runFieldInterpreterPath => '解释器路径';

  @override
  String get runFieldInterpreterOptions => '解释器选项';

  @override
  String get runFieldExecuteInTerminal => '在终端中执行';

  @override
  String get runFieldAllowMultipleInstances => '允许运行多个实例';

  @override
  String get runFieldActivateToolWindow => '激活工具窗口';

  @override
  String get runFieldFocusToolWindow => '聚焦工具窗口';

  @override
  String get runExecuteScriptFile => '脚本文件';

  @override
  String get runExecuteScriptText => '脚本内容';

  @override
  String get runValidationEnvMustBeStringMap => '环境变量必须是字符串映射';

  @override
  String get runValidationCwdMustBeString => '工作目录必须是字符串';

  @override
  String get runValidationConfigurationMustBeMap => '配置必须是对象';

  @override
  String get runValidationExecuteRequired => '必须选择执行方式';

  @override
  String get runValidationExecuteInvalid => '执行方式必须是脚本文件或脚本内容';

  @override
  String get runValidationScriptPathRequired => '脚本路径不能为空';

  @override
  String get runValidationScriptTextRequired => '脚本内容不能为空';

  @override
  String get runValidationInterpreterPathMustBeString => '解释器路径必须是字符串';

  @override
  String get runValidationExecuteInTerminalMustBeBoolean => '在终端中执行必须是布尔值';

  @override
  String get runValidationAllowMultipleInstancesMustBeBoolean =>
      '允许运行多个实例必须是布尔值';

  @override
  String get runValidationActivateToolWindowMustBeBoolean => '激活工具窗口必须是布尔值';

  @override
  String get runValidationFocusToolWindowMustBeBoolean => '聚焦工具窗口必须是布尔值';

  @override
  String get shortcutsRunSelected => '运行所选配置';

  @override
  String get shortcutsRunStop => '停止运行';

  @override
  String get shortcutsRunRestart => '重新运行';

  @override
  String get shortcutsCategoryRun => '运行';

  @override
  String get shortcutsCommandPalette => '命令面板';

  @override
  String get commandPaletteSearchHint => '输入命令…';

  @override
  String get commandPaletteEmpty => '没有匹配的命令';

  @override
  String get shortcutsTerminalSplitRight => '向右拆分终端';

  @override
  String get shortcutsTerminalSplitDown => '向下拆分终端';

  @override
  String get shortcutsTerminalFocusNextPane => '聚焦下一个窗格';

  @override
  String get shortcutsTerminalFocusPrevPane => '聚焦上一个窗格';

  @override
  String get shortcutsTerminalFocusPaneLeft => '聚焦左侧窗格';

  @override
  String get shortcutsTerminalFocusPaneRight => '聚焦右侧窗格';

  @override
  String get shortcutsTerminalFocusPaneUp => '聚焦上方窗格';

  @override
  String get shortcutsTerminalFocusPaneDown => '聚焦下方窗格';

  @override
  String get shortcutsTerminalZoomPane => '切换窗格最大化';

  @override
  String get shortcutsTerminalEqualizePanes => '均分窗格';

  @override
  String get shortcutsTerminalClosePane => '关闭窗格';

  @override
  String get shortcutsTerminalLayoutSingle => '布局：单窗格';

  @override
  String get shortcutsTerminalLayoutColumns2 => '布局：两列';

  @override
  String get shortcutsTerminalLayoutColumns3 => '布局：三列';

  @override
  String get shortcutsTerminalLayoutGrid => '布局：网格';

  @override
  String get shortcutsTerminalLayoutMainStack => '布局：主窗格 + 堆叠';

  @override
  String get shortcutsTerminalCommandLog => '显示命令日志';

  @override
  String get shortcutsTerminalCommandHistory => '显示命令历史';

  @override
  String get terminalColorSchemeTitle => '终端配色方案';

  @override
  String get terminalColorSchemeDescription => '为内置终端选择内建配色，或单独调整某些颜色。';

  @override
  String get terminalColorSchemeGroupDark => '暗色';

  @override
  String get terminalColorSchemeGroupLight => '亮色';

  @override
  String get terminalColorSchemeGroupLegacy => '自适应与经典';

  @override
  String terminalColorSchemeByAuthor(String author) {
    return '作者：$author';
  }

  @override
  String get terminalColorPreviewTitle => '预览';

  @override
  String get terminalUseCustomColorsTitle => '使用自定义颜色';

  @override
  String get terminalUseCustomColorsDescription => '在所选配色之上覆盖单个调色板槽位。';

  @override
  String get terminalCustomColorsSectionTitle => '自定义颜色';

  @override
  String get terminalColorResetAll => '全部重置';

  @override
  String get terminalColorResetSlot => '恢复为配色方案颜色';

  @override
  String get terminalColorInvalidHex => '请输入 #RRGGBB 或 #AARRGGBB';

  @override
  String get terminalSlotBackground => '背景';

  @override
  String get terminalSlotForeground => '前景';

  @override
  String get terminalSlotCursor => '光标';

  @override
  String get terminalSlotSelection => '选区';

  @override
  String get terminalSlotSearchHit => '搜索匹配';

  @override
  String get terminalSlotSearchHitCurrent => '当前匹配';

  @override
  String get terminalSlotSearchHitFg => '匹配文字';

  @override
  String get terminalSlotAccent => '强调色';

  @override
  String terminalSlotAnsiLabel(String index) {
    return 'ANSI $index';
  }

  @override
  String get terminalThemeImportAction => '导入主题…';

  @override
  String get terminalThemeImportTitle => '导入终端配色';

  @override
  String get terminalThemeImportDescription =>
      '在下方粘贴 Alacritty TOML 或 Ghostty 配置，也可以直接选择文件。';

  @override
  String get terminalThemeImportNameLabel => '主题名称';

  @override
  String get terminalThemeImportSourceLabel => '配色文件内容';

  @override
  String get terminalThemeImportChooseFile => '选择文件…';

  @override
  String get terminalThemeImportConfirm => '导入';

  @override
  String get terminalThemeImportFileReadFailed => '无法读取该文件。';

  @override
  String get terminalThemeImportEmptySource => '请先粘贴配色内容。';

  @override
  String get terminalThemeImportErrorFormat =>
      '无法识别的格式 — 需要 Alacritty TOML（[colors.primary]）或 Ghostty 的 key = value 行。';

  @override
  String get terminalThemeImportErrorBackground => '文件中没有可用的背景色。';

  @override
  String get terminalThemeImportErrorForeground => '文件中没有可用的前景色。';

  @override
  String get terminalThemeImportErrorAnsi => '缺少常规 ANSI 颜色（0-7）。';

  @override
  String get terminalThemeImportSaveFailed => '无法保存导入的主题。';

  @override
  String terminalThemeImportSuccess(String name) {
    return '已导入“$name”。';
  }

  @override
  String terminalThemeImportDerived(String slots) {
    return '以下颜色由调色板推导得出：$slots';
  }

  @override
  String get terminalColorSchemeGroupImported => '已导入';

  @override
  String get terminalThemeDeleteTooltip => '删除导入的主题';

  @override
  String get terminalThemeDeleteConfirmTitle => '删除导入的主题？';

  @override
  String terminalThemeDeleteConfirmMessage(String name) {
    return '将移除“$name”。仍在使用它的终端会回退到自适应配色。';
  }

  @override
  String get terminalThemeDeleteFailed => '无法删除该主题。';

  @override
  String get pairingSettingsTitle => '设备配对';

  @override
  String get pairingPageSubtitle => '在局域网内与手机配对，镜像并控制此桌面的终端。';

  @override
  String get pairingHostDesktopOnly => '设备配对主机仅在桌面端可用。';

  @override
  String get pairingEnableTitle => '允许手机通过局域网配对';

  @override
  String get pairingEnableSubtitle => '同一网络下的手机扫码后可镜像并控制此桌面的终端会话。';

  @override
  String get pairingScanToPair => '扫码配对';

  @override
  String get pairingNewCode => '刷新配对码';

  @override
  String get pairingGeneratingCode => '正在生成配对码…';

  @override
  String get pairingEnterAddressManually => '或手动输入以下任一地址：';

  @override
  String get pairingNoLanAddress => '未检测到局域网地址。';

  @override
  String get pairingPairedDevices => '已配对设备';

  @override
  String get pairingNoDevicesYet => '暂无已配对设备。';

  @override
  String get pairingRevoke => '撤销';

  @override
  String get pairingDesktops => '桌面';

  @override
  String get pairingScan => '扫码';

  @override
  String get pairingRemove => '移除';

  @override
  String get pairingNoPairedDesktops => '暂无已配对的桌面。';

  @override
  String get pairingEmptyHint => '在桌面端打开 TeamPilot，启用设备配对，然后扫描显示的二维码。';

  @override
  String get pairingScanQrCode => '扫描二维码';

  @override
  String get pairingWaitingForConnection => '等待连接…';

  @override
  String get pairingEnterManually => '手动输入';

  @override
  String get pairingPointAtQr => '对准桌面端 TeamPilot 显示的二维码。';

  @override
  String get pairingEnterPairingCode => '输入配对码';

  @override
  String get pairingCodeHint => 'teampilot://pair?code=… 或原始配对码';

  @override
  String get pairingInvalidCode => '不是有效的配对码或链接。';

  @override
  String get pairingPair => '配对';

  @override
  String get pairingConfirmTitle => '与桌面配对';

  @override
  String get pairingRetry => '重试';

  @override
  String get pairingConnect => '连接';

  @override
  String get pairingConnecting => '连接中…';

  @override
  String get pairingConnectionLost => '连接已断开，正在重连…';

  @override
  String get pairingReconnected => '已重新连接到桌面。';

  @override
  String get pairingFailed => '配对失败。';

  @override
  String get pairingReadyHint => '准备配对。请确保此手机与桌面处于同一网络，然后点击“连接”。';

  @override
  String get pairingDesktopFallback => '桌面';

  @override
  String get pairingRefresh => '刷新';

  @override
  String get pairingNoWorkspaces => '此桌面上没有工作区。';

  @override
  String get pairingWorkspaces => '工作区';

  @override
  String get pairingLiveBadge => '在线';

  @override
  String get pairingOfflineBadge => '离线';

  @override
  String get pairingActivating => '激活中…';

  @override
  String get pairingActivateFailed => '无法激活该会话。';

  @override
  String get pairingFallbackOpenedTerminal => '聊天会话不可用，已改为打开工作区终端。';

  @override
  String get pairingFromAlbum => '从相册选择';

  @override
  String get pairingNoQrInImage => '该图片中未找到配对二维码。';

  @override
  String get pairingManualCodeLabel => '或将此配对码复制到手机上：';

  @override
  String get pairingCopyCode => '复制配对码';

  @override
  String get pairingMirrorCopySelection => '复制';

  @override
  String get pairingCodeCopied => '配对码已复制。';

  @override
  String get pairingCodeTtlHint =>
      '配对码约 15 分钟内有效。若配对报 invalid token，请点“刷新配对码”后重新配对。';

  @override
  String pairingLastConnected(String time) {
    return '上次连接 $time';
  }

  @override
  String get pairingLanLabel => '局域网';

  @override
  String get pairingStepProgressTitle => '连接进度';

  @override
  String get pairingStageConnect => '连上桌面';

  @override
  String get pairingStageConnectNote => '拨号其局域网地址';

  @override
  String get pairingStageSecureChannel => '建立安全通道';

  @override
  String get pairingStageSecureChannelNote => '交换密钥并校验主机公钥';

  @override
  String get pairingStageAuthenticate => '校验配对码';

  @override
  String get pairingStageAuthenticateNote => '注册本设备';

  @override
  String get pairingStageLoadWorkspaces => '同步工作区';

  @override
  String get pairingStageLoadWorkspacesNote => '拉取会话与在线终端';

  @override
  String get pairingConnectionLogTitle => '连接日志';

  @override
  String pairingLogLineCount(int count) {
    return '$count 行';
  }

  @override
  String get pairingConnectedBadge => '已连接';

  @override
  String pairingRemovedUndo(String name) {
    return '已移除 $name';
  }

  @override
  String get pairingUndo => '撤销';

  @override
  String get pairingOpenTerminalHere => '在此打开终端';

  @override
  String get pairingNewTerminalHere => '新建终端';

  @override
  String get pairingCreate => '创建';

  @override
  String get pairingNewWorkspace => '新建工作区';

  @override
  String get pairingNewGroup => '新建分组';

  @override
  String get pairingNewGroupNameHint => '例如：客户项目';

  @override
  String get pairingNewGroupNameLabel => '分组名称';

  @override
  String get pairingNewGroupHelp => '创建在已配对的桌面端，桌面端会立刻出现。';

  @override
  String get pairingNewGroupDuplicate => '已存在同名分组，换一个名字。';

  @override
  String get pairingCreating => '创建中…';

  @override
  String get pairingGroupCreateFailed => '无法创建分组。';

  @override
  String get pairingWorkspaceCreateFailed => '无法创建工作区。';

  @override
  String get pairingNewWorkspaceFolderLabel => '文件夹';

  @override
  String get pairingNewWorkspaceNameLabel => '名称';

  @override
  String get pairingNewWorkspaceNameHint => '默认使用文件夹名';

  @override
  String pairingNewWorkspaceNameHintFolder(String name) {
    return '默认使用文件夹名（$name）';
  }

  @override
  String get pairingNewWorkspaceSubtitle => '工作区指向主机上的一个目录，会话都在该目录里启动。';

  @override
  String get pairingNewWorkspaceFolderHelp => '选主机上的目录，不是手机本地目录。';

  @override
  String get pairingNewWorkspaceFolderPicked => '会话都在该目录里启动。';

  @override
  String get pairingNoFolderSelected => '未选择目录';

  @override
  String get pairingFieldRequired => '必填';

  @override
  String get pairingFieldOptional => '可选';

  @override
  String get pairingNewWorkspaceGroupLabel => '分组';

  @override
  String get pairingBrowseFolder => '浏览';

  @override
  String get pairingSelectFolderFirst => '请先选择一个文件夹。';

  @override
  String get pairingSelectThisFolder => '选择此文件夹';

  @override
  String get pairingParentDirectory => '上级目录';

  @override
  String get pairingBrowseTitle => '选择文件夹';

  @override
  String get pairingBrowseEmpty => '此处没有子文件夹。';

  @override
  String get pairingBrowseFailed => '无法列出该文件夹。';

  @override
  String pairingBrowseTitleOn(String target) {
    return '在 $target 上选择文件夹';
  }

  @override
  String get pairingChangesFailed => '无法从桌面端读取更改。';

  @override
  String pairingChangesBranch(String branch) {
    return '位于 $branch';
  }

  @override
  String get pairingDiffEmpty => '该文件没有差异。';

  @override
  String get pairingDiffFailed => '无法加载差异。';

  @override
  String get pairingNewWorkspaceTargetLabel => '机器';

  @override
  String get mobileToolbarHideKeyboard => '收起键盘';

  @override
  String get mobileToolbarCustomize => '自定义按键';

  @override
  String mobileToolbarVisibleGroups(int count) {
    return '显示组数：$count';
  }

  @override
  String get mobileToolbarMostUsed => '高频按键';

  @override
  String get mobileToolbarReorderHint => '拖动排序，靠前的组显示在工具栏左侧。';

  @override
  String get mobileToolbarReset => '恢复默认';

  @override
  String get mobileToolbarGroupArrows => '方向键';

  @override
  String get mobileToolbarGroupClipboard => '剪贴板';

  @override
  String get mobileToolbarGroupTerminalCtrl => '终端控制';

  @override
  String get mobileToolbarGroupSignals => '信号';

  @override
  String get mobileToolbarGroupSymbols1 => '符号 1';

  @override
  String get mobileToolbarGroupNavigation => '导航';

  @override
  String get mobileToolbarGroupEditing => '编辑';

  @override
  String get mobileToolbarGroupSearch => '搜索';

  @override
  String get mobileToolbarGroupPunctuation => '标点';

  @override
  String get mobileToolbarGroupSymbols2 => '符号 2';

  @override
  String get mobileToolbarGroupBrackets1 => '括号 1';

  @override
  String get mobileToolbarGroupBrackets2 => '括号 2';

  @override
  String get mobileToolbarGroupFkeys1 => 'F1–F4';

  @override
  String get mobileToolbarGroupFkeys2 => 'F5–F8';

  @override
  String get mobileToolbarGroupFkeys3 => 'F9–F12';

  @override
  String get mobileToolbarGroupAdvanced => '高级控制';

  @override
  String get mobileComposerHint => '输入命令';

  @override
  String get mobileComposerOpen => '文本输入';

  @override
  String get mobileComposerClose => '关闭输入面板';

  @override
  String get mobileComposerSend => '发送';

  @override
  String get mobileComposerSubmitOn => '发送时回车';

  @override
  String get mobileComposerSubmitOff => '发送不回车';

  @override
  String get mobileComposerAttach => '附加图片或视频';

  @override
  String get mobileComposerCancelUpload => '取消上传';

  @override
  String mediaUploadProgress(int percent, int sent, int total) {
    return '$percent% · $sent/$total MB';
  }

  @override
  String get mediaUploadFailed => '上传失败';

  @override
  String mediaUploadImageTooLarge(int mb) {
    return '图片超过 $mb MB';
  }

  @override
  String mediaUploadVideoTooLarge(int mb) {
    return '视频超过 $mb MB';
  }

  @override
  String get mediaUploadUnsupportedType => '不支持该文件类型';

  @override
  String get voiceInputStart => '开始语音输入';

  @override
  String get voiceInputStop => '停止语音输入';

  @override
  String get voiceInputBadgeSystem => '系统';

  @override
  String get voiceInputBadgeVolcengine => '豆包';

  @override
  String get voiceInputBadgeAliyun => '阿里';

  @override
  String get voiceInputPermissionDenied => '麦克风权限被拒绝，请在系统设置中开启';

  @override
  String get voiceInputFailed => '语音输入失败';

  @override
  String get voiceInputSettings => '语音输入';

  @override
  String get voiceInputProvider => '识别服务';

  @override
  String get voiceInputProviderSystem => '系统';

  @override
  String get voiceInputProviderVolcengine => '豆包（火山引擎）';

  @override
  String get voiceInputProviderAliyun => '阿里云智能语音';

  @override
  String get voiceInputLanguage => '识别语言';

  @override
  String get voiceInputLanguageDefault => '跟随系统';

  @override
  String get voiceInputCredentials => '凭据';

  @override
  String get voiceInputVolcAppId => 'App ID';

  @override
  String get voiceInputVolcAccessToken => 'Access Token';

  @override
  String get voiceInputAliyunAccessKeyId => 'AccessKey ID';

  @override
  String get voiceInputAliyunAccessKeySecret => 'AccessKey Secret';

  @override
  String get voiceInputAliyunAppKey => 'App Key';

  @override
  String get voiceInputTestConnection => '测试连接';

  @override
  String voiceInputTestPassed(int ms) {
    return '连接成功，耗时 $ms 毫秒';
  }

  @override
  String get voiceInputTestFailed => '连接失败';

  @override
  String get voiceInputCloudPrivacyNote => '音频将直接发送给云服务商，不经过端到端加密的配对通道。';
}
