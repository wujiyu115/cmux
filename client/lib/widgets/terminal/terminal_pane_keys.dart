import 'package:flutter/widgets.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../workspace_terminal_panel.dart' show kWorkspaceTerminalViewDebugLabel;

/// Stable per-pane [GlobalKey<TerminalViewState>] store.
///
/// Keys are created once per paneId and reused for the lifetime of the pane:
/// creating a fresh key per build would remount the underlying [TerminalView]
/// and drop terminal / glyph-cache state. Owned by the panel state (not the
/// split widget) so keys survive split-tree rebuilds and reordering.
class TerminalPaneKeys {
  final Map<String, GlobalKey<TerminalViewState>> _keys = {};

  /// The stable key for [paneId], creating it on first use.
  GlobalKey<TerminalViewState> keyFor(String paneId) => _keys.putIfAbsent(
        paneId,
        () => GlobalKey<TerminalViewState>(
          debugLabel: '$kWorkspaceTerminalViewDebugLabel:$paneId',
        ),
      );

  /// The mounted [TerminalViewState] for [paneId], or null when not mounted.
  TerminalViewState? stateFor(String paneId) => _keys[paneId]?.currentState;

  /// All currently-mounted pane states (offstage panes included).
  Iterable<TerminalViewState> get mountedStates sync* {
    for (final key in _keys.values) {
      final state = key.currentState;
      if (state != null) yield state;
    }
  }

  /// Drops keys for panes not in [livePaneIds] (panes that are gone).
  void prune(Set<String> livePaneIds) {
    _keys.removeWhere((id, _) => !livePaneIds.contains(id));
  }

  /// Forgets every key.
  void clear() => _keys.clear();
}
