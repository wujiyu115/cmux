import '../../cubits/workbench/workbench_tab.dart';
import '../../models/run/run_ui_intent.dart';

/// Maps a [RunUiIntent] to the workbench shell/run tab to activate, or null
/// when the intent should not switch the active tool surface.
WorkbenchTabId? resolveWorkbenchTabForRunIntent(
  RunUiIntent intent, {
  required String? latestRunSessionId,
  String? Function(String paneId)? terminalSurfaceForPane,
}) {
  if (!intent.activateToolWindow) return null;
  switch (intent.surface) {
    case RunToolSurface.terminal:
      final id = intent.terminalEntryId?.trim();
      if (id == null || id.isEmpty) return null;
      // Strip tabs are keyed by surface; map the injected pane to its owning
      // surface (falls back to the pane id when unmapped, e.g. in unit tests).
      final surfaceId = terminalSurfaceForPane?.call(id) ?? id;
      return WorkbenchTabId.shell(surfaceId);
    case RunToolSurface.run:
      final id = latestRunSessionId?.trim();
      if (id == null || id.isEmpty) return null;
      return WorkbenchTabId.run(id);
  }
}
