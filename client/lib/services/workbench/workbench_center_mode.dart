import '../commands/command_ids.dart';

enum WorkbenchCenterMode { welcome, tab }

/// Single source of truth for workspace center chrome/body.
WorkbenchCenterMode resolveWorkbenchCenterMode({
  required Object? activeTabId,
}) {
  if (activeTabId == null) return WorkbenchCenterMode.welcome;
  return WorkbenchCenterMode.tab;
}

/// Fixed welcome shortcut rows (labels via [titleForCommand]).
const List<String> kWorkbenchWelcomeCommandIds = [
  CommandIds.sessionNewTab,
  CommandIds.togglePanel,
  CommandIds.toggleSidebar,
  CommandIds.quickOpen,
  CommandIds.showCheatsheet,
];
