import '../../models/terminal_surface.dart';
import 'workspace_terminal_registry.dart';

/// IDEA-style tab labels: `Local`, `Local (2)`, `user@host`, …
abstract final class WorkspaceTerminalTitleResolver {
  WorkspaceTerminalTitleResolver._();

  static String tabTitle({
    required WorkspaceTerminalEntry entry,
    required List<WorkspaceTerminalEntry> siblings,
    required String baseLabel,
  }) {
    final sameBase = siblings
        .where((e) => e.titleLabel == baseLabel)
        .toList(growable: false);
    if (sameBase.length <= 1) return baseLabel;
    final index = sameBase.indexWhere((e) => e.id == entry.id) + 1;
    return '$baseLabel ($index)';
  }

  /// Label for a strip tab that is a whole surface (split tree). The base is the
  /// surface's own name, or the focused pane's label; duplicates are numbered
  /// across surfaces (not across the panes within one), so splitting a tab never
  /// changes its title.
  static String surfaceTabTitle({
    required TerminalSurface surface,
    required List<TerminalSurface> siblings,
    required WorkspaceTerminalEntry? Function(String paneId) entryFor,
  }) {
    final base = _surfaceBaseLabel(surface, entryFor);
    final sameBase = siblings
        .where((s) => _surfaceBaseLabel(s, entryFor) == base)
        .toList(growable: false);
    if (sameBase.length <= 1) return base;
    final index = sameBase.indexWhere((s) => s.id == surface.id) + 1;
    return '$base ($index)';
  }

  static String _surfaceBaseLabel(
    TerminalSurface surface,
    WorkspaceTerminalEntry? Function(String paneId) entryFor,
  ) {
    if (surface.name.isNotEmpty) return surface.name;
    final label = entryFor(surface.focusedPaneId)?.titleLabel ?? '';
    return label.isEmpty ? '…' : label;
  }
}
