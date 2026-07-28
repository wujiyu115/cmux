/// Stable command identifiers for the v1 keyboard shortcut catalog.
abstract final class CommandIds {
  // Workspace tabs
  static const String workspaceNextTab = 'workbench.workspace.nextTab';
  static const String workspacePrevTab = 'workbench.workspace.prevTab';
  static const String workspaceCloseTab = 'workbench.workspace.closeTab';
  static const String workspaceReopenClosed = 'workbench.workspace.reopenClosed';
  static const String workspaceSearch = 'workbench.workspace.search';

  // Workbench strip tabs (session / file / diff / shell / run)
  static const String stripNextTab = 'workbench.strip.nextTab';
  static const String stripPrevTab = 'workbench.strip.prevTab';
  static const String sessionNewTab = 'workbench.session.newTab';
  static const String sessionCloseTab = 'workbench.session.closeTab';

  /// 1-based ordinal → `workbench.strip.focusTabN` (N = 1…10).
  /// Bound to Alt+1…9 / Alt+0 (10th tab).
  static String stripFocusTab(int oneBased) {
    assert(oneBased >= 1 && oneBased <= 10);
    return 'workbench.strip.focusTab$oneBased';
  }

  /// All [stripFocusTab] ids in ordinal order (1…10).
  static final List<String> stripFocusTabs = [
    for (var n = 1; n <= 10; n++) stripFocusTab(n),
  ];

  // View
  static const String toggleSidebar = 'workbench.view.toggleSidebar';
  static const String togglePanel = 'workbench.view.togglePanel';
  static const String toggleSecondarySidebar =
      'workbench.view.toggleSecondarySidebar';

  // Zoom
  static const String zoomIn = 'workbench.zoom.in';
  static const String zoomOut = 'workbench.zoom.out';
  static const String zoomReset = 'workbench.zoom.reset';

  // Compose
  static const String composeSubmit = 'compose.submit';
  static const String composeNewline = 'compose.newline';

  // Meta
  static const String showCheatsheet = 'workbench.shortcuts.showCheatsheet';

  // Run
  static const String runRunSelected = 'run.runSelected';
  static const String runStop = 'run.stop';
  static const String runRestart = 'run.restart';

  // Terminal panes
  static const String terminalSplitRight = 'terminal.split.right';
  static const String terminalSplitDown = 'terminal.split.down';
  static const String terminalPaneFocusNext = 'terminal.pane.focusNext';
  static const String terminalPaneFocusPrev = 'terminal.pane.focusPrev';
  static const String terminalPaneFocusLeft = 'terminal.pane.focusLeft';
  static const String terminalPaneFocusRight = 'terminal.pane.focusRight';
  static const String terminalPaneFocusUp = 'terminal.pane.focusUp';
  static const String terminalPaneFocusDown = 'terminal.pane.focusDown';
  static const String terminalPaneZoom = 'terminal.pane.zoom';
  static const String terminalPaneEqualize = 'terminal.pane.equalize';
  static const String terminalPaneClose = 'terminal.pane.close';
  static const String terminalLayoutSingle = 'terminal.layout.single';
  static const String terminalLayoutColumns2 = 'terminal.layout.columns2';
  static const String terminalLayoutColumns3 = 'terminal.layout.columns3';
  static const String terminalLayoutGrid = 'terminal.layout.grid';
  static const String terminalLayoutMainStack = 'terminal.layout.mainStack';

  // App
  static const String commandPalette = 'app.commandPalette';
}
