import 'package:flutter/foundation.dart';

import '../../models/terminal_split.dart';
import '../terminal/terminal_layout_presets.dart';
import 'command_bus.dart';
import 'command_ids.dart';

/// The terminal split/focus/layout actions the pane commands drive.
///
/// Implemented by the workspace terminal panel; each method is a thin adapter
/// over the panel's private split methods. Handlers must be no-ops when there
/// is no active surface (the host guards internally).
abstract class TerminalSplitCommandHost {
  void splitRight();
  void splitDown();
  void focusNextPane();
  void focusPrevPane();
  void focusPaneInDirection(PaneDirection direction);
  void toggleZoom();
  void equalizePanes();
  void closeActivePane();
  void applyLayoutPreset(TerminalLayoutPreset preset);
}

/// Wires the terminal split/focus/layout commands onto [bus] against [host].
///
/// Unlike the app-lifetime registrars (layout / session), several terminal
/// panels can be alive at once (one per open workspace tab, kept alive
/// offstage), so registration is claimed on focus and released on dispose.
///
/// Returns a disposer that unregisters exactly the handlers it registered
/// (identity-guarded via [CommandBus.unregister], so a stale disposer never
/// clobbers a newer panel's claim).
VoidCallback registerTerminalSplitCommands(
  CommandBus bus,
  TerminalSplitCommandHost host,
) {
  final handlers = <String, CommandHandler>{
    CommandIds.terminalSplitRight: host.splitRight,
    CommandIds.terminalSplitDown: host.splitDown,
    CommandIds.terminalPaneFocusNext: host.focusNextPane,
    CommandIds.terminalPaneFocusPrev: host.focusPrevPane,
    CommandIds.terminalPaneFocusLeft: () =>
        host.focusPaneInDirection(PaneDirection.left),
    CommandIds.terminalPaneFocusRight: () =>
        host.focusPaneInDirection(PaneDirection.right),
    CommandIds.terminalPaneFocusUp: () =>
        host.focusPaneInDirection(PaneDirection.up),
    CommandIds.terminalPaneFocusDown: () =>
        host.focusPaneInDirection(PaneDirection.down),
    CommandIds.terminalPaneZoom: host.toggleZoom,
    CommandIds.terminalPaneEqualize: host.equalizePanes,
    CommandIds.terminalPaneClose: host.closeActivePane,
    CommandIds.terminalLayoutSingle: () =>
        host.applyLayoutPreset(TerminalLayoutPreset.single),
    CommandIds.terminalLayoutColumns2: () =>
        host.applyLayoutPreset(TerminalLayoutPreset.columns2),
    CommandIds.terminalLayoutColumns3: () =>
        host.applyLayoutPreset(TerminalLayoutPreset.columns3),
    CommandIds.terminalLayoutGrid: () =>
        host.applyLayoutPreset(TerminalLayoutPreset.grid2x2),
    CommandIds.terminalLayoutMainStack: () =>
        host.applyLayoutPreset(TerminalLayoutPreset.mainStack),
  };
  handlers.forEach(bus.register);
  return () {
    for (final entry in handlers.entries) {
      bus.unregister(entry.key, entry.value);
    }
  };
}
