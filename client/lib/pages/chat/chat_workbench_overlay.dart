/// Which full-pane overlay sits above the (possibly offstage) terminal.
enum ChatWorkbenchOverlay {
  /// Remote CLI provision progress.
  remoteProvision,

  /// Full-screen session-starting spinner.
  sessionStarting,

  /// No overlay; terminal (or empty) fills the pane.
  none,
}

/// Resolves the workbench center overlay.
ChatWorkbenchOverlay resolveChatWorkbenchOverlay({
  required bool sessionConnectInProgress,
  required bool showRemoteProvision,
}) {
  if (showRemoteProvision) return ChatWorkbenchOverlay.remoteProvision;
  if (sessionConnectInProgress) return ChatWorkbenchOverlay.sessionStarting;
  return ChatWorkbenchOverlay.none;
}
